// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Tests the HarfBuzz facade against upstream-recorded shaping results and fonts.
//! Run under `LC_ALL=C`; runtime-loaded builds require `HARFBUZZ_TEST_PROVIDER`.

const std = @import("std");
const testing = std.testing;

const hb = @import("harfbuzz");

const provider_variable = "HARFBUZZ_TEST_PROVIDER";

/// Upstream Latin fixture font used by `harfbust.tests`.
const harfbust_bytes = @embedFile("test/shape/data/in-house/fonts/HarfBust.ttf");

/// Upstream Arabic fixture font used by `digits.tests`.
const arabic_bytes = @embedFile("test/shape/data/in-house/fonts/3b791518a9ba89675df02f1eefbc9026a50648a6.ttf");

/// Upstream record `test/shape/data/in-house/tests/harfbust.tests:1`.
const harfbust_buzzz_recorded =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|z=6+790|z=7+790]";

/// Upstream record `test/shape/data/in-house/tests/harfbust.tests:2`.
const harfbust_rust_recorded =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|R=4+976|u=5+1022|s=6+972|t=7+625]";

/// Upstream record `test/shape/data/in-house/tests/harfbust.tests:4`.
const harfbust_bust_recorded =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|s=6+972|t=7+625]";

/// Sum of advances in `test/shape/data/in-house/tests/harfbust.tests:1`.
const harfbust_buzzz_advance_total: i64 = 6878;

/// Upstream `digits.tests:1` ltr record for the four Arabic codepoints.
const arabic_ltr_recorded =
    "[AyahEnd.alt3=0+1724|OneArabic.encl=0@-1143,444+0|" ++
    "TwoArabic.encl=0@-864,444+0|ThreeArabic.encl=0@-584,444+0]";

/// Upstream `digits.tests:5` rtl record for the same four codepoints.
const arabic_rtl_recorded =
    "[ThreeArabic.encl=0@1140,444+0|TwoArabic.encl=0@860,444+0|" ++
    "OneArabic.encl=0@581,444+0|AyahEnd.alt3=0+1724]";

/// Units per em from the HarfBust `head` table.
const harfbust_upem: u32 = 2048;

/// Glyph count from the HarfBust `maxp` table.
const harfbust_glyph_count: u32 = 99;

/// Loads the explicit runtime provider once; linked builds need none.
fn nativeReady() void {
    if (comptime !hb.runtime_loaded) return;
    if (hb.loadedSource() != null) return;
    // Use `std.c.getenv`; this package links libc in every configuration.
    const path = std.c.getenv(provider_variable) orelse @panic(
        "harfbuzz: this build resolves its entry points at run time. Set " ++
            provider_variable ++ " to the absolute path of a HarfBuzz provider " ++
            "(libharfbuzz.so.0, or the equivalent on this platform) before " ++
            "running these tests. There is no default location.",
    );
    // Keep this message independent of generated loader error-set members.
    hb.load(.{ .path = std.mem.span(path) }) catch @panic(
        "harfbuzz: the provider named by " ++ provider_variable ++ " could not be loaded",
    );
}

/// Returns the provider's path or loader name, or null for linked builds.
fn providerSource() ?[]const u8 {
    if (comptime !hb.runtime_loaded) return null;
    return switch (hb.loadedSource() orelse return null) {
        .path => |p| p,
        .system => |s| s,
    };
}

