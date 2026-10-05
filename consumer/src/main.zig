// SPDX-License-Identifier: MIT
// See ../../FORK-LICENSE.md for what that identifier covers.

//! The consumer program for the HarfBuzz SDK.
//!
//! It is the check the library's own tests cannot make: everything here runs
//! through `dep.module("harfbuzz")` from a package that did not write the
//! facade. Four questions, in order:
//!
//!   1. Does a dependent get a working buffer / shape / font surface from one
//!      dependency, and does it shape a font the way upstream recorded it?
//!   2. Is the sibling FreeType really compiled, linked and running? The proof
//!      is not a link line: `hb_ft_font_set_funcs` is asked to attach FreeType
//!      font functions to an existing font, and the `FT_Face` that comes back
//!      is read *through* FreeType - its `units_per_EM` and `num_glyphs` were
//!      computed by FreeType's face loader from the same bytes this program
//!      holds. Then the font is shaped again and must produce the identical
//!      line: the metrics now come from FreeType's scaler rather than from
//!      HarfBuzz's own `hmtx` reader, and on this font the two agree exactly.
//!   3. Does the runtime route work from outside, when a dependent names a
//!      provider with an explicit `load()`?
//!   4. Do the error paths report rather than crash?
//!
//! ## Where the fonts come from
//!
//! The two fixtures are upstream's own, read from the library tree at run time
//! rather than embedded: `consumer/` is its own package, so `@embedFile` of a
//! path outside it names a file the package cannot see. The relative path below
//! resolves against this package's directory, which is the working directory
//! both `zig build run` here and the library's own `zig build consumer` step use
//! - `build.zig`'s `runConsumer` sets the working directory to `consumer/`. A
//! run started from somewhere else names the directory with
//! `HARFBUZZ_FIXTURE_DIR` instead.
//!
//! Run it under `LC_ALL=C`; see `../../smoke.zig` for why the recorded lines
//! are locale-dependent otherwise.

const std = @import("std");
const Io = std.Io;
const hb = @import("harfbuzz");

/// `harfbust.tests:1`, "HarfBuzz" - the same line the library's own tests
/// compare, written down here a second time so a consumer that shaped the text
/// through a broken build could not pass by sharing code with them.
const recorded_buzzz =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|z=6+790|z=7+790]";

/// `digits.tests:5`, `--direction=rtl`.
const recorded_arabic_rtl =
    "[ThreeArabic.encl=0@1140,444+0|TwoArabic.encl=0@860,444+0|" ++
    "OneArabic.encl=0@581,444+0|AyahEnd.alt3=0+1724]";

/// The fixture directory, relative to this package, and the override.
const default_fixture_dir = "../test/shape/data/in-house/fonts";
const fixture_dir_variable = "HARFBUZZ_FIXTURE_DIR";

/// Two fonts, one path segment apart from each other in the corpus; the second
/// is the font `digits.tests:4-5` name.
const harfbust_name = "HarfBust.ttf";
const arabic_name = "3b791518a9ba89675df02f1eefbc9026a50648a6.ttf";

/// `FT_LOAD_DEFAULT | FT_LOAD_NO_HINTING`, which is what `src/hb-ft.cc:119`
/// gives a new FreeType-backed font. Spelled here rather than read out of the
/// translated header, so this file states the number it checks instead of
/// restating whatever the translation produced.
const default_load_flags: c_int = 0x0 | 0x2;

/// One named failure per question, so a red run says which one broke.
const ConsumerError = error{
    ProviderCheckFailed,
    EnvironmentCheckFailed,
    FixtureCheckFailed,
    ShapeCheckFailed,
    FreeTypeCheckFailed,
};

const options = struct {
    provider_path: ?[]const u8 = null,
    provider_system: ?[]const u8 = null,
};

/// Read the provider, from an argument first and the environment second.
///
/// There is no default location and no fallback: a runtime-loaded build with no
/// provider named is a hard error, because a program that quietly linked
/// something else would prove nothing.
fn parseOptions(init: std.process.Init) !options {
    var parsed = options{};
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--provider") or std.mem.eql(u8, arg, "--provider-system")) {
            if (index + 1 >= args.len) return ConsumerError.EnvironmentCheckFailed;
            index += 1;
            if (std.mem.eql(u8, arg, "--provider-system")) {
                parsed.provider_system = args[index];
            } else {
                parsed.provider_path = args[index];
            }
        } else if (std.mem.eql(u8, arg, "--help")) {
            std.debug.print(
                "usage: harfbuzz-consumer [--provider <absolute path>] [--provider-system <soname>]\n",
                .{},
            );
            std.process.exit(0);
        } else {
            std.debug.print("harfbuzz-consumer: unrecognised argument {s}\n", .{arg});
            return ConsumerError.EnvironmentCheckFailed;
        }
    }
    if (parsed.provider_path == null and parsed.provider_system == null) {
        parsed.provider_path = init.environ_map.get("HARFBUZZ_PROVIDER");
        parsed.provider_system = init.environ_map.get("HARFBUZZ_PROVIDER_SYSTEM");
    }
    return parsed;
}

