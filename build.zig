// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! Zig 0.16 build for HarfBuzz 14.5.1, shaped against the sibling FreeType.
//!
//! ## The sibling FreeType, and exactly what that means
//!
//! HarfBuzz's FreeType integration is `src/hb-ft.cc`, and that file is inside
//! `src/harfbuzz.cc`'s include list (`src/harfbuzz.cc:20`). It cannot be compiled
//! without FreeType's headers, and it cannot be *used* without FreeType's code.
//! This package therefore consumes the sibling `../freetype` package, and the
//! decision is stated here in full because it is the one thing a consumer has to
//! know before depending on it:
//!
//!   * The provider is a **relative path dependency** on `../freetype`, resolved
//!     through `b.dependency("freetype", ...)`. It is not a fetch, not a
//!     registry package, and not an installed system library.
//!   * `-Dfreetype=none` is **refused at configure time**, with the reason
//!     printed, and that is the whole of its behaviour. Upstream's
//!     `HB_NO_FREETYPE` configuration would remove `hb_ft_font_create` from the
//!     build while `zig/root.zig`'s `FtFont` names that entry point, so the two
//!     halves would disagree: either the facade stops compiling, or a stub
//!     stands in for a feature that was switched off. The check lives in
//!     `FreeType` below, which is the one place that knows the answer.
//!   * The headers come from `<path>/include`, the sibling's *source* tree. A
//!     FreeType installed under `include/freetype2` would need a different
//!     include root and a different library, and mixing the two is exactly the
//!     silent mismatch AGENTS.md section 4 warns about.
//!   * The path is explicit and defaults to `../freetype`. `-Dfreetype=<path>`
//!     selects a different FreeType source tree; there is no search path, no
//!     fallback and no system default.
//!
//! The sibling is a *source* dependency, not a required import for a *consumer*
//! of this package: a dependent that only shapes from a font blob never touches
//! `hb-ft.h`, and `zig build test` exercises both routes.
//!
//! ## What is compiled
//!
//! One translation unit: `src/harfbuzz.cc`, which is HarfBuzz's own amalgamation
//! and includes every `.cc` in the library, platform shims included
//! (`src/harfbuzz.cc:1-69`). Nothing is downloaded, no meson, no CMake and no
//! autotools script is executed.
//!
//! What is *not* compiled, and why it is upstream's choice rather than this
//! fork's: `src/harfbuzz-subset.cc` and `src/harfbuzz-world.cc` are separate
//! libraries with their own headers and their own `pkg-config` files
//! (`src/harfbuzz-subset.pc.in`, `src/harfbuzz-world.cc.in`), and `util/` is a
//! set of command-line programs rather than a library. This package is the
//! buffer/shape/font library.
//!
//! ## C++ dialect and the two flags that matter
//!
//! `-std=c++14 -fno-exceptions -fno-rtti`, and all three are this fork's
//! decision rather than a citation. HarfBuzz's top-level `meson.build` is not
//! vendored, so nothing in this tree records upstream's `cpp_std`, its
//! `-fno-exceptions` / `-fno-rtti` settings or any dialect bump; quoting a
//! `meson.build:NN` line here would be a citation to a file that is not in this
//! package. What the tree does record is why these three: HarfBuzz throws
//! nothing and uses no RTTI, both settings shrink the object and drop its
//! exception table, and one dialect for every target is what keeps a cross
//! build from compiling the same source under two different rules.
//!
//! ## Per-target compile-line macros
//!
//! HarfBuzz's configuration arrives two ways upstream: a generated `config.h`
//! (`src/hb-config.hh:34-36` includes it under `HAVE_CONFIG_H`), or macros on the
//! compile line. This build uses the compile line and never defines
//! `HAVE_CONFIG_H`, so there is no generated header to regenerate per target and
//! nothing whose content could disagree with the target being built. The facts
//! that header would carry are these, and each one is read out of the target,
//! not probed:
//!
//!   * `HAVE_PTHREAD` where `src/hb-mutex.hh:50-57` selects `pthread_mutex_t`.
//!     Without it that header falls through to `src/hb-mutex.hh:73-81`, which
//!     constructs a `std::mutex` in place - correct, but it moves the locking
//!     into libstdc++ rather than libc, which is not what upstream builds.
//!   * `HAVE_ATEXIT`, which `src/hb.hh:448` uses to register `hb_atexit`.
//!   * `HAVE_SYS_MMAN_H`, `HAVE_UNISTD_H`, `HAVE_MMAP` and `HAVE_MPROTECT`,
//!     which `src/hb-blob.cc:31-37`, `:417` and `:513` gate memory-mapped blob
//!     loading on. Every one of them is a header this target's libc is expected
//!     to have, and the mapping below is stated as a mapping, not as a probe.
//!   * `HAVE_FREETYPE` and `HAVE_FT_GET_TRANSFORM`, which `src/hb-ft.cc:32` and
//!     `:186` need, and which this build sets exactly when `-Dfreetype` selected
//!     a FreeType source tree.
//!
//! Every other `HAVE_*` upstream's `config.h` can carry - glib, icu, graphite2,
//! cairo, coretext, directwrite, uniscribe, gdi, wasm, png, zlib - is left
//! undefined, which is the "all optional dependencies off" configuration. Each
//! is guarded by the `HAVE_` test that would otherwise reach for a library this
//! package does not link.
//!
//! ## Entry points
//!
//!   zig build           install the library, the public headers, the
//!                       relocatable `harfbuzz.pc`, and the licence and
//!                       provenance records
//!   zig build test      run the behavioural tests for the selected target
//!                       (`-Dtarget`; the host when it is absent)
//!
//!   -Dlinkage=static   a static archive, `libharfbuzz.a`. The default.
//!   -Dlinkage=dynamic  a real shared object, with upstream's own SONAME:
//!                      `src/meson.build:650-652` sets `hb_so_version` and `:673`
//!                      passes it to the `library()` call.
//!   -Druntime=true     resolve the native entry points at run time. Default
//!                      off. Note what a loaded provider must be: see
//!                      `runtime/library.zig`, which explains that a HarfBuzz
//!                      built without FreeType is a conforming provider for
//!                      everything except `hb-ft.h`.
//!   -Dfreetype=<path>  the FreeType *source* tree to compile `src/hb-ft.cc`
//!                      against. Defaults to `../freetype`. `none` is refused at
//!                      configure time, with the reason printed.
//!   -Dsystem=true      link an installed `libharfbuzz` instead of compiling
//!                      `src/`. Supplies the default of
//!                      `b.systemIntegrationOption("harfbuzz", ...)`.
//!   -Dtarget=<triple>  build for one target; `zig build check` checks that
//!                      target only.
//!   -Doptimize=<mode>  the caller's mode, passed to every graph below.
//!
//! ## The SONAME
//!
//! The SONAME this package delivers is upstream's own, and it is read out of a
//! file that is in this tree. `src/meson.build:650-652` assigns
//! `hb_so_version = ''` for a Microsoft compiler and `hb_so_version = '0'` for
//! everything else, and `src/meson.build:673` passes it to the `library()` call
//! as `soversion`; that is where upstream's `libharfbuzz.so.0` comes from. Zig
//! derives the SONAME from `version.major`, so `major` is 0 here and for that
//! reason.
//!
//! The other two components are **not** sourced from this tree, and saying so
//! is the point of this paragraph. `src/meson.build:643` shows the shape of
//! upstream's own version string, `version = '0.@0@.0'.format(hb_version_int)`,
//! but `hb_version_int` is assigned in the top-level `meson.build`, which this
//! package does not vendor, and no file under `src/`, `docs/` or `NEWS` records
//! the number it takes. So `minor` and `patch` carry `61451` - `60000 +
//! major*100 + minor*10 + micro` for 14.5.1 - as upstream's convention carried
//! over, not as a value read out of a file here. Only the delivered file name,
//! `libharfbuzz.so.0.61451.61451`, depends on that pair; the SONAME does not.