/// Reads selected font-table fields independently to validate fixture metadata.
const TrueType = struct {
    const Table = struct { offset: usize, length: usize };

    fn table(bytes: []const u8, tag: *const [4]u8) !Table {
        if (bytes.len < 12) return error.TruncatedFont;
        const count = std.mem.readInt(u16, bytes[4..6], .big);
        if (bytes.len < 12 + @as(usize, count) * 16) return error.TruncatedFont;
        for (0..count) |i| {
            const record = 12 + @as(usize, i) * 16;
            if (std.mem.eql(u8, bytes[record..][0..4], tag)) {
                const offset = std.mem.readInt(u32, bytes[record + 8 ..][0..4], .big);
                const length = std.mem.readInt(u32, bytes[record + 12 ..][0..4], .big);
                if (@as(usize, offset) + @as(usize, length) > bytes.len) return error.TruncatedFont;
                return .{ .offset = @intCast(offset), .length = @intCast(length) };
            }
        }
        return error.MissingTable;
    }

    /// `head.unitsPerEm`, `head` offset 18.
    fn upem(bytes: []const u8) !u32 {
        const head = try table(bytes, "head");
        if (head.length < 20) return error.TruncatedFont;
        return std.mem.readInt(u16, bytes[head.offset + 18 ..][0..2], .big);
    }

    /// `maxp.numGlyphs`, `maxp` offset 4.
    fn glyphCount(bytes: []const u8) !u32 {
        const maxp = try table(bytes, "maxp");
        if (maxp.length < 6) return error.TruncatedFont;
        return std.mem.readInt(u16, bytes[maxp.offset + 4 ..][0..2], .big);
    }

    /// Reads a glyph index from a format-4 `cmap` subtable.
    /// Prefer `(3,1)`, fall back to `(0,3)`, regardless of table order.
    /// `idRangeOffset` is relative to its own slot in the offset array.
    fn glyphIndex(bytes: []const u8, codepoint: u21) !u32 {
        const cmap = try table(bytes, "cmap");
        const head = bytes[cmap.offset..][0..cmap.length];
        if (head.len < 4) return error.TruncatedFont;
        const records = std.mem.readInt(u16, head[2..4], .big);
        if (head.len < 4 + @as(usize, records) * 8) return error.TruncatedFont;

        // Search the preferred `(3,1)` subtable first, regardless of file order.
        for ([_]struct { platform: u16, encoding: u16 }{
            .{ .platform = 3, .encoding = 1 },
            .{ .platform = 0, .encoding = 3 },
        }) |wanted| {
            for (0..records) |i| {
                const record = head[4 + @as(usize, i) * 8 ..][0..8];
                if (std.mem.readInt(u16, record[0..2], .big) != wanted.platform) continue;
                if (std.mem.readInt(u16, record[2..4], .big) != wanted.encoding) continue;
                const offset: usize = std.mem.readInt(u32, record[4..8], .big);
                if (offset + 2 > head.len) continue;
                if (std.mem.readInt(u16, head[offset..][0..2], .big) != 4) continue;
                return format4Lookup(head[offset..], codepoint);
            }
        }
        return error.MissingTable;
    }

    fn format4Lookup(sub: []const u8, codepoint: u21) !u32 {
        if (sub.len < 16) return error.TruncatedFont;
        const seg_x2 = std.mem.readInt(u16, sub[6..8], .big);
        if (seg_x2 == 0 or seg_x2 % 2 != 0) return error.TruncatedFont;
        const segments = @as(usize, seg_x2) / 2;
        const ends_at = 14;
        const starts_at = ends_at + seg_x2 + 2;
        const deltas_at = starts_at + seg_x2;
        const ranges_at = deltas_at + seg_x2;
        if (ranges_at + seg_x2 > sub.len) return error.TruncatedFont;

        const ends = sub[ends_at..][0..seg_x2];
        const starts = sub[starts_at..][0..seg_x2];
        const deltas = sub[deltas_at..][0..seg_x2];
        const ranges = sub[ranges_at..][0..seg_x2];

        // Segments are sorted by `endCode`; the first match is the only candidate.
        for (0..segments) |i| {
            const end = std.mem.readInt(u16, ends[i * 2 ..][0..2], .big);
            if (codepoint > end) continue;
            const start = std.mem.readInt(u16, starts[i * 2 ..][0..2], .big);
            if (codepoint < start) return 0;
            // Add the signed `idDelta` to the codepoint before converting to unsigned.
            const delta: i16 = @bitCast(std.mem.readInt(u16, deltas[i * 2 ..][0..2], .big));
            const range_offset = std.mem.readInt(u16, ranges[i * 2 ..][0..2], .big);
            if (range_offset == 0)
                return @intCast(@as(i32, delta) + @as(i32, codepoint));
            // `idRangeOffset` is relative to this slot in the offset array.
            const at = ranges_at + i * 2 + range_offset + 2 * @as(usize, codepoint - start);
            if (at + 2 > sub.len) return error.TruncatedFont;
            const glyph = std.mem.readInt(u16, sub[at..][0..2], .big);
            if (glyph == 0) return 0;
            return @intCast(@as(i32, delta) + @as(i32, glyph));
        }
        return 0;
    }
};

