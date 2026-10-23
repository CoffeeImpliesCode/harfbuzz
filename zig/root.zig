// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! Typed HarfBuzz facade over translated C declarations and sibling FreeType.
//! Owns C handles explicitly and exposes linked or runtime-loaded entry points.

const std = @import("std");

/// The translated HarfBuzz headers, including FreeType's through `<hb-ft.h>`,
/// or the generated dispatch over them under `-Druntime=true`.
pub const c = @import("c");

/// Sibling FreeType module used by `FtFont`; its `FT_FaceRec` type appears in public signatures.
/// Import this module to construct and name those same C types.
pub const freetype = @import("freetype");

const rt = @import("rt");

/// Whether this build resolves HarfBuzz's entry points at run time.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Where a runtime-loaded provider comes from.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Why a runtime load did not happen.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads the explicit provider for runtime dispatch; its handle stays open until process exit.
/// Returns `LoadError` on failure; linked builds panic because no provider is configured.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime runtime_loaded) {
        return c.load(source);
    }
    std.debug.panic(
        "harfbuzz: load was called on a build that links HarfBuzz, so every " ++
            "entry point is already resolved. Rebuild with -Druntime=true to " ++
            "select a provider at run time.",
        .{},
    );
}

/// The provider this process published, or `null`.
pub fn loadedSource() ?LoadSource {
    if (comptime runtime_loaded) return c.loadedSource();
    return null;
}

/// HarfBuzz version reported by the translated headers; the build manifest must match.
pub const version: std.SemanticVersion = .{
    .major = c.HB_VERSION_MAJOR,
    .minor = c.HB_VERSION_MINOR,
    .patch = c.HB_VERSION_MICRO,
};

/// Upstream direction enum, re-exported so callers can pass values to the C API.
pub const Direction = c.hb_direction_t;

pub const direction_invalid: Direction = c.HB_DIRECTION_INVALID;
pub const direction_ltr: Direction = c.HB_DIRECTION_LTR;
pub const direction_rtl: Direction = c.HB_DIRECTION_RTL;
pub const direction_ttb: Direction = c.HB_DIRECTION_TTB;
pub const direction_btt: Direction = c.HB_DIRECTION_BTT;

/// `hb_buffer_cluster_level_t`, re-exported for the same reason.
pub const ClusterLevel = c.hb_buffer_cluster_level_t;

pub const cluster_level_monotone_graphemes: ClusterLevel = c.HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES;
pub const cluster_level_monotone_characters: ClusterLevel = c.HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS;
pub const cluster_level_characters: ClusterLevel = c.HB_BUFFER_CLUSTER_LEVEL_CHARACTERS;
pub const cluster_level_graphemes: ClusterLevel = c.HB_BUFFER_CLUSTER_LEVEL_GRAPHEMES;

/// Errors reported by HarfBuzz or by facade argument checks.
pub const Error = error{
    /// HarfBuzz's shaping entry point returned false; it does not report a cause.
    ShapingFailed,
    /// HarfBuzz reported allocation failure through its empty-object or buffer-success signal.
    OutOfMemory,
    /// File loading failed; HarfBuzz does not distinguish I/O and allocation causes.
    FileNotLoaded,
    /// No face exists at index zero or HarfBuzz could not allocate one.
    NoFace,
    /// An argument exceeds a C API limit, or the caller's output buffer is too small.
    InvalidArgument,
};

/// Owns one `hb_blob_t`; `fromBytes` copies the caller's input.
pub const Blob = struct {
    raw: ?*c.hb_blob_t = null,

    /// Opens a font file and returns an owned blob or `FileNotLoaded`.
    pub fn fromFile(path: [*:0]const u8) Error!Blob {
        const blob = c.hb_blob_create_from_file_or_fail(path) orelse
            return Error.FileNotLoaded;
        return .{ .raw = blob };
    }

    /// Copies caller bytes into an owned blob; rejects lengths above the C API limit.
    pub fn fromBytes(bytes: []const u8) Error!Blob {
        if (bytes.len > std.math.maxInt(c_uint)) return Error.InvalidArgument;
        // Upstream returns an empty blob for zero-length input and allocation failure alike.
        // No upstream status distinguishes those cases.
        const blob = c.hb_blob_create(
            bytes.ptr,
            @intCast(bytes.len),
            c.HB_MEMORY_MODE_DUPLICATE,
            null,
            null,
        );
        return .{ .raw = blob };
    }

    /// Destroys the blob and clears its handle.
    pub fn deinit(self: *Blob) void {
        if (self.raw) |blob| c.hb_blob_destroy(blob);
        self.raw = null;
    }

    pub fn isOpen(self: *const Blob) bool {
        return self.raw != null;
    }

    pub fn handle(self: *const Blob) *c.hb_blob_t {
        return self.raw orelse @panic(
            "harfbuzz: this Blob was closed; deinit() clears the handle and " ++
                "there is nothing left to hand to a face. Check isOpen() if " ++
                "the lifetime is not obvious.",
        );
    }

    /// Returns the blob length in bytes.
    pub fn len(self: *const Blob) u32 {
        return c.hb_blob_get_length(self.handle());
    }
};