const std = @import("std");
const manifest = @import("build.zig.zon");
const graph = @import("runtime/graph.zig");

const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon .version is not a semantic version");

const lib_name = "harfbuzz";
const freetype_name = "freetype";
const facade_source = "zig/root.zig";
const translate_header = "zig/translate.h";
const test_source = "tests.zig";
const example_source = "smoke.zig";

/// The native source root, which is also the include path: `src/harfbuzz.cc`
/// includes `"OT/Var/VARC/VARC.cc"` and its siblings by relative name.
const source_dir = "src";

/// The default sibling FreeType source tree, resolved relative to this package.
const default_freetype_path = "../freetype";

/// The HarfBuzz release these sources are, read out of `src/hb-version.h:44`
/// (`HB_VERSION_MAJOR 14`), `:50` (`HB_VERSION_MINOR 5`) and `:56`
/// (`HB_VERSION_MICRO 1`). Three separate lines: no range in that header holds
/// all three macros.
const upstream_version: std.SemanticVersion = .{ .major = 14, .minor = 5, .patch = 1 };

/// The SONAME this package delivers: upstream's own `0`, read out of
/// `src/meson.build:650-652` and `:673`. The module doc's SONAME section says
/// which parts of this constant are sourced and which are carried. Zig takes
/// the SONAME from `major`; `minor` and `patch` reach only the file name.
const abi_version: std.SemanticVersion = .{ .major = 0, .minor = 61451, .patch = 61451 };

