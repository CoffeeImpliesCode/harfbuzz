// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//! HarfBuzz-specific configuration for runtime provider loading.
//! Defines provider validation, process-wide synchronization, and ABI requirements.

const std = @import("std");
const rt = @import("rt");

// ABI: `hb_position_t` is signed 32-bit font design units divided by its scale (default: `unitsPerEm`).
// HarfBuzz allocates through libc, outside Zig allocator and leak checking.
// Providers must match the C++ ABI as well as the version; FreeType-backed fonts are not thread-safe.
// FreeType declarations stay direct, so a HarfBuzz provider need not export FT symbols.

/// Process-wide synchronization binding used by the runtime loader.
/// Its prefix must match `runtime/graph.zig` and `runtime/sync.c`.
pub const Sync = struct {
    extern fn harfbuzz_rt_lock() void;
    extern fn harfbuzz_rt_unlock() void;
    extern fn harfbuzz_rt_wait() void;
    extern fn harfbuzz_rt_broadcast() void;
    // C `unsigned long long` is 64 bits on every supported target.
    extern fn harfbuzz_rt_thread_self() u64;

    pub fn lock() void {
        harfbuzz_rt_lock();
    }
    pub fn unlock() void {
        harfbuzz_rt_unlock();
    }
    pub fn wait() void {
        harfbuzz_rt_wait();
    }
    pub fn broadcast() void {
        harfbuzz_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return harfbuzz_rt_thread_self();
    }
};

/// Header version required from a provider.
const expected_version: [3]c_uint = .{ 14, 5, 1 };

/// Load-time report for this package's build with sibling FreeType.
const config_name = "HAVE_FREETYPE from the sibling ../freetype source tree; HB_NO_FREETYPE not defined";

/// Builds the loader descriptor for the generated dispatch type.
/// Passing the type avoids a dependency on generated code.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name reported by the loader and used as its state key.
        pub const library_name = "harfbuzz";

        /// The generated dispatch table type.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;
        pub const sync = Sync;

        /// Returns the process-wide dispatch table.
        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        /// Returns the readiness flag guarding table access.
        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Checks the provider's HarfBuzz version and ability to allocate a buffer.
        /// Returns a diagnostic on failure; does not test shaping.
        pub fn validate(dst: *const table) ?[]const u8 {
            var major: c_uint = 0;
            var minor: c_uint = 0;
            var micro: c_uint = 0;
            dst.hb_version(&major, &minor, &micro);
            const seen = [3]c_uint{ major, minor, micro };
            if (!std.mem.eql(c_uint, &seen, &expected_version)) {
                std.debug.print(
                    "harfbuzz: provider reports {d}.{d}.{d}, this SDK's headers " ++
                        "describe {d}.{d}.{d}; they are different external ABIs\n",
                    .{ major, minor, micro, expected_version[0], expected_version[1], expected_version[2] },
                );
                return "this provider implements a different HarfBuzz ABI family " ++
                    "than the one this SDK's headers describe";
            }
            // A zero-argument buffer checks that the provider can allocate and destroy a basic object.
            const buffer = dst.hb_buffer_create() orelse return "hb_buffer_create returned null, so this provider's allocator " ++
                "could not satisfy an empty buffer";
            dst.hb_buffer_destroy(buffer);
            return null;
        }

        /// Returns the build configuration string for load-time reports.
        pub fn describeConfiguration() []const u8 {
            return config_name;
        }
    };
}
