// SPDX-License-Identifier: MIT
// See ../../FORK-LICENSE.md for what that identifier covers.

//! Consumer smoke program for the HarfBuzz module, including FreeType and runtime loading.
//! Reads upstream font fixtures from the default corpus path or `HARFBUZZ_FIXTURE_DIR`.

const std = @import("std");
const Io = std.Io;
const hb = @import("harfbuzz");

/// Expected upstream shaping line for `HarfBuzz`, recorded in `harfbust.tests`.
const recorded_buzzz =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|z=6+790|z=7+790]";

/// Expected upstream RTL shaping line from `digits.tests`.
const recorded_arabic_rtl =
    "[ThreeArabic.encl=0@1140,444+0|TwoArabic.encl=0@860,444+0|" ++
    "OneArabic.encl=0@581,444+0|AyahEnd.alt3=0+1724]";

/// Default corpus path; `HARFBUZZ_FIXTURE_DIR` overrides it.
const default_fixture_dir = "../test/shape/data/in-house/fonts";
const fixture_dir_variable = "HARFBUZZ_FIXTURE_DIR";

/// Fixture filenames used by the HarfBuzz and Arabic checks.
const harfbust_name = "HarfBust.ttf";
const arabic_name = "3b791518a9ba89675df02f1eefbc9026a50648a6.ttf";

/// Flags passed to FreeType-backed fonts: `FT_LOAD_DEFAULT | FT_LOAD_NO_HINTING`.
const default_load_flags: c_int = 0x0 | 0x2;

/// Named failures for consumer checks.
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

/// Reads `--provider`/`--provider-system` first, then `HARFBUZZ_PROVIDER`/`HARFBUZZ_PROVIDER_SYSTEM`.
/// Runtime-loaded builds require one; there is no default.
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

/// Loads the named provider, or does nothing in a linked build.
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
    // Join directory/name for `readFileAlloc`; the page-allocated path lasts through process exit.
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

    // Ask HarfBuzz's FreeType bridge to attach metrics from its own `FT_Face`.
    hb.c.hb_ft_font_set_funcs(font.handle());
    const ft_face = hb.c.hb_ft_font_get_ft_face(font.handle());
    // translate-c represents `FT_Face` as `[*c]FT_FaceRec`, which has no null value.
    // Check its address before indexing.
    if (@intFromPtr(ft_face) == 0) {
        std.debug.print("  hb_ft_font_get_ft_face      null\n", .{});
        return ConsumerError.FreeTypeCheckFailed;
    }
    // FreeType's face loader populated these fields from the fixture bytes.
    std.debug.print("  ft units_per_EM             {d}\n", .{ft_face[0].units_per_EM});
    std.debug.print("  ft num_glyphs               {d}\n", .{ft_face[0].num_glyphs});
    if (ft_face[0].units_per_EM != 2048 or ft_face[0].num_glyphs != 99) {
        return ConsumerError.FreeTypeCheckFailed;
    }

    // Load flags can be set only on a FreeType-backed font.
    hb.c.hb_ft_font_set_load_flags(font.handle(), default_load_flags);
    const flags = hb.c.hb_ft_font_get_load_flags(font.handle());
    std.debug.print("  ft load flags               {d}\n", .{flags});
    if (flags != default_load_flags) return ConsumerError.FreeTypeCheckFailed;

    // Both readers use the same `hmtx` row; at this font's upem/64 scale, advances are exact multiples of 1/64 px.
    // The result must match without rounding differences.
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

    // Use `if/else`: a print-only `catch` branch returns `void`, not the `Blob`/`Face` success type.
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