/// The single translation unit: HarfBuzz's own amalgamation.
const core_source = "src/harfbuzz.cc";

/// The public headers, installed flat beside the library.
///
/// `zig/translate.h:54-60` reaches three umbrellas: `<hb.h>`, `<hb-ft.h>`, and
/// `<hb-ot.h>`, which the facade needs for `hb_ot_font_set_funcs`. This list is
/// exactly the headers those three reach - `src/hb.h:31-45` and
/// `src/hb-ot.h:33-43` are the two include lists behind it - so the installed
/// closure and the translated closure are the same set rather than two lists
/// that can drift. That is also why a C consumer of this SDK gets a header for
/// every symbol the library it links against exports: a translated declaration
/// whose header is not installed is the silent mismatch this workspace's rules
/// are about, and the twelve `hb-ot*` entries are what keep the OpenType
/// surface out of it.
const public_headers = [_][]const u8{
    "src/hb.h",
    "src/hb-blob.h",
    "src/hb-buffer.h",
    "src/hb-common.h",
    "src/hb-deprecated.h",
    "src/hb-draw.h",
    "src/hb-face.h",
    "src/hb-font.h",
    "src/hb-ft.h",
    "src/hb-map.h",
    "src/hb-ot.h",
    "src/hb-ot-fetch.h",
    "src/hb-ot-color.h",
    "src/hb-ot-deprecated.h",
    "src/hb-ot-font.h",
    "src/hb-ot-layout.h",
    "src/hb-ot-math.h",
    "src/hb-ot-meta.h",
    "src/hb-ot-metrics.h",
    "src/hb-ot-name.h",
    "src/hb-ot-shape.h",
    "src/hb-ot-var.h",
    "src/hb-paint.h",
    "src/hb-set.h",
    "src/hb-shape-plan.h",
    "src/hb-shape.h",
    "src/hb-style.h",
    "src/hb-unicode.h",
    "src/hb-version.h",
};

/// The records installed under `share/licenses/harfbuzz/`.
const licence_records = [_][]const u8{
    "COPYING",
    "test/COPYING",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "UPSTREAM.sha256",
    "FORK-NOTES.md",
    "CHANGELOG.md",
    "README.md",
    "README.upstream.md",
};

/// The C++ flags every translation unit gets.
const cpp_flags = [_][]const u8{
    "-std=c++14",
    // This fork's settings, not a citation: HarfBuzz's top-level `meson.build`
    // is not vendored, so no file in this tree records upstream's own flags.
    // HarfBuzz never throws and never uses RTTI, and both settings shrink the
    // object and remove an exception table from it.
    "-fno-exceptions",
    "-fno-rtti",
};

/// Which native library this build links.
const Library = enum {
    bundled,
    system,
};

/// The FreeType integration.
///
/// There is no `none` member on purpose. Upstream supports a HarfBuzz built
/// with `HB_NO_FREETYPE`, and this fork does not offer that configuration:
/// offering it honestly would need either a second facade root file that exists
/// only in it - so that `dep.module("harfbuzz")` would resolve to different
/// source depending on a build option - or a facade that names
/// `hb_ft_font_create` in a build that does not contain it. The first is a
/// second convention and the second is a stub, so `-Dfreetype=none` is refused
/// at configure time with that reason instead.
///
/// The dependency is resolved *per target* inside `addGraph`, not once in
/// `build()`: a matrix cell builds for a different target than the published
/// graph, and one dependency resolved for the wrong target is a library built
/// for the wrong ABI.
const FreeType = struct {
    /// A FreeType *source* tree, relative to this package's root.
    path: []const u8,

    /// The sibling package, for the target this graph builds.
    fn dep(
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) *std.Build.Dependency {
        return b.dependency(freetype_name, .{ .target = target, .optimize = optimize });
    }

    /// The sibling's *source* include root, lazily.
    ///
    /// `b.pathJoin` answers a `[]u8`, and `addIncludePath` wants a
    /// `Build.LazyPath`; `LazyPath.path` is the join that keeps the base lazy.
    /// `../freetype` escapes this package's root, which is why the base goes
    /// through `b.path` rather than being spelled as a string: the build runner
    /// resolves a `src_path` against its build root, so the `..` stays a
    /// relative hop rather than becoming a path relative to the process's
    /// working directory.
    fn include(freetype: FreeType, b: *std.Build) std.Build.LazyPath {
        return b.path(freetype.path).path(b, "include");
    }
};

