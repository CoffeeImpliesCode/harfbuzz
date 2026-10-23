// SPDX-License-Identifier: MIT

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

/// `src/harfbuzz.cc:1` includes files relative to `src/`; keep it on the include path.
const source_dir = "src";

/// Default FreeType source tree, relative to this package.
const default_freetype_path = "../freetype";

/// Version from upstream macros in `src/hb-version.h:44,50,56`.
const upstream_version: std.SemanticVersion = .{ .major = 14, .minor = 5, .patch = 1 };

/// Upstream sets SONAME 0 in `src/meson.build:650-673`. Other values name the shared file.
const abi_version: std.SemanticVersion = .{ .major = 0, .minor = 61451, .patch = 61451 };

const core_source = "src/harfbuzz.cc";

/// Keep the installed headers aligned with those reached by `zig/translate.h`.
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

const cpp_flags = [_][]const u8{
    "-std=c++14",
    "-fno-exceptions",
    "-fno-rtti",
};

const Library = enum {
    bundled,
    system,
};

/// FreeType source dependency resolved for each target graph.
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

/// FreeType includes `<setjmp.h>` (`include/freetype/config/ftstdlib.h:166`).
/// wasi-libc rejects it without `__wasm_exception_handling__` (`libc/include/wasm-wasi-musl/setjmp.h:13`).
/// Keep WASI in `check_targets`.
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
            // `src/hb-blob.cc:31-37` gates mmap on headers and `mprotect`.
            .mmap = switch (os_tag) {
                .linux, .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .netbsd,
                .openbsd, .dragonfly, .illumos,
                => true,
                else => false,
            },
            // `src/hb-mutex.hh:50-60` selects pthread or Windows `CRITICAL_SECTION`.
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
            // This C++ source requires the C++ runtime.
            .link_libcpp = true,
            .pic = if (linkage == .dynamic) true else null,
        }),
    });
    const c_mod = c_lib.root_module;

    // `src/harfbuzz.cc:1` includes source files relative to `src/`.
    // `src/hb-ft.h:34` resolves `<ft2build.h>` from FreeType's source include root.
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

    // Use headers from the source tree whose archive this graph links.
    c_mod.addIncludePath(freetype.include(b));
    c_mod.addCMacro("HAVE_FREETYPE", "1");
    // `HAVE_FT_GET_TRANSFORM` gates `FT_Get_Transform` (`src/hb-ft.cc:186`).
    // The sibling header declares it since 2.11 (`../freetype/include/freetype/freetype.h:3711-3712`).
    c_mod.addCMacro("HAVE_FT_GET_TRANSFORM", "1");

    c_mod.addCSourceFile(.{
        .file = b.path(core_source),
        .flags = &cpp_flags,
        .language = .cpp,
    });

    if (platform.separate_m) c_mod.linkSystemLibrary("m", .{});

    // Resolve FreeType for this target to match its ABI.

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

/// Aro omits Clang's RISC-V float-ABI macro. Mirror the target value for translation.
/// glibc rejects the single-precision ABI (`lib/libc/include/riscv-linux-gnu/bits/setjmp.h:32-36`).
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
    // Match the library's feature macros on translation so declarations agree.
    // Aro omits Clang's RISC-V ABI macro; mirror it from the selected target.
    translate.addIncludePath(freetype.include(b));
    translate.defineCMacro("HAVE_FREETYPE", "1");
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
    // Forward the selected FreeType source path to the consumer build.
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

    // Reject `none`; other values name a FreeType source tree.
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
    // Resolve relative paths against this package root.
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