/// Owns a blob, face, and font; close them in reverse construction order.
const Fixture = struct {
    blob: hb.Blob,
    face: hb.Face,
    font: hb.Font,

    fn open(bytes: []const u8) !Fixture {
        nativeReady();
        var blob = try hb.Blob.fromBytes(bytes);
        errdefer blob.deinit();
        var face = try hb.Face.create(&blob);
        errdefer face.deinit();
        const font = try hb.Font.create(&face);
        return .{ .blob = blob, .face = face, .font = font };
    }

    fn close(self: *Fixture) void {
        self.font.deinit();
        self.face.deinit();
        self.blob.deinit();
    }
};

/// Shapes with upstream's setup order and returns an allocated text-format line.
fn shapeOver(font: *const hb.Font, text: []const u8, direction: hb.Direction) ![]u8 {
    var buffer = try hb.Buffer.create();
    defer buffer.deinit();
    try buffer.addUtf8(text);
    buffer.guessSegmentProperties();
    buffer.setDirection(direction);
    try hb.shape(font, &buffer, &.{});
    return buffer.serializeText(font, testing.allocator);
}

fn shapeRecordedLine(fixture: *const Fixture, text: []const u8, direction: hb.Direction) ![]u8 {
    return shapeOver(&fixture.font, text, direction);
}

/// Tracks callback invocations and the face passed to it.
var ft_destroy_calls: usize = 0;
var ft_destroy_face: ?*anyopaque = null;

fn recordFaceDestroy(data: ?*anyopaque) callconv(.c) void {
    ft_destroy_calls += 1;
    ft_destroy_face = data;
}

/// Owns an `FT_Library` and `FT_Face` over the embedded font fixture.
/// Uses the sibling module whose `FT_FaceRec` type appears in `FtFont`'s API.
const FtFixture = struct {
    library: hb.freetype.c.FT_Library,
    face: hb.freetype.c.FT_Face,

    fn open() !FtFixture {
        nativeReady();
        var library: hb.freetype.c.FT_Library = undefined;
        if (hb.freetype.c.FT_Init_FreeType(&library) != 0) return error.FreeTypeRefused;
        errdefer _ = hb.freetype.c.FT_Done_FreeType(library);
        var face: hb.freetype.c.FT_Face = undefined;
        if (hb.freetype.c.FT_New_Memory_Face(library, harfbust_bytes.ptr, @intCast(harfbust_bytes.len), 0, &face) != 0)
            return error.FreeTypeRefused;
        // Set the FreeType face size before creating an `hb_font_t`; HarfBuzz reads its metrics.
        if (hb.freetype.c.FT_Set_Char_Size(face, @intCast(harfbust_upem), @intCast(harfbust_upem), 0, 0) != 0)
            return error.FreeTypeRefused;
        return .{ .library = library, .face = face };
    }

    /// Closes the face, then the FreeType library.
    fn close(self: *FtFixture) void {
        _ = hb.freetype.c.FT_Done_Face(self.face);
        _ = hb.freetype.c.FT_Done_FreeType(self.library);
    }

    /// Narrows the translated FreeType `FT_Face` pointer to a single-item pointer.
    fn record(self: *const FtFixture) *hb.freetype.c.FT_FaceRec {
        return @ptrCast(self.face);
    }
};

/// Shapes with a FreeType-backed font and returns an allocated serialized line.
fn shapeFreeTypeLine(font: *const hb.FtFont, text: []const u8) ![]u8 {
    var buffer = try hb.Buffer.create();
    defer buffer.deinit();
    try buffer.addUtf8(text);
    buffer.guessSegmentProperties();
    buffer.setDirection(hb.direction_ltr);
    try hb.shape(font, &buffer, &.{});
    return buffer.serializeText(font, testing.allocator);
}

test "a FreeType-backed font shapes the recorded line from FreeType's own metrics" {
    var ft = try FtFixture.open();
    defer ft.close();

    var font = hb.FtFont.createReferenced(ft.record());
    defer font.deinit();
    try testing.expect(font.isOpen());
    const handed_back = font.ftFace() orelse return error.FreeTypeRefused;
    // The referenced form returns the same face the caller supplied.
    try testing.expectEqual(ft.record(), handed_back);

    const line = try shapeFreeTypeLine(&font, "HarfBuzz");
    defer testing.allocator.free(line);
    // FreeType's metrics match the recorded line at the selected design-grid scale.
    try testing.expectEqualStrings(harfbust_buzzz_recorded, line);
}