/// The six cross targets this package compiles for.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// No target is refused, and one of them is known not to compile.
///
/// `src/harfbuzz.cc` is guarded at every optional dependency by an `HAVE_*`
/// test, and the WASI cell compiles the same single translation unit, so
/// HarfBuzz's own sources were never the obstacle. The obstacle is one level
/// down, in the sibling: `zig/translate.h` includes `<hb-ft.h>`, `src/hb-ft.h:34`
/// opens `<ft2build.h>`, and FreeType's
/// `include/freetype/config/ftstdlib.h:166` includes `<setjmp.h>` with no guard.
/// The pinned toolchain's wasi-libc refuses to declare `setjmp` at all:
/// `libc/include/wasm-wasi-musl/setjmp.h:13` raises `#error` unless
/// `__wasm_exception_handling__` is defined. Observed 2026-10-05: this
/// package's translation, the sibling's translation and the sibling's library
/// all fail there.
///
/// The row therefore stays in `check_targets` and this list stays empty, so the
/// failure keeps being reported on every `zig build check` instead of the target
/// quietly disappearing. `-Dfreetype=none` would compile by dropping the
/// FreeType integration, which is why this package has a sibling dependency at
/// all, so it is not that fix. `FORK-NOTES.md` carries the full diagnosis.
const refused_check_targets = [_]std.Target.Query{};

const Graph = struct {
    c_lib: ?*std.Build.Step.Compile,
    module: *std.Build.Module,
    platform: Platform,
};

/// The one place the target's platform facts live.
const Platform = struct {
    /// Name/value compile-line macros, resolved from the resolved target.
    macros: []const [2][]const u8,
    /// Whether HarfBuzz's blob loader can map a file.
    mmap: bool,
    /// Whether the target's libc supplies the pthread mutexes HarfBuzz prefers.
    pthread: bool,
    /// Whether the maths HarfBuzz uses lives in a separate library.
    separate_m: bool,
    dll: bool,

    fn forTarget(target: std.Build.ResolvedTarget) Platform {
        const os_tag = target.result.os.tag;
        const base = Platform{
            .macros = &.{},
            // `src/hb-blob.cc:31-37` needs both headers before it will even
            // look at `HAVE_MMAP`, and `:417` additionally needs `mprotect`.
            // Every OS below has all three; nothing else this package is built
            // for does.
            .mmap = switch (os_tag) {
                .linux, .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .netbsd,
                .openbsd, .dragonfly, .illumos,
                => true,
                else => false,
            },
            // `src/hb-mutex.hh:50`: `HAVE_PTHREAD` or `__APPLE__`. Windows takes
            // the `CRITICAL_SECTION` branch at `:60` and needs no macro.
            .pthread = switch (os_tag) {
                .windows, .wasi, .emscripten => false,
                else => true,
            },
            .separate_m = switch (os_tag) {
                .windows, .wasi, .emscripten => false,
                else => true,
            },
            .dll = os_tag == .windows,
        };
        return base;
    }

    fn kind(platform: Platform) []const u8 {
        if (platform.pthread) return "pthread mutexes, HAVE_MMAP blob loading";
        if (platform.mmap) return "HAVE_MMAP blob loading, no pthread macros";
        return "no mmap, no pthread macros";
    }
};

fn artifactName(b: *std.Build, target: std.Build.ResolvedTarget, public: bool) []const u8 {
    if (public) return lib_name;
    const triple = target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    return b.fmt("{s}-{s}", .{ lib_name, triple });
}