/// Owns one `hb_face_t` for the font's face and table metadata.
pub const Face = struct {
    raw: ?*c.hb_face_t = null,

    /// Creates face index 0 from `blob`; returns `NoFace` if creation fails.
    pub fn create(blob: *const Blob) Error!Face {
        const face = c.hb_face_create_or_fail(blob.handle(), 0) orelse
            return Error.NoFace;
        return .{ .raw = face };
    }

    /// Destroys the face and clears its handle.
    pub fn deinit(self: *Face) void {
        if (self.raw) |face| c.hb_face_destroy(face);
        self.raw = null;
    }

    pub fn isOpen(self: *const Face) bool {
        return self.raw != null;
    }

    pub fn handle(self: *const Face) *c.hb_face_t {
        return self.raw orelse @panic(
            "harfbuzz: this Face was closed; deinit() clears the handle and " ++
                "there is no face left to build a font from. Check isOpen() if " ++
                "the lifetime is not obvious.",
        );
    }

    /// Returns units per em from the font's `head` table.
    pub fn upem(self: *const Face) u32 {
        return c.hb_face_get_upem(self.handle());
    }

    /// Returns the glyph count from the `maxp` table.
    pub fn glyphCount(self: *const Face) u32 {
        return c.hb_face_get_glyph_count(self.handle());
    }

    /// Writes a glyph name into caller-owned `buffer`; returns null when unavailable.
    pub fn glyphName(self: *const Face, glyph: u32, buffer: []u8) ?[]const u8 {
        if (buffer.len == 0) return null;
        if (!c.hb_face_get_glyph_name(self.handle(), glyph, buffer.ptr, @intCast(buffer.len))) {
            return null;
        }
        const terminator = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
        if (terminator == 0) return null;
        return buffer[0..terminator];
    }
};

/// Owns one HarfBuzz font used for shaping.
pub const Font = struct {
    raw: ?*c.hb_font_t = null,

    /// Creates an OpenType font over `face` with HarfBuzz's font functions.
    /// Returns `OutOfMemory` if HarfBuzz creates its empty-font sentinel.
    pub fn create(face: *const Face) Error!Font {
        const font = c.hb_font_create(face.handle());
        if (font == c.hb_font_get_empty()) return Error.OutOfMemory;
        c.hb_ot_font_set_funcs(font);
        return .{ .raw = font };
    }

    /// Destroys the font and clears its handle.
    pub fn deinit(self: *Font) void {
        if (self.raw) |font| c.hb_font_destroy(font);
        self.raw = null;
    }

    pub fn isOpen(self: *const Font) bool {
        return self.raw != null;
    }

    pub fn handle(self: *const Font) *c.hb_font_t {
        return self.raw orelse @panic(
            "harfbuzz: this Font was closed; deinit() clears the handle and " ++
                "there is no font left to shape against. Check isOpen() if the " ++
                "lifetime is not obvious.",
        );
    }

    /// Sets the position scale on both axes.
    /// The default is the face's units per em; `upem * 64` gives 26.6 pixel units.
    pub fn setScale(self: *Font, x_scale: c_int, y_scale: c_int) void {
        c.hb_font_set_scale(self.handle(), x_scale, y_scale);
    }

    /// Returns the current horizontal and vertical scales.
    pub fn scale(self: *const Font) struct { x: c_int, y: c_int } {
        var x: c_int = 0;
        var y: c_int = 0;
        c.hb_font_get_scale(self.handle(), &x, &y);
        return .{ .x = x, .y = y };
    }

    /// Sets pixels per em for rasterization without changing the metrics scale.
    pub fn setPpem(self: *Font, x_ppem: c_uint, y_ppem: c_uint) void {
        c.hb_font_set_ppem(self.handle(), x_ppem, y_ppem);
    }

    /// Returns the glyph's horizontal advance in the current scale units.
    pub fn glyphAdvance(self: *const Font, glyph: u32) i32 {
        return c.hb_font_get_glyph_h_advance(self.handle(), glyph);
    }
};

