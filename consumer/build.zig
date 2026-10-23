// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.
//
//! Consumer build graph for the HarfBuzz module and sibling FreeType.
//! The run step forwards linkage/runtime options to exercise the selected route.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose delivery options so the run checks the selected artifact.
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

    // Forward the FreeType source option; the dependency resolves it relative to its package root.
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

    // System integration is inherited through the shared build graph, not declared as a duplicate `-D` option.

    // The dependency module carries its libc requirement; do not mask a missing declaration here.
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
    // Forward `--provider` for runtime mode; no arguments leave linked runs unchanged.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
