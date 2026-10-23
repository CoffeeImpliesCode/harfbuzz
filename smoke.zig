// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Compares shaping and error results with upstream's recorded HarfBuzz cases.
//! Run with `LC_ALL=C`; runtime-loaded builds require `HARFBUZZ_TEST_PROVIDER`.

const std = @import("std");
const hb = @import("harfbuzz");

const harfbust_bytes = @embedFile("test/shape/data/in-house/fonts/HarfBust.ttf");
const arabic_bytes = @embedFile("test/shape/data/in-house/fonts/3b791518a9ba89675df02f1eefbc9026a50648a6.ttf");

const provider_variable = "HARFBUZZ_TEST_PROVIDER";

/// Named failures reported by the smoke program.
const SmokeError = error{
    ProviderCheckFailed,
    EnvironmentCheckFailed,
    ShapeCheckFailed,
    SerializeCheckFailed,
};

/// Upstream `harfbust.tests:1` record for "HarfBuzz".
const recorded_buzzz =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|z=6+790|z=7+790]";

/// Upstream `harfbust.tests:4` record for "HarfBust".
const recorded_bust =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|s=6+972|t=7+625]";

/// Upstream `digits.tests:1` ltr record for the Arabic run.
const recorded_arabic_ltr =
    "[AyahEnd.alt3=0+1724|OneArabic.encl=0@-1143,444+0|" ++
    "TwoArabic.encl=0@-864,444+0|ThreeArabic.encl=0@-584,444+0]";
/// Upstream `digits.tests:5` rtl record for the same run.
const recorded_arabic_rtl =
    "[ThreeArabic.encl=0@1140,444+0|TwoArabic.encl=0@860,444+0|" ++
    "OneArabic.encl=0@581,444+0|AyahEnd.alt3=0+1724]";

/// Loads the explicit runtime provider; linked builds need none.
fn nativeReady() !void {
    if (comptime !hb.runtime_loaded) return;
    if (hb.loadedSource() != null) return;
    const path = std.c.getenv(provider_variable) orelse return error.EnvironmentCheckFailed;
    hb.load(.{ .path = std.mem.span(path) }) catch return error.ProviderCheckFailed;
}

fn checkLine(label: []const u8, expected: []const u8, actual: []const u8) SmokeError!void {
    std.debug.print("  {s: <24} {s}\n", .{ label, actual });
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("  {s: <24} expected {s}\n", .{ label, expected });
        return error.ShapeCheckFailed;
    }
}

fn check(comptime label: [:0]const u8, expected: anytype, actual: @TypeOf(expected)) SmokeError!void {
    std.debug.print("  {s: <24} {any}\n", .{ label, actual });
    if (expected != actual) {
        std.debug.print("  {s: <24} expected {any}, got {any}\n", .{ label, expected, actual });
        return error.SerializeCheckFailed;
    }
}

/// Shapes like upstream's `hb-shape` and serializes text.
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

pub fn main() !void {
    try nativeReady();

    std.debug.print(
        \\
        \\harfbuzz smoke: {f}, {s}
        \\
    , .{ hb.version, if (hb.runtime_loaded) "runtime-loaded provider" else "linked" });

    var blob = try hb.Blob.fromBytes(harfbust_bytes);
    defer blob.deinit();
    var face = try hb.Face.create(&blob);
    defer face.deinit();
    var font = try hb.Font.create(&face);
    defer font.deinit();

    // Version is informational; the smoke program does not pin it.
    std.debug.print("  library version             {f}\n", .{hb.version});
    try check("design grid (units/em)", @as(u32, 2048), face.upem());
    try check("glyph count", @as(u32, 99), face.glyphCount());
    try check("blob length (bytes)", @as(u32, harfbust_bytes.len), blob.len());
    std.debug.print("  scale (font units)          {d},{d}\n", .{ font.scale().x, font.scale().y });

    const buzzz = try shapeLine(&font, std.heap.page_allocator, "HarfBuzz", hb.direction_ltr);
    defer std.heap.page_allocator.free(buzzz);
    std.debug.print("\n  harfbust.tests:1, \"HarfBuzz\"\n", .{});
    try checkLine("shaped", recorded_buzzz, buzzz);

    const bust = try shapeLine(&font, std.heap.page_allocator, "HarfBust", hb.direction_ltr);
    defer std.heap.page_allocator.free(bust);
    std.debug.print("\n  harfbust.tests:4, \"HarfBust\"\n", .{});
    try checkLine("shaped", recorded_bust, bust);

    var blob2 = try hb.Blob.fromBytes(arabic_bytes);
    defer blob2.deinit();
    var face2 = try hb.Face.create(&blob2);
    defer face2.deinit();
    var font2 = try hb.Font.create(&face2);
    defer font2.deinit();

    const run = "\u{06DD}\u{0661}\u{0662}\u{0663}";
    const arabic_ltr = try shapeLine(&font2, std.heap.page_allocator, run, hb.direction_ltr);
    defer std.heap.page_allocator.free(arabic_ltr);
    const arabic_rtl = try shapeLine(&font2, std.heap.page_allocator, run, hb.direction_rtl);
    defer std.heap.page_allocator.free(arabic_rtl);
    std.debug.print("\n  digits.tests:1 and :5, U+06DD U+0661 U+0662 U+0663\n", .{});
    // The Arabic records differ in glyph order and x-offset signs.
    try checkLine("shaped ltr", recorded_arabic_ltr, arabic_ltr);
    try checkLine("shaped rtl", recorded_arabic_rtl, arabic_rtl);

    // Scale by 64 to express font units as 26.6 pixels.
    font.setScale(2048 * 64, 2048 * 64);
    try check("scale x after setScale", @as(i32, 2048 * 64), font.scale().x);
    const pixels = try shapeLine(&font, std.heap.page_allocator, "HarfBuzz", hb.direction_ltr);
    defer std.heap.page_allocator.free(pixels);
    std.debug.print("\n  the same run at 26.6 pixels\n", .{});
    std.debug.print("  {s: <24} {s}\n", .{ "shaped", pixels });

    if (hb.Blob.fromFile("/nonexistent-harfbuzz-smoke/no-such-font.ttf")) |opened| {
        var unexpected = opened;
        unexpected.deinit();
        return error.EnvironmentCheckFailed;
    } else |err| {
        std.debug.print("\n  missing font                 {s}\n", .{@errorName(err)});
        if (err != hb.Error.FileNotLoaded) return error.EnvironmentCheckFailed;
    }
    var prose = try hb.Blob.fromBytes("not a font");
    defer prose.deinit();
    if (hb.Face.create(&prose)) |opened| {
        var unexpected = opened;
        unexpected.deinit();
        return error.ShapeCheckFailed;
    } else |err| {
        std.debug.print("  bytes that are not a font    {s}\n", .{@errorName(err)});
        if (err != hb.Error.NoFace) return error.ShapeCheckFailed;
    }

    font.deinit();
    face.deinit();
    blob.deinit();
    std.debug.print("\nevery shaped line matched the value upstream recorded\n", .{});
}
