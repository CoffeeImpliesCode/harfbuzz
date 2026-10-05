// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.

//! Behavioural tests for the HarfBuzz SDK.
//!
//! ## Where the answers come from
//!
//! The primary fixture is an **upstream oracle**: HarfBuzz records its own
//! shaping expectations in `test/shape/data/in-house/tests/*.tests`, one line
//! per case, each line naming the font, the options, the codepoints and the
//! glyphs with their clusters and advances. Every shaping answer below is a
//! line from one of those files, transcribed here with the file and line it
//! came from. Nobody in this fork wrote those numbers: they were authored by
//! upstream, recorded by upstream's `test/shape/record-test.sh`, and this
//! package only reads them.
//!
//! Two `.tests` files are used, and each earns its place:
//!
//!   * `harfbust.tests` - the Latin font `HarfBust.ttf`, whose recorded lines
//!     name eight glyphs with eight distinct advances. It answers "does this
//!     build shape this font the way upstream does".
//!   * `digits.tests` - one Arabic font run twice, `--direction=ltr` on line 1
//!     and `--direction=rtl` on line 5. It answers "does direction reach the
//!     shaper", which a Latin-only fixture cannot ask.
//!
//! Line 6 of `harfbust.tests` is **deliberately not used**: it is qualified
//! `@shapers=harfrust,uniscribe,directwrite`, and this build has no such
//! shaper. A recorded answer for a shaper that is not compiled is not an
//! expectation this package can hold itself to, and copying it would be a
//! fabricated pass. Line 4's `@shapers=ot,coretext` includes `ot`, which is the
//! shaper `hb_shape` runs over an OpenType font, so line 4 is in scope.
//!
//! ## How a recorded line is reproduced
//!
//! Upstream's runner (`test/shape/run-tests.py:19`) sets `LC_ALL=C` and drives
//! `hb-shape`, which applies, in this order: `hb_buffer_add_utf8`,
//! `hb_buffer_guess_segment_properties`, then any `--direction` / `--script` /
//! `--language` from the line. `Fixture.shape` below does the same four steps
//! through this package's facade, so a recorded line and a line this file
//! compares against were produced the same way. The `LC_ALL=C` part matters:
//! `hb_language_get_default()` reads the locale, and "C" is what makes a
//! recorded line locale-independent. Run the tests under `LC_ALL=C`; the
//! workflow and `devenv.nix` do.
//!
//! The comparison itself is a string comparison against
//! `HB_BUFFER_SERIALIZE_FORMAT_TEXT`, which is the format upstream records in
//! (`src/hb-buffer-serialize.cc:273`, `:520`). The serializer is the shared
//! spelling of both sides; the *numbers* are upstream's.
//!
//! ## What these tests do NOT check
//!
//! There is no leak check. HarfBuzz allocates through the C library
//! (`src/hb.hh:555`, `#define hb_malloc_impl malloc`), so `std.testing`'s
//! allocator never sees a byte of it and this file's leaks, if any, are
//! invisible here. That is a stated limit, not a silent one.
//!
//! The FreeType-backed font is tested here too, through `hb.freetype`: the
//! facade publishes the sibling's module, so `hb.freetype.c.FT_FaceRec` is the
//! type `hb.FtFont.create` takes and the same type `hb.freetype.c.FT_New_
//! Memory_Face` fills in. Reaching for `hb.c` instead would not do: translate-c
//! types are nominal per module, so the same struct reached through two
//! modules is two unrelated Zig types.
//!
//! `hb.shape` and `Buffer.serializeText` take either font, so the FreeType tests
//! use this file's own helpers rather than reaching for the raw `hb_*` entry
//! points, and they pass `&font` on a `var` like any other caller: the facade
//! checks the pointee, not the pointer's constness (`zig/root.zig:551-561`), so
//! mutability is not a rule a caller has to learn.

const std = @import("std");
const testing = std.testing;

/// The typed facade, exactly as a dependent imports it.
const hb = @import("harfbuzz");

