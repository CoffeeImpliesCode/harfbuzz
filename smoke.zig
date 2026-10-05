// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! A deterministic example program for the HarfBuzz SDK.
//!
//! It shapes three strings out of two of upstream's own test fonts, prints
//! what HarfBuzz answered, and compares each answer with a line recorded by
//! upstream in `test/shape/data/in-house/tests/`. Nothing here is a golden
//! image or a golden count: every expected value is a line somebody else
//! wrote, and this program says which file it came from.
//!
//! Run it under `LC_ALL=C`. `test/shape/run-tests.py:19` sets that variable for
//! the same reason this program needs it: `hb_language_get_default()` reads the
//! locale, and under "C" it answers no language at all, which is the
//! configuration the recorded lines were taken in.
//!
//! Under `-Druntime=true` it needs `HARFBUZZ_TEST_PROVIDER`; a linked build
//! needs nothing.

const std = @import("std");
const hb = @import("harfbuzz");

const harfbust_bytes = @embedFile("test/shape/data/in-house/fonts/HarfBust.ttf");
const arabic_bytes = @embedFile("test/shape/data/in-house/fonts/3b791518a9ba89675df02f1eefbc9026a50648a6.ttf");

const provider_variable = "HARFBUZZ_TEST_PROVIDER";

/// Every failure below is one named condition, so a failing smoke run says what
/// was wrong instead of panicking in the middle of a sentence.
const SmokeError = error{
    ProviderCheckFailed,
    EnvironmentCheckFailed,
    ShapeCheckFailed,
    SerializeCheckFailed,
};

/// `harfbust.tests:1`, "HarfBuzz". The line's own codepoints are
/// `U+0048,U+0061,U+0072,U+0066,U+0042,U+0075,U+007A,U+007A`, so the last two
/// are `z` and not `Z`.
const recorded_buzzz =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|z=6+790|z=7+790]";

/// `harfbust.tests:4`, "HarfBust".
const recorded_bust =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|s=6+972|t=7+625]";

/// `digits.tests:1`, `--direction=ltr --script=arab` over the same four
/// codepoints the rtl line uses.
const recorded_arabic_ltr =
    "[AyahEnd.alt3=0+1724|OneArabic.encl=0@-1143,444+0|" ++
    "TwoArabic.encl=0@-864,444+0|ThreeArabic.encl=0@-584,444+0]";
/// `digits.tests:5`, `--direction=rtl`.
const recorded_arabic_rtl =
    "[ThreeArabic.encl=0@1140,444+0|TwoArabic.encl=0@860,444+0|" ++
    "OneArabic.encl=0@581,444+0|AyahEnd.alt3=0+1724]";

/// Load the runtime provider, or do nothing in a linked build.
fn nativeReady() !void {
    if (comptime !hb.runtime_loaded) return;
    if (hb.loadedSource() != null) return;
    const path = std.c.getenv(provider_variable) orelse return error.EnvironmentCheckFailed;
    hb.load(.{ .path = std.mem.span(path) }) catch return error.ProviderCheckFailed;
}

/// Print one labelled line and compare it with the recorded one.
fn checkLine(label: []const u8, expected: []const u8, actual: []const u8) SmokeError!void {
    std.debug.print("  {s: <24} {s}\n", .{ label, actual });
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("  {s: <24} expected {s}\n", .{ label, expected });
        return error.ShapeCheckFailed;
    }
}

/// Print one labelled number and compare it.
fn check(comptime label: [:0]const u8, expected: anytype, actual: @TypeOf(expected)) SmokeError!void {
    std.debug.print("  {s: <24} {any}\n", .{ label, actual });
    if (expected != actual) {
        std.debug.print("  {s: <24} expected {any}, got {any}\n", .{ label, expected, actual });
        return error.SerializeCheckFailed;
    }
}

/// Shape one string the way upstream's `hb-shape` does and return the line.
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

    // Printed, never compared: the release is provenance, and a test that
    // pinned it would be testing a string constant.
    std.debug.print("  library version             {f}\n", .{hb.version});
    try check("design grid (units/em)", @as(u32, 2048), face.upem());
    try check("glyph count", @as(u32, 99), face.glyphCount());
    try check("blob length (bytes)", @as(u32, harfbust_bytes.len), blob.len());
    std.debug.print("  scale (font units)          {d},{d}\n", .{ font.scale().x, font.scale().y });

    // Three recorded lines, three different questions.
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
    // Both lines are compared: line 1 is the recorded `--direction=ltr` answer
    // and line 5 the recorded `--direction=rtl` one, and they differ in glyph
    // order *and* in the sign of every x_offset, so neither can pass by being
    // the other one.
    try checkLine("shaped ltr", recorded_arabic_ltr, arabic_ltr);
    try checkLine("shaped rtl", recorded_arabic_rtl, arabic_rtl);

    // 26.6 pixels: the same run, every position multiplied by exactly 64.
    font.setScale(2048 * 64, 2048 * 64);
    try check("scale x after setScale", @as(i32, 2048 * 64), font.scale().x);
    const pixels = try shapeLine(&font, std.heap.page_allocator, "HarfBuzz", hb.direction_ltr);
    defer std.heap.page_allocator.free(pixels);
    std.debug.print("\n  the same run at 26.6 pixels\n", .{});
    std.debug.print("  {s: <24} {s}\n", .{ "shaped", pixels });

    // The two error paths, because an example that cannot fail is not evidence
    // that anything works.
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