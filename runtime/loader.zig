// SPDX-License-Identifier: MIT
//
//! Thread-safe loader for generated C dispatch tables; opens one explicit provider and publishes only after resolution and validation.
//! Successful handles and request copies live for the process; failures publish nothing and require an explicit retry.
//! A provider constructor that waits for another thread calling `load` can deadlock.

const std = @import("std");
const builtin = @import("builtin");

/// Selects an explicit file path or platform loader name; neither falls back to the other.
/// Paths must be absolute; system names cannot contain separators or NUL bytes.
pub const LoadSource = union(enum) {
    /// Absolute file path; relative paths are invalid.
    path: []const u8,
    /// Basename or SONAME; separators and NUL bytes are invalid.
    system: []const u8,
};

/// Errors returned when a load request is refused.
pub const LoadError = error{
    /// Empty path or system name.
    EmptySource,
    /// Request exceeds `max_source_len`; it is never truncated.
    SourceTooLong,
    /// Path is not absolute, or a system name has a path component or NUL.
    InvalidSource,
    /// Target has no dynamic loader; no provider was opened.
    UnsupportedTarget,
    /// Platform loader could not open the provider or its dependencies.
    OpenFailed,
    /// A required export is missing; the candidate is closed.
    MissingSymbol,
    /// Provider validation failed; the candidate is closed.
    ValidationFailed,
    /// A different provider is already loaded or being loaded.
    ProviderMismatch,
    /// The loading thread called `load` reentrantly.
    ReentrantLoad,
};

/// The longest request the loader will remember, in bytes.
pub const max_source_len = 32768;

/// Fixed-size copy of the request, retained for process lifetime.
const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    /// Called under the loader lock after checking the request length.
    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Returns the remembered request; its bytes point into this record.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Compares request kind and bytes exactly; paths are not normalized.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// States of a configured module's dispatch table.
pub const Phase = enum(u8) {
    /// No provider loaded; failed attempts return here for explicit retry.
    not_loaded = 0,
    /// One thread is resolving and validating the provider.
    loading = 1,
    /// The table is published and routed calls may proceed.
    ready = 2,
};

/// Readiness flag for the dispatch table.
/// A release store publishes all table fields to callers using acquire loads.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@intFromEnum(Phase.not_loaded)),

    /// True after a successful load, using one acquire load.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @intFromEnum(Phase.ready);
    }

    /// Returns the current state.
    pub fn state(self: *const Ready) Phase {
        return @enumFromInt(self.phase.load(.acquire));
    }

    /// Publishes the new state with release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@intFromEnum(value), .release);
    }
};

/// Required export kind: function pointers or addresses of provider data.
pub const SymbolKind = enum {
    /// Function address with the translated header's exact function-pointer type.
    function,
    /// Object address, not a copy, so provider-side writes remain visible.
    data,
};

/// One required export: the name to look up and what kind of thing it is.
pub const Symbol = struct {
    /// The exported name, exactly as the C header spells it.
    name: [:0]const u8,
    /// What the table field holds for this symbol.
    kind: SymbolKind,
};

/// Panics in every optimization mode when a routed call precedes successful load.
/// The message names the library and symbol.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether the target has a dynamic loader; unsupported targets return `UnsupportedTarget`.
pub const supported_target: bool = switch (builtin.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Defines the process-global loader type for one generated dispatch configuration.
/// Same-source calls share attempts; failures may be retried, mismatches/reentry fail, and success retains the handle.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// The generated dispatch table type.
        pub const table_type = Config.table;

        /// In-flight attempt, retained until all waiters consume its result.
        attempt: ?Attempt = null,

        /// Request copy; accessed under the lock before readiness, immutable after publication.
        request: SourceRecord = .{},

        /// Resolves and validates the named provider before publishing the table.
        /// Concurrent same-source calls share the result; failed loads remain unpublished and may be retried.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Join the in-flight same-source attempt; do not start another.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the result until every waiter consumes it; then a retry may replace it.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // A retry waits for the prior attempt's waiters to drain.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Run provider constructors without the lock; other callers wait on this attempt.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Wake all attached waiters; each must read this attempt's result.
            Config.sync.broadcast();
            // Keep the record until waiters drain, then wake callers waiting to retry.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Returns the retained request after success, or null before success.
        /// Returned bytes point into process-lifetime loader storage.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            // The acquire load precedes every call to accept.
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Opens, resolves, and validates without holding the lock.
        /// Failed candidates are closed; only the caller can publish success.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // Keep the handle open; published table addresses remain inside it.
            retain = true;
        }
    };
}

/// One in-flight or undrained load attempt.
const Attempt = struct {
    /// Identity of the thread running the attempt, for the reentrancy check.
    owner: u64,
    /// Result written under lock before readiness changes; waiters read it after waking.
    result: LoadError!void = error.OpenFailed,
    /// Attached waiters; record remains until all consume the result.
    waiters: usize = 0,
};

/// Windows path buffer limit: 32,768 UTF-16 units; accepted UTF-8 requests fit.
const windows_path_units = 32768;

const platform = if (builtin.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

/// Dynamic-loader stub; every request returns `UnsupportedTarget`.
const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // `RTLD_NOW` reports missing dependencies at open; `RTLD_LOCAL` avoids global symbol collisions.
        return std.c.dlopen(
            // `dlopen` requires a sentinel-terminated path.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Basenames search standard directories; paths load as named, without current-directory search.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