/// The environment variable naming a provider for the runtime route.
const provider_variable = "HARFBUZZ_TEST_PROVIDER";

/// Upstream's Latin in-house test font, the one `harfbust.tests` names.
const harfbust_bytes = @embedFile("test/shape/data/in-house/fonts/HarfBust.ttf");

/// The font `digits.tests:4-5` name, one Arabic fixture driven twice.
const arabic_bytes = @embedFile("test/shape/data/in-house/fonts/3b791518a9ba89675df02f1eefbc9026a50648a6.ttf");

// -- The recorded answers ---------------------------------------------------

/// `test/shape/data/in-house/tests/harfbust.tests:1`, transcribed.
///
/// `U+0048,U+0061,U+0072,U+0066,U+0042,U+0075,U+007A,U+007A` is "HarfBuzz".
const harfbust_buzzz_recorded =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|z=6+790|z=7+790]";

/// `harfbust.tests:2`: the same font, "HarfRust". Three of the eight advances
/// differ from line 1 and none of the eight glyph names is shared except the
/// first four, so this line cannot pass by accident when line 1 passes.
const harfbust_rust_recorded =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|R=4+976|u=5+1022|s=6+972|t=7+625]";

/// `harfbust.tests:4`, the `@shapers=ot,coretext` line: "HarfBust".
const harfbust_bust_recorded =
    "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|s=6+972|t=7+625]";

/// `harfbust.tests:1` read as a sum: 1022+990+710+574+980+1022+790+790.
const harfbust_buzzz_advance_total: i64 = 6878;

/// `test/shape/data/in-house/tests/digits.tests:1`, `--direction=ltr
/// --script=arab` over `U+06DD,U+0661,U+0662,U+0663`.
const arabic_ltr_recorded =
    "[AyahEnd.alt3=0+1724|OneArabic.encl=0@-1143,444+0|" ++
    "TwoArabic.encl=0@-864,444+0|ThreeArabic.encl=0@-584,444+0]";

/// `digits.tests:5`, the same four codepoints with `--direction=rtl`.
const arabic_rtl_recorded =
    "[ThreeArabic.encl=0@1140,444+0|TwoArabic.encl=0@860,444+0|" ++
    "OneArabic.encl=0@581,444+0|AyahEnd.alt3=0+1724]";

/// The design grid `HarfBust.ttf`'s own `head` table carries, and what
/// `Face.upem` must therefore answer with no call at all.
const harfbust_upem: u32 = 2048;

/// `HarfBust.ttf`'s `maxp` glyph count.
const harfbust_glyph_count: u32 = 99;

// -- Runtime plumbing -------------------------------------------------------

/// Load the runtime provider once, or do nothing in a linked build.
///
/// Under `-Druntime=true` there is no default provider and no fallback, so a
/// test that needs one and was not given one is a hard `@panic` naming the
/// variable rather than a silent skip: a skipped test is not a result.
fn nativeReady() void {
    if (comptime !hb.runtime_loaded) return;
    if (hb.loadedSource() != null) return;
    // `std.c.getenv`, not `std.posix.getenv`: this SDK links the C library in
    // every configuration, including the runtime one whose loader calls
    // `dlopen`, so the C spelling is the one present on every target here.
    const path = std.c.getenv(provider_variable) orelse @panic(
        "harfbuzz: this build resolves its entry points at run time. Set " ++
            provider_variable ++ " to the absolute path of a HarfBuzz provider " ++
            "(libharfbuzz.so.0, or the equivalent on this platform) before " ++
            "running these tests. There is no default location.",
    );
    // No `@errorName` in this message: under `-Druntime=true` the error set
    // comes from the generated dispatch (`hb.LoadError`), and naming its member
    // here needs a comptime value the loaded provider cannot supply. Which
    // provider failed is what the message has to say; the reason belongs to
    // the loader, which reports it through its own API.
    hb.load(.{ .path = std.mem.span(path) }) catch @panic(
        "harfbuzz: the provider named by " ++ provider_variable ++ " could not be loaded",
    );
}