test "the two FreeType constructors differ in who closes the face" {
    var ft = try FtFixture.open();
    defer ft.close();

    // The caller's destroy callback runs when the HarfBuzz font is destroyed.
    ft_destroy_calls = 0;
    ft_destroy_face = null;
    var owned = hb.FtFont.create(ft.record(), &recordFaceDestroy);
    try testing.expect(owned.isOpen());
    try testing.expectEqual(@as(usize, 0), ft_destroy_calls);
    try testing.expectEqual(ft.record(), owned.ftFace() orelse return error.FreeTypeRefused);

    const owned_line = try shapeFreeTypeLine(&owned, "HarfBuzz");
    defer testing.allocator.free(owned_line);
    try testing.expectEqualStrings(harfbust_buzzz_recorded, owned_line);

    owned.deinit();
    try testing.expectEqual(@as(usize, 1), ft_destroy_calls);
    try testing.expectEqual(@as(?*anyopaque, @ptrCast(ft.face)), ft_destroy_face);
    // The callback records the event without closing the caller's face.
    try testing.expect(!owned.isOpen());
    try testing.expectEqual(@as(?*hb.freetype.c.FT_FaceRec, null), owned.ftFace());
    try testing.expectEqual(@as(c_long, 99), ft.face[0].num_glyphs);
    try testing.expectEqual(@as(c_ushort, 2048), ft.face[0].units_per_EM);

    // HarfBuzz releases only its added reference; the caller's face remains open.
    ft_destroy_calls = 0;
    var borrowed = hb.FtFont.createReferenced(ft.record());
    try testing.expectEqual(@as(usize, 0), ft_destroy_calls);

    const borrowed_line = try shapeFreeTypeLine(&borrowed, "HarfBuzz");
    defer testing.allocator.free(borrowed_line);
    try testing.expectEqualStrings(harfbust_buzzz_recorded, borrowed_line);

    borrowed.deinit();
    try testing.expectEqual(@as(usize, 0), ft_destroy_calls);
    try testing.expectEqual(@as(c_long, 99), ft.face[0].num_glyphs);
}

test "the fixture is the font the recorded answers were taken from" {
    // Compare independent font-table reads with HarfBuzz's metadata.
    var fixture = try Fixture.open(harfbust_bytes);
    defer fixture.close();

    try testing.expectEqual(harfbust_upem, try TrueType.upem(harfbust_bytes));
    try testing.expectEqual(harfbust_upem, fixture.face.upem());
    try testing.expectEqual(harfbust_glyph_count, try TrueType.glyphCount(harfbust_bytes));
    try testing.expectEqual(harfbust_glyph_count, fixture.face.glyphCount());

    // The default scale is the face's units per em.
    try testing.expectEqual(@as(i32, @intCast(harfbust_upem)), fixture.font.scale().x);
    try testing.expectEqual(@as(i32, @intCast(harfbust_upem)), fixture.font.scale().y);
}

test "HarfBuzz shapes HarfBuzz into the line upstream recorded" {
    var fixture = try Fixture.open(harfbust_bytes);
    defer fixture.close();

    const line = try shapeRecordedLine(&fixture, "HarfBuzz", hb.direction_ltr);
    defer testing.allocator.free(line);
    try testing.expectEqualStrings(harfbust_buzzz_recorded, line);
}

test "the same font and a different string give a different recorded line" {
    var fixture = try Fixture.open(harfbust_bytes);
    defer fixture.close();

    // These records differ in glyph names and advances.
    const rust = try shapeRecordedLine(&fixture, "HarfRust", hb.direction_ltr);
    defer testing.allocator.free(rust);
    try testing.expectEqualStrings(harfbust_rust_recorded, rust);

    const bust = try shapeRecordedLine(&fixture, "HarfBust", hb.direction_ltr);
    defer testing.allocator.free(bust);
    try testing.expectEqualStrings(harfbust_bust_recorded, bust);
}