/// Owns one `hb_buffer_t` for text input and shaped glyph output.
pub const Buffer = struct {
    raw: ?*c.hb_buffer_t = null,

    pub fn create() Error!Buffer {
        // Check HarfBuzz's success flag; creation returns an empty buffer on allocation failure.
        const buffer = c.hb_buffer_create();
        if (c.hb_buffer_allocation_successful(buffer) == 0) return Error.OutOfMemory;
        return .{ .raw = buffer };
    }

    /// Destroys the buffer and clears its handle.
    pub fn deinit(self: *Buffer) void {
        if (self.raw) |buffer| c.hb_buffer_destroy(buffer);
        self.raw = null;
    }

    pub fn isOpen(self: *const Buffer) bool {
        return self.raw != null;
    }

    pub fn handle(self: *const Buffer) *c.hb_buffer_t {
        return self.raw orelse @panic(
            "harfbuzz: this Buffer was closed; deinit() clears the handle and " ++
                "there is nothing left to shape. Check isOpen() if the lifetime " ++
                "is not obvious.",
        );
    }

    /// Clears text and resets segment properties; Unicode functions and replacement codepoint remain.
    pub fn clear(self: *Buffer) void {
        c.hb_buffer_clear_contents(self.handle());
    }

    /// Adds the full UTF-8 slice; returns `InvalidArgument` if its length exceeds `c_int`.
    pub fn addUtf8(self: *Buffer, text: []const u8) Error!void {
        if (text.len > std.math.maxInt(c_int)) return Error.InvalidArgument;
        c.hb_buffer_add_utf8(self.handle(), text.ptr, @intCast(text.len), 0, -1);
    }

    pub fn setDirection(self: *Buffer, dir: Direction) void {
        c.hb_buffer_set_direction(self.handle(), dir);
    }

    pub fn direction(self: *const Buffer) Direction {
        return c.hb_buffer_get_direction(self.handle());
    }

    pub fn setClusterLevel(self: *Buffer, level: ClusterLevel) void {
        c.hb_buffer_set_cluster_level(self.handle(), level);
    }

    /// Guesses unset script, direction, and language from the buffer text.
    pub fn guessSegmentProperties(self: *Buffer) void {
        c.hb_buffer_guess_segment_properties(self.handle());
    }

    /// Returns the codepoint count before shaping or glyph count after shaping.
    pub fn len(self: *const Buffer) u32 {
        var length: c_uint = 0;
        _ = c.hb_buffer_get_glyph_infos(self.handle(), &length);
        return length;
    }

    /// Returns glyph infos borrowed from the buffer; mutation may replace them.
    pub fn infos(self: *const Buffer) []const c.hb_glyph_info_t {
        var length: c_uint = 0;
        const pointer = c.hb_buffer_get_glyph_infos(self.handle(), &length) orelse
            return &.{};
        return pointer[0..length];
    }

    /// Returns glyph positions borrowed from the buffer; mutation may replace them.
    pub fn positions(self: *const Buffer) []const c.hb_glyph_position_t {
        var length: c_uint = 0;
        const pointer = c.hb_buffer_get_glyph_positions(self.handle(), &length) orelse
            return &.{};
        return pointer[0..length];
    }

    /// Serializes glyphs in HarfBuzz's text format from a `Font` or `FtFont`.
    /// The caller frees the result with `allocator`; failures return `OutOfMemory` or `InvalidArgument`.
    pub fn serializeText(
        self: *const Buffer,
        font: anytype,
        allocator: std.mem.Allocator,
    ) Error![]u8 {
        requireFontType(@TypeOf(font));

        // Recheck consumed length; the estimate only sizes the temporary buffer.
        const estimate = 64 + @as(usize, self.len()) * 256;
        const scratch = try allocator.allocSentinel(u8, estimate, 0);
        defer allocator.free(scratch);

        var consumed: c_uint = 0;
        _ = c.hb_buffer_serialize_glyphs(
            self.handle(),
            0,
            c.hb_buffer_get_length(self.handle()),
            scratch.ptr,
            @intCast(scratch.len),
            &consumed,
            font.handle(),
            c.HB_BUFFER_SERIALIZE_FORMAT_TEXT,
            0,
        );
        if (consumed > scratch.len) return Error.InvalidArgument;
        return try allocator.dupe(u8, scratch[0..consumed]);
    }
};