/// Compile HarfBuzz against a sibling FreeType source tree.
fn add_c_library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    requested: std.builtin.LinkMode,
    platform: Platform,
    freetype: FreeType,
    name: []const u8,
) *std.Build.Step.Compile {
    const linkage = deliveredLinkage(target, requested);
    const c_lib = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        .version = if (linkage == .dynamic) abi_version else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            // One translation unit is compiled as C++, so the archive needs the
            // C++ runtime. Not `linkLibCpp()` on the facade: this is the library
            // module, and the facade only ever links it.
            .link_libcpp = true,
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    // `src/harfbuzz.cc:1` opens `"OT/Var/VARC/VARC.cc"`, so the source directory
    // is also an include path - and it must be on the *translation*'s path too,
    // because `src/hb-ft.h:34` opens `<ft2build.h>` by bare name.
    c_mod.addIncludePath(b.path(source_dir));

    for (platform.macros) |macro| c_mod.addCMacro(macro[0], macro[1]);
    if (platform.pthread) c_mod.addCMacro("HAVE_PTHREAD", "1");
    c_mod.addCMacro("HAVE_ATEXIT", "1");
    if (platform.mmap) {
        c_mod.addCMacro("HAVE_SYS_MMAN_H", "1");
        c_mod.addCMacro("HAVE_UNISTD_H", "1");
        c_mod.addCMacro("HAVE_MMAP", "1");
        c_mod.addCMacro("HAVE_MPROTECT", "1");
    }

    // The sibling's *source* include root. Not `include/freetype2`, which is
    // where an installed FreeType puts the same headers: mixing one tree's
    // headers with another tree's library is the silent mismatch AGENTS.md
    // section 4 is about.
    c_mod.addIncludePath(freetype.include(b));
    c_mod.addCMacro("HAVE_FREETYPE", "1");
    // `src/hb-ft.cc:186` gates the transform branch on it, and five places call
    // `FT_Get_Transform`: `:520`, `:572`, `:612`, `:720`, `:860`. The sibling
    // documents it as `@since 2.11`
    // (`../freetype/include/freetype/freetype.h:3711-3712`) and pins 2.14.3
    // (`:5170-5172`), so this macro is a fact read out of the header on the
    // compile line, not a probe.
    c_mod.addCMacro("HAVE_FT_GET_TRANSFORM", "1");

    c_mod.addCSourceFile(.{
        .file = b.path(core_source),
        .flags = &cpp_flags,
        .language = .cpp,
    });

    if (platform.separate_m) c_mod.linkSystemLibrary("m", .{});

    // Resolved for *this* graph's target, so a matrix cell links a FreeType
    // built for that cell's target rather than the published graph's.
    c_mod.linkLibrary(FreeType.dep(b, target, optimize).artifact(freetype_name));

    if (linkage == .dynamic) setVersionScript(b, c_lib, target);

    for (public_headers) |header| {
        c_lib.installHeader(b.path(header), std.fs.path.basename(header));
    }

    return c_lib;
}

fn setVersionScript(b: *std.Build, c_lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    if (target.result.ofmt != .elf) return;
    const files = b.addWriteFiles();
    c_lib.setVersionScript(files.add("harfbuzz.map",
        \\HARFBUZZ_14 {
        \\  global:
        \\    hb_*;
        \\  local:
        \\    *;
        \\};
        \\
    ));
}

fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

fn deliveredLinkage(target: std.Build.ResolvedTarget, requested: std.builtin.LinkMode) std.builtin.LinkMode {
    if (requested == .dynamic and !targetHasDynamicLinker(target)) {
        std.debug.panic(
            "harfbuzz: -Dlinkage=dynamic was asked for {s}, which has no " ++
                "dynamic linker. Name a target with one, or build the static " ++
                "archive that is this package's default.",
            .{@tagName(target.result.os.tag)},
        );
    }
    return requested;
}

/// The RISC-V float-ABI macro the C compiler predefines and `translate-c` does
/// not, as the `-D` pair `defineCMacro` takes, or null on every other
/// architecture.
///
/// glibc lays out a RISC-V `jmp_buf` for two of the three RISC-V float ABIs and
/// refuses the third. In the pinned toolchain's own headers,
/// `lib/libc/include/riscv-linux-gnu/bits/setjmp.h:32-36` gives the struct
/// twelve callee-saved `double` registers when `__riscv_float_abi_double` is
/// defined, gives it none when `__riscv_float_abi_soft` is, and raises `#error
/// unsupported FLEN` for `__riscv_float_abi_single`, the one ABI left with no
/// layout there. `<setjmp.h>` reaches this package through FreeType:
/// `zig/translate.h` includes `<hb-ft.h>`, `src/hb-ft.h:34-35` opens
/// `<ft2build.h>` and `FT_FREETYPE_H`, and `include/freetype/config/ftstdlib.h`
/// includes `<setjmp.h>` at line 166 with no guard behind it.
///
/// Clang and the translator disagree about that one macro and about nothing
/// else on this path. `zig cc -target riscv64-linux-gnu` predefines
/// `__riscv_float_abi_double`, so HarfBuzz's `src/harfbuzz.cc` compiles for that
/// target; `translate-c`, which is Aro, predefines none of the three and stops
/// on the same header at `bits/setjmp.h:35`. Left alone, the facade would be
/// translated against a `jmp_buf` layout the library was never compiled with.
///
/// So the translation is handed the macro the compile was handed, derived from
/// the target being built and never from the host (AGENTS.md section 5). A
/// target with F and no D gets `__riscv_float_abi_single`, which is what clang
/// gives it and what glibc rejects, so that failure stays a failure instead of
/// being translated away.
fn translateCRiscvFloatAbi(target: std.Build.ResolvedTarget) ?[2][]const u8 {
    switch (target.result.cpu.arch) {
        .riscv32, .riscv32be, .riscv64, .riscv64be => {},
        else => return null,
    }
    const abi: []const u8 = if (std.Target.riscv.featureSetHas(target.result.cpu.features, .d))
        "__riscv_float_abi_double"
    else if (std.Target.riscv.featureSetHas(target.result.cpu.features, .f))
        "__riscv_float_abi_single"
    else
        "__riscv_float_abi_soft";
    return .{ abi, "1" };
}

fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    freetype: FreeType,
    public: bool,
) Graph {
    const platform = Platform.forTarget(target);

    const c_lib: ?*std.Build.Step.Compile = if (library == .bundled)
        add_c_library(b, target, optimize, linkage, platform, freetype, artifactName(b, target, public))
    else
        null;

    const no_macros: []const [2][]const u8 = &.{};
    const translate_macros = if (library == .bundled) platform.macros else no_macros;
    const translate_include: ?std.Build.LazyPath =
        if (library == .bundled) b.path(source_dir) else null;

    const translate = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (translate_include) |dir| translate.addIncludePath(dir);
    for (translate_macros) |macro| translate.defineCMacro(macro[0], macro[1]);
    if (library == .bundled) {
        if (platform.pthread) translate.defineCMacro("HAVE_PTHREAD", "1");
        if (platform.mmap) translate.defineCMacro("HAVE_MMAP", "1");
    }
    // Same macros, on the translation, for the same reason FreeType puts
    // `FT2_BUILD_LIBRARY` on both: `src/hb-ft.h` is `#ifdef HAVE_FREETYPE`, so a
    // translation that disagreed with the library would declare a different set
    // of `hb_ft_*` functions than the one that was compiled.
    translate.addIncludePath(freetype.include(b));
    translate.defineCMacro("HAVE_FREETYPE", "1");
    // The one macro the C compiler and the translator disagree about on this
    // path, reached through FreeType's `ftstdlib.h`. It goes on the translation
    // only: clang already predefines it for every C++ compile line, and a `-D`
    // there would be a second copy of a fact the compiler owns. Null off RISC-V,
    // so no other architecture sees a `-D` it did not need.
    if (translateCRiscvFloatAbi(target)) |macro| translate.defineCMacro(macro[0], macro[1]);
    if (library == .system) {
        translate.linkSystemLibrary(lib_name, .{ .preferred_link_mode = linkage });
    }

    const module = if (public)
        b.addModule(lib_name, .{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

    if (runtime_loaded) {
        module.addImport("c", graph.createModule(b, translate, target, optimize));
    } else {
        module.addImport("c", translate.createModule());
        module.addImport("rt", graph.createCoreModule(b, target, optimize));
        if (c_lib) |lib| module.linkLibrary(lib);
    }
    if (library == .bundled) {
        module.addIncludePath(b.path(source_dir));
        module.addImport(freetype_name, FreeType.dep(b, target, optimize).module(freetype_name));
    }

    return .{ .c_lib = c_lib, .module = module, .platform = platform };
}

fn add_target_check(
    b: *std.Build,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    freetype: FreeType,
    step: *std.Build.Step,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const triple = cross_target.result.zigTriple(b.allocator) catch @panic("unspellable target");
    const cross = addGraph(b, cross_target, optimize, library, linkage, runtime_loaded, freetype, false);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addTest(.{
        .name = b.fmt("harfbuzz-tests-{s}", .{triple}),
        .root_module = test_mod,
    }).step);

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, cross.module);
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("harfbuzz-smoke-{s}", .{triple}),
        .root_module = example_mod,
    }).step);
}

