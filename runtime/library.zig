// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//! HarfBuzz's side of the runtime loader: the names its synchronization
//! binding has, what it requires of a provider beyond resolving its symbols,
//! and what the external ABI boundary for this provider actually is.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! HarfBuzz's, and it is the file another SDK replaces.

const std = @import("std");
const rt = @import("rt");

/// What a provider must export, and what it must answer correctly.
///
/// `zig/translate.h` includes the public `hb-*.h` headers plus `<hb-ft.h>`,
/// which in turn includes `<ft2build.h>` and `FT_FREETYPE_H`. Every `hb_*`
/// declaration that reaches the translation is routed: this configuration has
/// no optional entry points, so `provider_optional` and `provider_excluded` in
/// `runtime/graph.zig` are both empty and a provider that exports only part of
/// the header-declared API is refused rather than half used.
///
/// The FreeType declarations `hb-ft.h` reaches are *not* owed by a HarfBuzz
/// provider. They are classified as noise in `runtime/graph.zig` alongside the
/// C library's, for a sharper reason: a HarfBuzz provider that was built
/// without FreeType — `HB_NO_FREETYPE`, an upstream-supported configuration — is
/// a conforming provider for everything else in this header, and asking it for
/// `FT_Init_FreeType` would refuse it. This package's default build *does* have
/// the sibling FreeType (`build.zig` defines `HAVE_FREETYPE`), so
/// `hb_ft_font_create` and the rest resolve; a provider without it is a
/// documented, narrower provider, not a broken one, and the facade reports the
/// gap rather than calling through a null entry.
///
/// ## The external ABI boundary, stated honestly
///
/// HarfBuzz's ABI family is `HB_VERSION_MAJOR`/`HB_VERSION_MINOR`/`HB_VERSION_MICRO`
/// — read out of `src/hb-version.h:44`, `:50` and `:56`, which are 14, 5 and 1
/// for the release this package vendors — and the same three numbers are what
/// `hb_version()` answers at run time: `src/hb-common.cc:640-642` assigns those
/// three macros to the caller's out-parameters, under the declaration at
/// `src/hb-version.h:79-82`. That is the check `validate` makes below.
///
/// What crosses that boundary, and what a caller must know:
///
///   * Every `hb_position_t` is a signed 32-bit count of *font design units*
///     divided by the font's scale. `hb_font_set_scale` is what decides those
///     units, and the default scale is the face's own `unitsPerEm`. A caller
///     that mixes a scale of 1000 with a scale of 1000 * 64 gets positions that
///     differ by exactly 64 and nothing complains.
///   * Memory crosses into HarfBuzz's own allocator. There is no
///     `src/hb-malloc.cc` in this release: `src/hb.hh:555-558` defines
///     `hb_malloc_impl`, `hb_calloc_impl`, `hb_realloc_impl` and `hb_free_impl`
///     as `malloc`, `calloc`, `realloc` and `free`, in the arm of
///     `HB_CUSTOM_MALLOC` that is not taken here. So a Zig allocator can neither
///     bound nor intercept it, and
///     `zig/std`'s leak checking has no oracle for it. This package's tests
///     therefore prove behaviour, never absence of leaks.
///   * HarfBuzz is thread-safe and HarfBuzz-over-FreeType is **not**.
///     `src/hb-ft.cc:66-67` says so: "FreeType is not thread-safe, therefore
///     these functions are not thread-safe either". A process that shapes from
///     several threads must not put one `hb_ft_font_t` in more than one of
///     them.
///   * The whole library is one C++ translation unit (`src/harfbuzz.cc`), so a
///     provider's C++ ABI is part of its interface: the same standard library,
///     the same `-fno-exceptions`/`-fno-rtti` settings `build.zig` uses. Two
///     providers built with different settings are not interchangeable even at
///     the same version number, which is why the version check is a necessary
///     condition and not a sufficient one.

/// The process-wide synchronization this SDK's loader uses.
///
/// The prefix `harfbuzz_rt` is spelled in exactly two places: the `extern`
/// names below and `runtime/graph.zig`'s `sync_prefix`, which is what
/// `runtime/sync.c` is compiled with. A build where the two disagree does not
/// link, and that is the whole error report — there is no runtime path that
/// could hide it.
pub const Sync = struct {
    extern fn harfbuzz_rt_lock() void;
    extern fn harfbuzz_rt_unlock() void;
    extern fn harfbuzz_rt_wait() void;
    extern fn harfbuzz_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
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

/// The HarfBuzz release the vendored headers describe.
///
/// Read out of `src/hb-version.h:44`, `:50` and `:56`. It is the version of the
/// C++ library this package compiles, not a version of this wrapper.
const expected_version: [3]c_uint = .{ 14, 5, 1 };

/// The configuration this package builds with, for a load-time report.
///
/// `HB_NO_FREETYPE` is **not** defined in the default configuration:
/// `build.zig` defines `HAVE_FREETYPE` and puts the sibling FreeType's
/// `include/` on the compile line, so `src/hb-ft.cc` compiles and
/// `hb_ft_font_create` is available, and that is the only configuration there
/// is: `-Dfreetype=none` is **refused** at configure time rather than accepted,
/// so `HB_NO_FREETYPE` is never defined by this package and a provider built
/// from these sources always carries the FreeType integration.
const config_name = "HAVE_FREETYPE from the sibling ../freetype source tree; HB_NO_FREETYPE not defined";

/// The descriptor the generated dispatch builds its loader over.
///
/// `dispatch` is passed as a type rather than imported, so this file never
/// depends on generated code: the dependency runs one way only, and a build that
/// could see both halves would have a cycle.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// The name `load` reports and the name the loader state is keyed on.
        pub const library_name = "harfbuzz";

        /// The one table this process will ever publish, one per build.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;
        pub const sync = Sync;

        /// Where the single published table lives.
        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        /// The readiness flag every routed call pays one acquire load for.
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

        /// What this SDK checks about a provider *after* every symbol resolved.
        ///
        /// Two questions, both of which answer rather than abort, because a
        /// loader that has to report `ValidationFailed` can only run checks
        /// that return.
        ///
        /// 1. Does `hb_version` report the version these headers describe?
        /// 2. Can the provider allocate and release an object at all? A buffer
        ///    is the cheapest HarfBuzz object that crosses the allocator
        ///    boundary, it takes no argument (so this descriptor never has to
        ///    name a translated enum value, which is a constant on the
        ///    `c_native` side and not a field of this table), and every other
        ///    object is built on one.
        ///
        /// Deliberately **not** checked: shaping. `hb_shape` needs a font, and a
        /// loader that guessed at one would be checking a property of the font
        /// rather than of the provider.
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
            // `hb_buffer_create` takes no argument and returns null only when
            // the allocator fails, which is exactly the question being asked.
            const buffer = dst.hb_buffer_create() orelse return
                "hb_buffer_create returned null, so this provider's allocator " ++
                "could not satisfy an empty buffer";
            dst.hb_buffer_destroy(buffer);
            return null;
        }

        /// The configuration string, for a load-time report.
        pub fn describeConfiguration() []const u8 {
            return config_name;
        }
    };
}