test "shaping advances the buffer from eight codepoints to eight glyphs" {
    var fixture = try Fixture.open(harfbust_bytes);
    defer fixture.close();

    var buffer = try hb.Buffer.create();
    defer buffer.deinit();
    try buffer.addUtf8("HarfBuzz");
    try testing.expectEqual(@as(u32, 8), buffer.len());

    buffer.guessSegmentProperties();
    buffer.setDirection(hb.direction_ltr);
    try hb.shape(&fixture.font, &buffer, &.{});

    // The recorded run has eight glyphs and no ligature merges the final `zz`.
    try testing.expectEqual(@as(u32, 8), buffer.len());
    try testing.expectEqual(@as(usize, 8), buffer.infos().len);
    try testing.expectEqual(@as(usize, 8), buffer.positions().len);

    // Compare glyph ids with the independent cmap reader and require monotone clusters.
    // HarfBuzz exposes glyph ids in `info.codepoint` after shaping.
    const codepoints = [_]u21{ 'H', 'a', 'r', 'f', 'B', 'u', 'z', 'z' };
    var previous_cluster: u32 = 0;
    for (buffer.infos(), 0..) |info, index| {
        try testing.expectEqual(try TrueType.glyphIndex(harfbust_bytes, codepoints[index]), info.codepoint);
        try testing.expect(info.cluster >= previous_cluster);
        previous_cluster = info.cluster;
    }
    try testing.expectEqual(@as(u32, 0), buffer.infos()[0].cluster);
    try testing.expectEqual(@as(u32, 7), buffer.infos()[7].cluster);

    var total: i64 = 0;
    for (buffer.positions()) |position| total += @as(i64, position.x_advance);
    try testing.expectEqual(harfbust_buzzz_advance_total, total);
}

test "positions are font units, and a 26.6 scale multiplies every one by 64" {
    var fixture = try Fixture.open(harfbust_bytes);
    defer fixture.close();

    var units = try hb.Buffer.create();
    defer units.deinit();
    try units.addUtf8("HarfBuzz");
    units.guessSegmentProperties();
    units.setDirection(hb.direction_ltr);
    try hb.shape(&fixture.font, &units, &.{});
    var units_total: i64 = 0;
    for (units.positions()) |position| units_total += @as(i64, position.x_advance);

    // `upem * 64` gives an exact 26.6 scale, so advances can be compared exactly.
    fixture.font.setScale(@intCast(harfbust_upem * 64), @intCast(harfbust_upem * 64));
    try testing.expectEqual(@as(i32, @intCast(harfbust_upem * 64)), fixture.font.scale().x);

    var pixels = try hb.Buffer.create();
    defer pixels.deinit();
    try pixels.addUtf8("HarfBuzz");
    pixels.guessSegmentProperties();
    pixels.setDirection(hb.direction_ltr);
    try hb.shape(&fixture.font, &pixels, &.{});

    try testing.expectEqual(units.infos().len, pixels.infos().len);
    for (units.infos(), pixels.infos()) |before, after| {
        try testing.expectEqual(before.codepoint, after.codepoint);
        try testing.expectEqual(before.cluster, after.cluster);
    }
    var pixels_total: i64 = 0;
    for (pixels.positions()) |position| pixels_total += @as(i64, position.x_advance);
    try testing.expectEqual(units_total * 64, pixels_total);
    try testing.expectEqual(harfbust_buzzz_advance_total, units_total);
}

test "direction reaches the shaper: one Arabic run, two recorded answers" {
    // The upstream Arabic records differ in glyph order and x-offset signs.
    const run = "\u{06DD}\u{0661}\u{0662}\u{0663}";
    var fixture = try Fixture.open(arabic_bytes);
    defer fixture.close();

    const ltr = try shapeRecordedLine(&fixture, run, hb.direction_ltr);
    defer testing.allocator.free(ltr);
    try testing.expectEqualStrings(arabic_ltr_recorded, ltr);

    const rtl = try shapeRecordedLine(&fixture, run, hb.direction_rtl);
    defer testing.allocator.free(rtl);
    try testing.expectEqualStrings(arabic_rtl_recorded, rtl);

    try testing.expect(!std.mem.eql(u8, ltr, rtl));
}

test "guessing the direction reaches the same answer as naming it" {
    // U+06DD is the first strong character, so HarfBuzz guesses right-to-left.
    const run = "\u{06DD}\u{0661}\u{0662}\u{0663}";
    var fixture = try Fixture.open(arabic_bytes);
    defer fixture.close();

    var buffer = try hb.Buffer.create();
    defer buffer.deinit();
    try buffer.addUtf8(run);
    buffer.guessSegmentProperties();
    try hb.shape(&fixture.font, &buffer, &.{});

    try testing.expectEqual(hb.direction_rtl, buffer.direction());

    const guessed = try buffer.serializeText(&fixture.font, testing.allocator);
    defer testing.allocator.free(guessed);
    try testing.expectEqualStrings(arabic_rtl_recorded, guessed);
}