fn runConsumer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    library: Library,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    freetype_path: []const u8,
) *std.Build.Step.Run {
    const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);
    const cpu = target.query.serializeCpuAlloc(b.allocator) catch @panic("OOM");
    defer b.allocator.free(cpu);

    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.setName("consumer package");
    run.setCwd(b.path("consumer"));
    run.addArg(if (hostCanExecute(b, target)) "run" else "install");
    run.addArg(b.fmt("-Dtarget={s}", .{triple}));
    run.addArg(b.fmt("-Dcpu={s}", .{cpu}));
    run.addArg(b.fmt("-Doptimize={s}", .{@tagName(optimize)}));
    run.addArg(b.fmt("-Dlinkage={s}", .{@tagName(linkage)}));
    run.addArg(b.fmt("-Druntime={s}", .{if (runtime_loaded) "true" else "false"}));
    // The same source tree, forwarded, so the consumer's HarfBuzz is the same
    // build and not a differently-configured one.
    run.addArg(b.fmt("-Dfreetype={s}", .{freetype_path}));
    run.addArg(if (library == .system)
        b.fmt("-fsys={s}", .{lib_name})
    else
        b.fmt("-fno-sys={s}", .{lib_name}));
    if (b.enable_darling) run.addArg("-fdarling");
    if (b.enable_qemu) run.addArg("-fqemu");
    if (b.enable_rosetta) run.addArg("-frosetta");
    if (b.enable_wasmtime) run.addArg("-fwasmtime");
    if (b.enable_wine) run.addArg("-fwine");
    if (b.libc_runtimes_dir) |runtimes| run.addArgs(&.{ "--libc-runtimes", runtimes });
    run.addArg("-j8");
    run.addArg("--summary");
    run.addArg("all");
    if (b.cache_root.path) |cache| {
        run.addArg("--cache-dir");
        run.addArg(b.fmt("{s}/consumer", .{cache}));
    }
    if (b.graph.global_cache_root.path) |global_cache| {
        run.addArg("--global-cache-dir");
        run.addArg(global_cache);
    }
    const default_prefix = b.build_root.join(b.allocator, &.{"zig-out"}) catch @panic("OOM");
    if (!std.mem.eql(u8, b.install_prefix, default_prefix)) {
        const prefix = if (std.fs.path.isAbsolute(b.install_prefix))
            b.install_prefix
        else
            b.pathJoin(&.{ b.graph.cache.cwd, b.install_prefix });
        run.addArg("--prefix");
        run.addArg(prefix);
    }
    if (b.args) |args| {
        run.addArg("--");
        run.addArgs(args);
    }
    run.has_side_effects = true;
    return run;
}

fn hostCanExecute(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const host = &b.graph.host.result;
    const candidate = &target.result;
    const options: std.zig.system.GetExternalExecutorOptions = .{
        .allow_darling = b.enable_darling,
        .allow_qemu = b.enable_qemu,
        .allow_wasmtime = b.enable_wasmtime,
        .allow_wine = b.enable_wine,
        .qemu_fixes_dl = candidate.isGnuLibC() and b.libc_runtimes_dir != null,
        .link_libc = true,
    };
    return switch (std.zig.system.getExternalExecutor(b.graph.io, host, candidate, options)) {
        .native, .rosetta, .wine, .wasmtime, .darling => true,
        .qemu => !(candidate.isGnuLibC() and b.libc_runtimes_dir == null),
        .bad_dl, .bad_os_or_cpu => false,
    };
}