/// The provider this process published, as a reader.
fn providerSource() ?[]const u8 {
    if (comptime !hb.runtime_loaded) return null;
    return switch (hb.loadedSource() orelse return null) {
        .path => |p| p,
        .system => |s| s,
    };
}

// -- An independent TrueType table reader -----------------------------------

/// The fields this file reads without HarfBuzz, decoded from the font's own
/// table directory.
///
/// Written from the OpenType specification, not from HarfBuzz's reader, so the
/// numbers asserted below are checked twice over the same bytes by two
/// implementations that share no code.
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

    /// `cmap` format 4: a codepoint's glyph index, read from the font.
    ///
    /// Format 4 is what the OpenType specification calls "segment mapping to
    /// delta values": a table of `endCode`/`startCode` segment pairs, a
    /// `idDelta` and an `idRangeOffset` per segment, and the two tables of
    /// offsets immediately after them (`cmap` offsets 14, 16, 18 and 20 in the
    /// specification's own numbering). A segment with `idRangeOffset` 0 maps
    /// by adding its delta; otherwise `idRangeOffset` is a byte offset *from
    /// its own slot in the `idRangeOffset` array* to a `glyphIdArray` entry,
    /// which the delta is then added to.
    ///
    /// Two subtables are chosen between by the specification's own rule: the
    /// `(3, 1)` BMP one is preferred, and the `(0, 3)` Unicode one is the
    /// fallback for a font that has only that.
    fn glyphIndex(bytes: []const u8, codepoint: u21) !u32 {
        const cmap = try table(bytes, "cmap");
        const head = bytes[cmap.offset..][0..cmap.length];
        if (head.len < 4) return error.TruncatedFont;
        const records = std.mem.readInt(u16, head[2..4], .big);
        if (head.len < 4 + @as(usize, records) * 8) return error.TruncatedFont;

        // Two passes rather than one loop with a remembered offset: the
        // preferred `(3, 1)` subtable may be listed *after* the `(0, 3)` one,
        // so remembering the fallback in a variable and returning it at the end
        // would hand back the less-preferred subtable whenever the font lists
        // the two in that order. Looking for `(3, 1)` first and only then for
        // `(0, 3)` cannot pick the wrong one.
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

        // Segments are sorted by `endCode`, so the first one that ends at or
        // after the codepoint is the only candidate.
        for (0..segments) |i| {
            const end = std.mem.readInt(u16, ends[i * 2 ..][0..2], .big);
            if (codepoint > end) continue;
            const start = std.mem.readInt(u16, starts[i * 2 ..][0..2], .big);
            if (codepoint < start) return 0;
            // `idDelta` is a signed 16-bit value the specification adds to the
            // code point, so the addition is done signed and the sum is taken
            // back to unsigned at the end.
            const delta: i16 = @bitCast(std.mem.readInt(u16, deltas[i * 2 ..][0..2], .big));
            const range_offset = std.mem.readInt(u16, ranges[i * 2 ..][0..2], .big);
            if (range_offset == 0)
                return @intCast(@as(i32, delta) + @as(i32, codepoint));
            // The offset is from this slot, not from the end of the table.
            const at = ranges_at + i * 2 + range_offset + 2 * @as(usize, codepoint - start);
            if (at + 2 > sub.len) return error.TruncatedFont;
            const glyph = std.mem.readInt(u16, sub[at..][0..2], .big);
            if (glyph == 0) return 0;
            return @intCast(@as(i32, delta) + @as(i32, glyph));
        }
        return 0;
    }
};

// -- Fixture ----------------------------------------------------------------

/// A blob, a face and a font over some bytes, and the teardown order they need.
///
/// `defer close()` is the contract: the font is destroyed before the face,
/// which is destroyed before the blob, because that is the order HarfBuzz
/// requires and this helper exists to make it unbreakable in every test.
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