/// Load the named provider, or do nothing in a linked build.
fn nativeReady(parsed: options) !void {
    if (comptime !hb.runtime_loaded) return;
    if (hb.loadedSource() != null) return;
    const source: hb.LoadSource = if (parsed.provider_path) |path|
        .{ .path = path }
    else if (parsed.provider_system) |name|
        .{ .system = name }
    else {
        std.debug.print(
            "harfbuzz-consumer: this build resolves its entry points at run time.\n" ++
                "Name a provider with --provider <absolute path> or --provider-system <soname>,\n" ++
                "or set HARFBUZZ_PROVIDER / HARFBUZZ_PROVIDER_SYSTEM. There is no default.\n",
            .{},
        );
        return ConsumerError.EnvironmentCheckFailed;
    };
    hb.load(source) catch |err| {
        std.debug.print("harfbuzz-consumer: load failed: {s}\n", .{@errorName(err)});
        return ConsumerError.ProviderCheckFailed;
    };
}

/// Read one of upstream's in-house test fonts.
fn readFixture(init: std.process.Init, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const directory = init.environ_map.get(fixture_dir_variable) orelse default_fixture_dir;
    // One `sub_path`, not a directory and a name: `Io.Dir.readFileAlloc`
    // takes `dir`, `io`, `sub_path`, `gpa` and `limit`, so the two components
    // are joined here rather than passed as two arguments. The page allocator
    // because the joined path lives as long as the process does, which is the
    // one allocation here that is deliberately never freed.
    const path = try std.fs.path.join(std.heap.page_allocator, &.{ directory, name });
    return Io.Dir.cwd().readFileAlloc(
        init.io,
        path,
        allocator,
        .limited(1 << 24),
    ) catch |err| {
        std.debug.print(
            "harfbuzz-consumer: could not read the fixture {s}/{s}: {s}\n",
            .{ directory, name, @errorName(err) },
        );
        return ConsumerError.FixtureCheckFailed;
    };
}

/// Shape one string the way upstream's `hb-shape` does, and return the line.
fn shapeLine(
    font: *const hb.Font,
    allocator: std.mem.Allocator,
    text: []const u8,
    direction: hb.Direction,
) ![]u8 {
    var buffer = try hb.Buffer.create();
    defer buffer.deinit();
    try buffer.addUtf8(text);
    buffer.guessSegmentProperties();
    buffer.setDirection(direction);
    try hb.shape(font, &buffer, &.{});
    return buffer.serializeText(font, allocator);
}