fn add_pkg_config(b: *std.Build, linkage: std.builtin.LinkMode) void {
    const files = b.addWriteFiles();
    const install_pc = b.addInstallFileWithDir(
        files.add("harfbuzz.pc", b.fmt(
            \\# harfbuzz.pc for the HarfBuzz {f} SDK.
            \\#
            \\# Upstream generates this file from `src/harfbuzz.pc.in` with the
            \\# package's own name and version substituted. Every field below is this
            \\# fork's, and build.zig's add_pkg_config names what each one came from.
            \\# `prefix` is pcfiledir-relative so the installed file is correct wherever
            \\# --prefix put it.
            \\prefix=${{pcfiledir}}/../..
            \\exec_prefix=${{prefix}}
            \\libdir=${{prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: harfbuzz
            \\Description: HarfBuzz text shaping engine
            \\Version: {f}
            \\
            \\Requires:
            \\Libs: -L"${{libdir}}" -lharfbuzz
            \\Libs.private: -lm
            \\Cflags: -I"${{includedir}}"{s}
            \\
        , .{
            upstream_version,
            upstream_version,
            if (linkage == .dynamic) " -DHB_NO_MT=0" else "",
        })),
        .prefix,
        "lib/pkgconfig/harfbuzz.pc",
    );
    b.getInstallStep().dependOn(&install_pc.step);
}

fn install_licence_records(b: *std.Build) void {
    for (licence_records) |record| {
        const install_record = b.addInstallFileWithDir(
            b.path(record),
            .prefix,
            b.fmt("share/licenses/harfbuzz/{s}", .{std.fs.path.basename(record)}),
        );
        b.getInstallStep().dependOn(&install_record.step);
    }
}

fn checkMatrixPartition(_: *std.Build) void {
    if (refused_check_targets.len != 0) {
        @panic("build.zig: refused_check_targets is not empty and this build has no refusal to record; see the module doc");
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const system_default = b.option(
        bool,
        "system",
        "Link an installed libharfbuzz instead of compiling src/. The default is false, because this package's job is to build HarfBuzz from its own vendored source.",
    );
    const use_system = b.systemIntegrationOption(lib_name, .{ .default = system_default });
    const library: Library = if (use_system) .system else .bundled;

    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "How the library is delivered. static gives libharfbuzz.a; dynamic gives a real shared object.",
    );
    const linkage: std.builtin.LinkMode = linkage_option orelse
        (if (library == .system) .dynamic else .static);

    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve HarfBuzz's entry points through the platform loader at run time instead of linking them. Orthogonal to -Dlinkage. Default false.",
    ) orelse false;

    // The FreeType selection, resolved once and read by every graph below.
    //
    // `none` is a keyword and not a path, so it is spelled out before the
    // comparison; anything else is a path to a FreeType *source* tree, defaulting
    // to the sibling package one directory up.
    const freetype_option = b.option(
        []const u8,
        "freetype",
        "The FreeType source tree that src/hb-ft.cc compiles against. The word `none` is refused at configure time with the reason; there is no HB_NO_FREETYPE configuration here. Defaults to the sibling ../freetype package.",
    );
    if (freetype_option) |value| {
        if (std.mem.eql(u8, value, "none")) {
            std.log.err(
                "harfbuzz: -Dfreetype=none is refused. Upstream's HB_NO_FREETYPE\n" ++
                    "configuration is not offered by this fork: a facade that names\n" ++
                    "hb_ft_font_create in a build that does not contain it is a stub, and a\n" ++
                    "second facade root file would make dep.module(\"harfbuzz\") resolve to\n" ++
                    "different source depending on a build option. See the module doc.\n",
                .{},
            );
            @panic("harfbuzz: refusing a configuration this package has no honest facade for");
        }
    }
    // A FreeType *source* tree, relative to this package's root. `b.pathJoin` is
    // what makes `../freetype` resolve against the package root rather than
    // against the process's working directory.
    const freetype: FreeType = .{ .path = freetype_option orelse default_freetype_path };

    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out of src/hb-version.h; see UPSTREAM.md");
    }

    checkMatrixPartition(b);

    const published = addGraph(b, target, optimize, library, linkage, runtime_loaded, freetype, true);

    if (published.c_lib) |c_lib| {
        b.installArtifact(c_lib);
        add_pkg_config(b, deliveredLinkage(target, linkage));
        install_licence_records(b);
    }

    const example_mod = b.createModule(.{
        .root_source_file = b.path(example_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_mod.addImport(lib_name, published.module);
    const example = b.addExecutable(.{ .name = "harfbuzz-smoke", .root_module = example_mod });
    b.getInstallStep().dependOn(&example.step);

    const run_example = b.addRunArtifact(example);
    run_example.has_side_effects = true;
    if (b.args) |args| run_example.addArgs(args);
    b.step("smoke", "Run the deterministic example program").dependOn(&run_example.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(test_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, published.module);
    const unit_tests = b.addTest(.{ .name = "harfbuzz-tests", .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    run_tests.has_side_effects = true;
    b.step("test", "Run the behavioural tests").dependOn(&run_tests.step);

    b.step("consumer", "Build or run the consumer/ package for the selected target")
        .dependOn(&runConsumer(b, target, optimize, library, deliveredLinkage(target, linkage), runtime_loaded, freetype.path).step);

    const check_step = b.step(
        "check",
        "Compile the library, facade, tests and example for the cross targets, running nothing",
    );
    if (!target.query.isNative()) {
        add_target_check(b, target.query, optimize, library, linkage, runtime_loaded, freetype, check_step);
    } else {
        for (check_targets[0..]) |query| {
            add_target_check(b, query, optimize, library, linkage, runtime_loaded, freetype, check_step);
        }
    }

    std.debug.print(
        \\
        \\harfbuzz {f}, compiled from this repository's own src/harfbuzz.cc
        \\  translation unit: 1 (C++, -std=c++14 -fno-exceptions -fno-rtti)
        \\  platform: {s}
        \\  delivery: {s}
        \\
    , .{
        upstream_version,
        published.platform.kind(),
        if (library == .system)
            "an installed libharfbuzz"
        else switch (deliveredLinkage(target, linkage)) {
            .static => "a static archive, libharfbuzz.a",
            .dynamic => b.fmt("a shared object, libharfbuzz.so.{d}.{d}.{d} (SONAME libharfbuzz.so.{d})", .{
                abi_version.major,
                abi_version.minor,
                abi_version.patch,
                abi_version.major,
            }),
        },
    });

    std.debug.print(
        "  freetype: {s} (sibling source tree, not a system library); HAVE_FREETYPE, HAVE_FT_GET_TRANSFORM\n",
        .{freetype.path},
    );
    if (runtime_loaded) {
        std.debug.print(
            "  dispatch: every hb_* entry point is resolved through the platform loader; call load() first\n",
            .{},
        );
    }
    if (library == .system) {
        std.debug.print(
            "  system mode: nothing is compiled from src/, and this package's tests are not a result about that library\n",
            .{},
        );
    }
}