/// Shape `text` over one font and return the buffer in upstream's text format.
///
/// The four steps are upstream's own, in upstream's order; see the module
/// documentation for why that order is part of the answer. Taking a font rather
/// than a `Fixture` is what lets a test hold a font that a fixture does not own.
fn shapeOver(font: *const hb.Font, text: []const u8, direction: hb.Direction) ![]u8 {
    var buffer = try hb.Buffer.create();
    defer buffer.deinit();
    try buffer.addUtf8(text);
    buffer.guessSegmentProperties();
    buffer.setDirection(direction);
    try hb.shape(font, &buffer, &.{});
    return buffer.serializeText(font, testing.allocator);
}

/// The same, over a fixture's own font.
fn shapeRecordedLine(fixture: *const Fixture, text: []const u8, direction: hb.Direction) ![]u8 {
    return shapeOver(&fixture.font, text, direction);
}

// -- FreeType-backed fonts --------------------------------------------------

/// How many times the callback below ran, and which face it was handed.
///
/// The callback deliberately does *not* close anything. A destroy callback
/// that called `FT_Done_Face` would prove nothing about *when* the closing
/// happens, and the caller's own `FT_Done_Face` in `FtFixture.close` would then
/// be a double free. Recording instead of closing is what makes the ownership
/// transition observable without risking it.
var ft_destroy_calls: usize = 0;
var ft_destroy_face: ?*anyopaque = null;

fn recordFaceDestroy(data: ?*anyopaque) callconv(.c) void {
    ft_destroy_calls += 1;
    ft_destroy_face = data;
}

/// An `FT_Library` and one `FT_Face` over the embedded fixture.
///
/// Reached through `hb.freetype`, the sibling's own published module, because
/// that is the same module `hb.FtFont.create` takes its `*FT_FaceRec` from. The
/// sibling's `FT_Library` and `FT_Face` are C pointer types, so they are
/// `undefined` rather than null before the constructors fill them in.
const FtFixture = struct {
    library: hb.freetype.c.FT_Library,
    face: hb.freetype.c.FT_Face,

    fn open() !FtFixture {
        nativeReady();
        var library: hb.freetype.c.FT_Library = undefined;
        if (hb.freetype.c.FT_Init_FreeType(&library) != 0) return error.FreeTypeRefused;
        errdefer _ = hb.freetype.c.FT_Done_FreeType(library);
        var face: hb.freetype.c.FT_Face = undefined;
        // `FT_New_Memory_Face` takes `const FT_Byte *`
        // (`include/freetype/freetype.h:2615`), so the embedded fixture's bytes
        // go in as they are: the signature says FreeType does not write through
        // that pointer, and nothing here has to copy a 10 KB font to respect it.
        if (hb.freetype.c.FT_New_Memory_Face(library, harfbust_bytes.ptr, @intCast(harfbust_bytes.len), 0, &face) != 0)
            return error.FreeTypeRefused;
        // The size, before any `hb_font_t` exists, because upstream says it has
        // to be: `src/hb-ft.h:1483-1484` puts it in a `<note>` on
        // `hb_ft_font_create_referenced` - "You must set the face size on
        // @ft_face before calling ... HarfBuzz assumes size is always set and
        // will access `size` member of FT_Face unconditionally."
        //
        // The consequence is visible: `hb_ft_font_changed` reads the scale out
        // of `ft_face->size->metrics` (`src/hb-ft.cc:1404-1406`), and a freshly
        // opened face reports 0 there until a size is set, so a font built over
        // it comes up with scale 0 and every advance 0.
        //
        // `upem` points, which at FreeType's default 72 dpi is `upem / 64` = 32
        // ppem for this font, is what puts the font's scale back at the design
        // grid: `hb_ft_font_changed` reads the scale back as
        // `size->metrics.x_scale * upem >> 16`, and 32 ppem over a 2048-unit em
        // is `x_scale = 65536`, so the font's scale is 2048 and its advances are
        // the `hmtx` entries the recorded line was written from.
        if (hb.freetype.c.FT_Set_Char_Size(face, @intCast(harfbust_upem), @intCast(harfbust_upem), 0, 0) != 0)
            return error.FreeTypeRefused;
        return .{ .library = library, .face = face };
    }

    /// One close of each, in the order FreeType requires.
    fn close(self: *FtFixture) void {
        _ = hb.freetype.c.FT_Done_Face(self.face);
        _ = hb.freetype.c.FT_Done_FreeType(self.library);
    }

    /// The face as the pointer `FtFont` constructors take.
    ///
    /// `FT_Face` is `typedef struct FT_FaceRec_ *FT_Face`, which translate-c
    /// turns into the many-item pointer `[*c]FT_FaceRec`; a single-item
    /// pointer is the same address, so this is a narrowing of the type and
    /// nothing else.
    fn record(self: *const FtFixture) *hb.freetype.c.FT_FaceRec {
        return @ptrCast(self.face);
    }
};