fn checkLine(label: []const u8, expected: []const u8, actual: []const u8) ConsumerError!void {
    std.debug.print("  {s: <26} {s}\n", .{ label, actual });
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("  {s: <26} expected {s}\n", .{ label, expected });
        return ConsumerError.ShapeCheckFailed;
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const parsed = try parseOptions(init);
    try nativeReady(parsed);

    std.debug.print(
        \\
        \\harfbuzz consumer: {f}, {s}
        \\
    , .{ hb.version, if (hb.runtime_loaded) "runtime-loaded provider" else "linked" });
    if (hb.runtime_loaded) {
        switch (hb.loadedSource() orelse return ConsumerError.ProviderCheckFailed) {
            .path => |path| std.debug.print("  provider path               {s}\n", .{path}),
            .system => |name| std.debug.print("  provider soname             {s}\n", .{name}),
        }
    }

    const harfbust = try readFixture(init, allocator, harfbust_name);
    defer allocator.free(harfbust);

    // 1. The dependent's own view of the library.
    var blob = try hb.Blob.fromBytes(harfbust);
    defer blob.deinit();
    var face = try hb.Face.create(&blob);
    defer face.deinit();
    var font = try hb.Font.create(&face);
    defer font.deinit();

    std.debug.print("  design grid (units/em)      {d}\n", .{face.upem()});
    std.debug.print("  glyph count                 {d}\n", .{face.glyphCount()});
    const ot_line = try shapeLine(&font, allocator, "HarfBuzz", hb.direction_ltr);
    defer allocator.free(ot_line);
    try checkLine("shaped (ot metrics)", recorded_buzzz, ot_line);

    // 2. The sibling FreeType, asked for by name rather than inferred from a
    //    link line. `hb_ft_font_set_funcs` is `src/hb-ft.h:147`; it replaces
    //    this font's metrics with FreeType's and creates its own `FT_Face`.
    hb.c.hb_ft_font_set_funcs(font.handle());
    const ft_face = hb.c.hb_ft_font_get_ft_face(font.handle());
    // `FT_Face` is `typedef struct FT_FaceRec_ *FT_Face`, which translate-c
    // turns into the many-item pointer `[*c]FT_FaceRec`; that type carries no
    // null, so the "no face" answer is tested on the address and reached
    // through an index.
    if (@intFromPtr(ft_face) == 0) {
        std.debug.print("  hb_ft_font_get_ft_face      null\n", .{});
        return ConsumerError.FreeTypeCheckFailed;
    }
    // Read *through* FreeType: these two fields were filled in by FreeType's
    // own face loader, from the bytes this program passed in.
    std.debug.print("  ft units_per_EM             {d}\n", .{ft_face[0].units_per_EM});
    std.debug.print("  ft num_glyphs               {d}\n", .{ft_face[0].num_glyphs});
    if (ft_face[0].units_per_EM != 2048 or ft_face[0].num_glyphs != 99) {
        return ConsumerError.FreeTypeCheckFailed;
    }

    // The load flags are a reader on this font only because it is FreeType
    // backed: `src/hb-ft.cc:275` refuses the setter on any other font.
    hb.c.hb_ft_font_set_load_flags(font.handle(), default_load_flags);
    const flags = hb.c.hb_ft_font_get_load_flags(font.handle());
    std.debug.print("  ft load flags               {d}\n", .{flags});
    if (flags != default_load_flags) return ConsumerError.FreeTypeCheckFailed;

    // Shaping the same text through FreeType's metrics must give the same line.
    // Both readers see the same `hmtx` row: HarfBuzz's own table reader, and
    // FreeType's scaler at the ppem this scale selects (upem/64 = 32 for this
    // font, so every advance is an exact multiple of 1/64 px and no rounding
    // can creep in).
    const ft_line = try shapeLine(&font, allocator, "HarfBuzz", hb.direction_ltr);
    defer allocator.free(ft_line);
    try checkLine("shaped (ft metrics)", recorded_buzzz, ft_line);

    // 3. Direction, from a second font, right to left.
    const arabic = try readFixture(init, allocator, arabic_name);
    defer allocator.free(arabic);

    var blob2 = try hb.Blob.fromBytes(arabic);
    defer blob2.deinit();
    var face2 = try hb.Face.create(&blob2);
    defer face2.deinit();
    var font2 = try hb.Font.create(&face2);
    defer font2.deinit();

    const run = "\u{06DD}\u{0661}\u{0662}\u{0663}";
    const ltr = try shapeLine(&font2, allocator, run, hb.direction_ltr);
    defer allocator.free(ltr);
    const rtl = try shapeLine(&font2, allocator, run, hb.direction_rtl);
    defer allocator.free(rtl);
    std.debug.print("  {s: <26} {s}\n", .{ "shaped ltr", ltr });
    try checkLine("shaped rtl", recorded_arabic_rtl, rtl);

    // 4. The error paths.
    // `if`/`else` rather than `catch`: both calls answer a value, and a
    // `catch` block that only prints has type `void`, which cannot unify with
    // the `Blob` and `Face` on the success side.
    if (hb.Blob.fromFile("/nonexistent-harfbuzz-consumer/no-such-font.ttf")) |opened| {
        var unexpected = opened;
        unexpected.deinit();
        return ConsumerError.FixtureCheckFailed;
    } else |err| {
        std.debug.print("  missing font                {s}\n", .{@errorName(err)});
    }
    var prose = try hb.Blob.fromBytes("not a font");
    defer prose.deinit();
    if (hb.Face.create(&prose)) |opened| {
        var unexpected = opened;
        unexpected.deinit();
        return ConsumerError.FreeTypeCheckFailed;
    } else |err| {
        std.debug.print("  bytes that are not a font   {s}\n", .{@errorName(err)});
    }

    font.deinit();
    face.deinit();
    blob.deinit();
    std.debug.print("\nthe dependent saw every value upstream recorded\n", .{});
}