fn requireFontType(comptime Font_: type) void {
    const pointer = switch (@typeInfo(Font_)) {
        .pointer => |info| info,
        else => @compileError("harfbuzz: a font is passed by pointer"),
    };
    if (pointer.size != .one) @compileError("harfbuzz: a font is a single-item pointer, not a slice or a many-pointer");
    switch (pointer.child) {
        Font, FtFont => {},
        else => @compileError("harfbuzz: expected a Font or an FtFont"),
    }
}

/// Shapes the buffer with supplied features and HarfBuzz's default shapers.
/// Borrows the font, buffer, and features; returns `InvalidArgument` or `ShapingFailed`.
pub fn shape(font: anytype, buffer: *Buffer, features: []const c.hb_feature_t) Error!void {
    requireFontType(@TypeOf(font));
    if (features.len > std.math.maxInt(c_uint)) return Error.InvalidArgument;
    // A null shaper list selects the same default shapers as upstream's `hb_shape`.
    const no_shapers: [*c]const [*c]const u8 = @ptrFromInt(0);
    if (c.hb_shape_full(
        font.handle(),
        buffer.handle(),
        if (features.len == 0) &.{} else features.ptr,
        @intCast(features.len),
        no_shapers,
    ) == 0) return Error.ShapingFailed;
}

/// Owns one HarfBuzz font backed by a FreeType face.
/// `create` uses the caller's destroy callback; `createReferenced` retains the face.
pub const FtFont = struct {
    raw: ?*c.hb_font_t = null,

    /// Wraps caller's `FT_Face`; `destroy` controls when HarfBuzz releases it.
    /// HarfBuzz exposes no error result for font-function allocation failure.
    pub fn create(ft_face: *freetype.c.FT_FaceRec, destroy: c.hb_destroy_func_t) FtFont {
        return .{ .raw = c.hb_ft_font_create(@ptrCast(ft_face), destroy) };
    }

    /// Creates a wrapper after HarfBuzz references `ft_face`; the caller retains its face.
    pub fn createReferenced(ft_face: *freetype.c.FT_FaceRec) FtFont {
        return .{ .raw = c.hb_ft_font_create_referenced(@ptrCast(ft_face)) };
    }

    /// Returns the borrowed FreeType face, or null if closed or not FreeType-backed.
    pub fn ftFace(self: *const FtFont) ?*freetype.c.FT_FaceRec {
        const font = self.raw orelse return null;
        const face = c.hb_ft_font_get_ft_face(font);
        if (@intFromPtr(face) == 0) return null;
        return @ptrCast(face);
    }

    /// Sets FreeType load flags; the default disables hinting.
    pub fn setLoadFlags(self: *FtFont, flags: c_int) void {
        c.hb_ft_font_set_load_flags(self.handle(), flags);
    }

    /// Returns the current FreeType load flags.
    pub fn loadFlags(self: *const FtFont) c_int {
        return c.hb_ft_font_get_load_flags(self.handle());
    }

    /// Destroys the font and clears its handle.
    pub fn deinit(self: *FtFont) void {
        if (self.raw) |font| c.hb_font_destroy(font);
        self.raw = null;
    }

    pub fn isOpen(self: *const FtFont) bool {
        return self.raw != null;
    }

    pub fn handle(self: *const FtFont) *c.hb_font_t {
        return self.raw orelse @panic(
            "harfbuzz: this FtFont was closed; deinit() clears the handle and " ++
                "there is no font left to shape against. Check isOpen() if the " ++
                "lifetime is not obvious.",
        );
    }

    /// Sets the HarfBuzz scale and FreeType character size used for metrics and rasterization.
    pub fn setScale(self: *FtFont, x_scale: c_int, y_scale: c_int) void {
        c.hb_font_set_scale(self.handle(), x_scale, y_scale);
    }
};