/// Shape through a FreeType-backed font and return the line.
///
/// The same four steps as `shapeOver`, and through the same two facade calls:
/// `hb.shape` and `Buffer.serializeText` take an `FtFont` as readily as a `Font`
/// and check the pointee rather than the pointer (`zig/root.zig:551-561`), so
/// there is nothing here that the `Font` route cannot do. What the two routes
/// cannot share is the *font*, and that is the point: this line must match the
/// recorded one for a font whose metrics came from FreeType rather than from
/// HarfBuzz's own `hmtx` reader.
///
/// The parameter is `*const` because that is how the call sites read best, not
/// because the check requires it: a `*FtFont` on a `var` is equally good.
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
    // The very face the caller opened is the one behind the font: the
    // referenced form borrows rather than copies.
    try testing.expectEqual(ft.record(), handed_back);

    const line = try shapeFreeTypeLine(&font, "HarfBuzz");
    defer testing.allocator.free(line);
    // Same eight advances as the OpenType-table route in the tests above, and
    // the same recorded line. HarfBuzz read those numbers from `hmtx`; here
    // FreeType's scaler produced them at the ppem this scale selects
    // (upem/64 = 32 for this font, so every advance is an exact multiple of
    // 1/64 px). Two independent metric readers and one upstream recording.
    try testing.expectEqualStrings(harfbust_buzzz_recorded, line);
}