test "an empty buffer has nothing to serialize" {
    var fixture = try Fixture.open(harfbust_bytes);
    defer fixture.close();

    var buffer = try hb.Buffer.create();
    defer buffer.deinit();

    try testing.expectEqual(@as(u32, 0), buffer.len());
    try testing.expectEqual(@as(usize, 0), buffer.infos().len);
    try testing.expectEqual(@as(usize, 0), buffer.positions().len);

    // An unpopulated buffer serializes to an empty string, not `[]`.
    const line = try buffer.serializeText(&fixture.font, testing.allocator);
    defer testing.allocator.free(line);
    try testing.expectEqualStrings("", line);
}

test "clearing a buffer keeps its settings and shapes the same text the same way" {
    var fixture = try Fixture.open(harfbust_bytes);
    defer fixture.close();

    var buffer = try hb.Buffer.create();
    defer buffer.deinit();

    try buffer.addUtf8("HarfBuzz");
    buffer.guessSegmentProperties();
    buffer.setDirection(hb.direction_ltr);
    try hb.shape(&fixture.font, &buffer, &.{});
    const first = try buffer.serializeText(&fixture.font, testing.allocator);
    defer testing.allocator.free(first);

    // Buffer.clear resets segment properties but preserves Unicode functions and replacement codepoint.
    buffer.clear();
    try testing.expectEqual(@as(u32, 0), buffer.len());
    try testing.expectEqual(hb.direction_invalid, buffer.direction());

    try buffer.addUtf8("HarfBuzz");
    buffer.setDirection(hb.direction_ltr);
    try hb.shape(&fixture.font, &buffer, &.{});
    const second = try buffer.serializeText(&fixture.font, testing.allocator);
    defer testing.allocator.free(second);

    try testing.expectEqualStrings(first, second);
    try testing.expectEqualStrings(harfbust_buzzz_recorded, second);
}

test "a blob over bytes the caller owns is independent of them" {
    nativeReady();

    // Mutating caller bytes after `fromBytes` must not change the copied blob.
    var copy: [harfbust_bytes.len]u8 = undefined;
    @memcpy(&copy, harfbust_bytes);
    var blob = try hb.Blob.fromBytes(&copy);
    defer blob.deinit();
    @memset(&copy, 0);

    var face = try hb.Face.create(&blob);
    defer face.deinit();
    var font = try hb.Font.create(&face);
    defer font.deinit();

    const line = try shapeOver(&font, "HarfBuzz", hb.direction_ltr);
    defer testing.allocator.free(line);
    try testing.expectEqualStrings(harfbust_buzzz_recorded, line);
}

test "closing is a transition this module owns" {
    nativeReady();

    var blob = try hb.Blob.fromBytes(harfbust_bytes);
    try testing.expect(blob.isOpen());
    var face = try hb.Face.create(&blob);
    try testing.expect(face.isOpen());
    var font = try hb.Font.create(&face);
    try testing.expect(font.isOpen());
    var buffer = try hb.Buffer.create();
    try testing.expect(buffer.isOpen());

    buffer.deinit();
    font.deinit();
    face.deinit();
    blob.deinit();

    try testing.expect(!buffer.isOpen());
    try testing.expect(!font.isOpen());
    try testing.expect(!face.isOpen());
    try testing.expect(!blob.isOpen());

    buffer.deinit();
    font.deinit();
    face.deinit();
    blob.deinit();
    try testing.expect(!blob.isOpen());
}

test "a font path that cannot be opened is refused" {
    nativeReady();

    // HarfBuzz reports a null file blob without identifying the I/O or allocation cause.
    try testing.expectError(
        hb.Error.FileNotLoaded,
        hb.Blob.fromFile("/nonexistent-harfbuzz-fixture-directory/no-such-font.ttf"),
    );
}

test "bytes that are not a font are refused rather than shaped" {
    nativeReady();

    // Prose bytes form a blob but not a face.
    var blob = try hb.Blob.fromBytes("this is not a font, it is prose");
    defer blob.deinit();
    try testing.expect(blob.isOpen());
    try testing.expectError(hb.Error.NoFace, hb.Face.create(&blob));
}

test "a successful runtime load is visible, and a linked build chose no provider" {
    nativeReady();
    if (comptime hb.runtime_loaded) {
        try testing.expect(providerSource() != null);
    } else {
        // Linked builds have no external provider.
        try testing.expectEqual(@as(?[]const u8, null), providerSource());
    }
}
