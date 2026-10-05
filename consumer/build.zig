// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.
//
//! Build wiring for the separate `consumer/` package.
//!
//! This package exists to prove one thing: that a dependent needs only
//! `dep.module("harfbuzz")` and gets a working, correctly linked library - the
//! HarfBuzz library *and* the sibling FreeType it shapes with. If the facade
//! module stopped carrying its C artifact, or the translated header stopped
//! matching the C++ source, or the sibling stopped being linked, this would
//! stop building or stop producing the answers its program checks, and nothing
//! inside the library would notice.
//!
//! `src/main.zig` is the API role's file. This file is only the graph that
//! builds it, and it deliberately repeats almost nothing: the library decides
//! which artifact is delivered, which platform macros it was compiled with,
//! which header describes it and which FreeType source tree it was built
//! against, and this package learns all of that through the dependency.
//!
//! `zig build run` runs it. `zig build run -Dlinkage=dynamic` really does check
//! the shared object, and `zig build run -Druntime=true -- --provider <path>`
//! really does check the runtime-loaded route; the options are forwarded rather
//! than ignored, so neither configuration can silently go unchecked.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The delivery and dispatch options are declared here rather than ignored,
    // so `zig build run -Dlinkage=dynamic` checks the shared object instead of
    // silently checking the default archive.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Which delivery of libharfbuzz to check. Forwarded to the dependency; it " ++
            "decides the artifact, never anything in this package.",
    ) orelse .static;
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Check the dependency's runtime-loading dispatch instead of a linked " ++
            "one. Forwarded to the dependency. A program built this way has to " ++
            "name a provider with an explicit load() before any native call, " ++
            "which is src/main.zig's business and not this file's.",
    ) orelse false;

    // The sibling FreeType source tree, forwarded verbatim.
    //
    // It is resolved by the *dependency*, relative to the library package's own
    // root rather than to this one, so the same spelling works from either
    // directory: `zig build -Dfreetype=..` from the repository root and
    // `zig build -Dfreetype=../..` from here mean the same tree. Declaring it
    // here rather than ignoring it is the point - a consumer that wanted a
    // different FreeType and silently got the default would be building a
    // program against a library it did not ask for.
    const freetype = b.option(
        []const u8,
        "freetype",
        "The FreeType source tree the library compiles against. Forwarded to " ++
            "the dependency, which resolves it relative to its own package root.",
    );

    const harfbuzz_options = .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime_loaded,
        .freetype = freetype,
    };

    const dep = b.dependency("harfbuzz", harfbuzz_options);

    // The system mode is deliberately *not* a `-D` option here, and that is not
    // an omission. The dependency resolves it through
    // `b.systemIntegrationOption`, which is fed by the build runner's
    // `-fsys=`/`-fno-sys=` flags and is never an entry in the `-D` map, so a
    // `b.option` declared here would have to be threaded down as a dependency
    // option to reach the same answer. It does not need to: a dependency
    // shares its parent's `Graph`, and `system_library_options` is a field of
    // it, so the flag the runner was given reaches the dependency's own
    // `systemIntegrationOption` call unchanged.

    // No `link_libc` here on purpose. The C requirement belongs to the library
    // module, which carries it; a dependent states its own, and this program
    // needs nothing beyond what the library already brings. Adding it here would
    // hide a library that forgot to declare it.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("harfbuzz", dep.module("harfbuzz"));

    const exe = b.addExecutable(.{
        .name = "harfbuzz-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.has_side_effects = true;
    // Forwarded so `zig build run -Druntime=true -- --provider <path>` reaches
    // `src/main.zig`, which reads exactly that and otherwise falls through to
    // `HARFBUZZ_PROVIDER`. With no arguments this is inert, so a linked run is
    // unchanged.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}