test "the two FreeType constructors differ in who closes the face" {
    var ft = try FtFixture.open();
    defer ft.close();

    // The owning form: the caller's callback *is* the closing decision.
    // `src/hb-ft.h:109-110` takes it as the second argument and `src/hb-ft.cc:1375`
    // hands it to the `hb_face_t` it builds, so it runs exactly once, when the
    // HarfBuzz font is destroyed and not before.
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
    // The face is the caller's again: nothing behind the callback's back closed
    // it, and a font that is gone has no face left to report.
    try testing.expect(!owned.isOpen());
    try testing.expectEqual(@as(?*hb.freetype.c.FT_FaceRec, null), owned.ftFace());
    try testing.expectEqual(@as(c_long, 99), ft.face[0].num_glyphs);
    try testing.expectEqual(@as(c_ushort, 2048), ft.face[0].units_per_EM);

    // The referenced form: HarfBuzz takes its own reference and closes that one
    // with upstream's own static destroy (`src/hb-ft.cc:1503-1504`), so the
    // caller's callback is never consulted and the caller's face survives.
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

// -- Tests ------------------------------------------------------------------

test "the fixture is the font the recorded answers were taken from" {
    // Two readers over the same bytes: this file's table walk and HarfBuzz's.
    // `Face.create` attaches HarfBuzz's own OpenType font functions, so the
    // face is the one upstream's own tests shaped with.
    var fixture = try Fixture.open(harfbust_bytes);
    defer fixture.close();

    try testing.expectEqual(harfbust_upem, try TrueType.upem(harfbust_bytes));
    try testing.expectEqual(harfbust_upem, fixture.face.upem());
    try testing.expectEqual(harfbust_glyph_count, try TrueType.glyphCount(harfbust_bytes));
    try testing.expectEqual(harfbust_glyph_count, fixture.face.glyphCount());

    // The default scale is the face's own design grid, which is why the
    // recorded advances are in font units and why no call is needed to get
    // there (`src/hb-ot-font.cc` scales by `upem` unless told otherwise).
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

    // Two more lines of the same file, so one cannot satisfy all three: the
    // glyph names differ from `HarfBuzz` at three positions and the advances
    // differ at five.
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
    // Before shaping the buffer counts codepoints.
    try testing.expectEqual(@as(u32, 8), buffer.len());

    buffer.guessSegmentProperties();
    buffer.setDirection(hb.direction_ltr);
    try hb.shape(&fixture.font, &buffer, &.{});

    // After shaping it counts glyphs. The count is the same as the
    // codepoint count, and that is what the recorded line says: it names all
    // eight, `H a r f B u z z`, and the last two carry clusters 6 and 7 of
    // their own. This font has no `zz` ligature, so a run that came back with
    // seven glyphs would be a shaper that had substituted something upstream
    // does not substitute here - and the recorded advances would not add up.
    try testing.expectEqual(@as(u32, 8), buffer.len());
    try testing.expectEqual(@as(usize, 8), buffer.infos().len);
    try testing.expectEqual(@as(usize, 8), buffer.positions().len);

    // Every glyph names the character it came from, and clusters never go
    // backwards in a left-to-right run. These are the two things that make
    // the run a mapping rather than a bag: a shaper that emitted garbage or
    // reversed the cluster values would fail here even if it happened to
    // produce the right advances.
    //
    // "Names the character it came from" is a glyph index and not a codepoint,
    // because that is what the field holds once the buffer holds glyphs:
    // `src/hb-buffer.h:45-46` says `@codepoint: either a Unicode code point
    // (before shaping) or a glyph index (after shaping)`. The expected indices
    // come from this file's own `cmap` reader rather than from a constant, so
    // HarfBuzz's `cmap` walk and the one above are checked against each other
    // over the same bytes.
    const codepoints = [_]u21{ 'H', 'a', 'r', 'f', 'B', 'u', 'z', 'z' };
    var previous_cluster: u32 = 0;
    for (buffer.infos(), 0..) |info, index| {
        try testing.expectEqual(try TrueType.glyphIndex(harfbust_bytes, codepoints[index]), info.codepoint);
        try testing.expect(info.cluster >= previous_cluster);
        previous_cluster = info.cluster;
    }
    // The first cluster is 0 and the last is 7, so the run covers every
    // codepoint it was given and none of them was merged.
    try testing.expectEqual(@as(u32, 0), buffer.infos()[0].cluster);
    try testing.expectEqual(@as(u32, 7), buffer.infos()[7].cluster);

    // And the advances add up to the recorded line's own total.
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

    // `upem * 64` asks for 26.6 pixels. HarfBuzz scales by `x_scale / upem`, so
    // with `x_scale = upem * 64` the factor is exactly 64 - no rounding, which
    // is why this is an equality and not a tolerance.
    fixture.font.setScale(@intCast(harfbust_upem * 64), @intCast(harfbust_upem * 64));
    try testing.expectEqual(@as(i32, @intCast(harfbust_upem * 64)), fixture.font.scale().x);

    var pixels = try hb.Buffer.create();
    defer pixels.deinit();
    try pixels.addUtf8("HarfBuzz");
    pixels.guessSegmentProperties();
    pixels.setDirection(hb.direction_ltr);
    try hb.shape(&fixture.font, &pixels, &.{});

    // The scale changes what a position means and nothing else: same glyphs,
    // same codepoints, same clusters, in the same order.
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
    // `digits.tests:4` and `:5` are the same four codepoints through the same
    // font, once left to right and once right to left. The two lines differ in
    // glyph order *and* in the sign of every x_offset, so neither a shaper that
    // ignored the direction nor one that reversed the glyphs without reversing
    // the offsets can match.
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
    // `hb-shape` guesses and then applies the line's `--direction`, so a line
    // with no direction option is a guessed one. The first strong character
    // here is U+06DD ARABIC END OF AYAH, so the guess is right-to-left and the
    // guessed run must equal the recorded rtl line.
    const run = "\u{06DD}\u{0661}\u{0662}\u{0663}";
    var fixture = try Fixture.open(arabic_bytes);
    defer fixture.close();

    var buffer = try hb.Buffer.create();
    defer buffer.deinit();
    try buffer.addUtf8(run);
    buffer.guessSegmentProperties();
    try hb.shape(&fixture.font, &buffer, &.{});

    // `digits.tests:5` was recorded with `--direction=rtl`, which is what the
    // guess produces here; the Latin run of `harfbust.tests` guesses left to
    // right, which is why those lines need no option either.
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

    // The empty answer is the empty string, not the two brackets. The
    // brackets are written unconditionally once the formatter runs, but
    // `hb_buffer_serialize_glyphs` returns before it reaches the formatter at
    // all: `src/hb-buffer-serialize.cc:517-518` is
    // `if (unlikely (start == end)) return 0;`, and an empty buffer has
    // `hb_buffer_get_length` 0, so `start` and `end` are both 0. What that
    // leaves is what `serializeText` reports: `buf_consumed` stays 0, so the
    // line is empty. `[]` would be the formatter's answer for a buffer that
    // had been shaped and came back with no glyphs, which is a different
    // thing than a buffer that was never given any text.
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

    // `hb_buffer_clear_contents` empties the text and the glyphs, and it
    // resets the segment properties too: `src/hb-buffer.cc:1500-1507` calls
    // `buffer->clear()`, and `hb_buffer_t::clear` (`:301-307`) begins
    // `props = default_props` where `HB_SEGMENT_PROPERTIES_DEFAULT` is
    // `HB_DIRECTION_INVALID`. The upstream documentation for the function
    // says what survives and what does not - "Similar to hb_buffer_reset(),
    // but does not clear the Unicode functions and the replacement code
    // point" (`:1495-1496`) - and the direction is not on that list. So the
    // direction below reads back as invalid, and that is the assertion: a
    // caller that empties a buffer has to set the direction again, and a
    // buffer that reported the old one would be shaping text the caller no
    // longer thinks it set.
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

    // A copy the test owns, scribbled over *after* the blob is created. The
    // blob is `HB_MEMORY_MODE_READONLY`, so HarfBuzz copies what it needs and
    // the recorded answer must survive the caller destroying its own bytes.
    // This is the ownership transition; it is not a round trip through this
    // package's own code.
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

    // Reverse construction order, and each `deinit` clears its own handle, so
    // a second close is a no-op rather than a double free.
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

    // The directory does not exist, so the *or fail* blob constructor answers
    // null rather than an empty blob - which is the whole reason
    // `Blob.fromFile` uses that form. The refusal is what is asserted here.
    //
    // `FileNotLoaded` is the tag that says "the null is reported, not its
    // cause": upstream answers null for a path it could not open, for an
    // `fstat`, `mmap` or read failure, for its own ~536 MB ceiling and for a
    // failed allocation alike (`src/hb-blob.cc:622`, `:627`, `:631`, `:649`,
    // `:735`, `:740`, `:750`, `:751`, `:762`), and this wrapper checked none of
    // those. A missing path is the usual cause and the tag does not claim to be
    // the only one.
    try testing.expectError(
        hb.Error.FileNotLoaded,
        hb.Blob.fromFile("/nonexistent-harfbuzz-fixture-directory/no-such-font.ttf"),
    );
}

test "bytes that are not a font are refused rather than shaped" {
    nativeReady();

    // A blob of prose is a real blob - `Blob.fromBytes` succeeds - and the face
    // over it is not. `hb_face_create_or_fail` answers null when the blob holds
    // no face at index 0 (`src/hb-face.cc:293-294`), which is a different fact
    // from a failed allocation and gets its own tag for that reason.
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
        // A linked build chose nothing: it was given its provider at link
        // time. Reporting a source here would be a fiction.
        try testing.expectEqual(@as(?[]const u8, null), providerSource());
    }
}