// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! The typed surface over HarfBuzz 14.5.1's buffer / shape / font API, plus the
//! FreeType-backed font that the sibling `freetype` package provides.
//!
//! ## Import routes
//!
//! One published route, `dep.module("harfbuzz")`, which is this file. The
//! translated headers are on it as `c`, and are never a module of their own, so
//! there is exactly one `hb_buffer_t` type per build whichever surface is used.
//!
//! ## The sibling FreeType, and what this package does about it
//!
//! `FtFont` wraps `hb_ft_font_create`, which needs an `FT_Face`. Those types come
//! from the *sibling* `../freetype` source tree, never from an installed
//! FreeType: `build.zig` puts that tree's `include/` on the compile line and
//! links that package's own compiled archive. There is no configuration in
//! which that integration is off: `-Dfreetype=none` is refused at configure
//! time, so `FtFont` is always compiled and never answers null for a feature
//! that was switched off. See `build.zig`'s module doc for the linkage
//! decision.
//!
//! ## Positions are in the font's own units, and that is a decision
//!
//! `hb_font_set_scale` chooses what one position unit means. The default is the
//! face's `unitsPerEm`, so with no call at all HarfBuzz reports font design
//! units — which is exactly what upstream's own shaping tests in
//! `test/shape/data/in-house/tests/*.tests` contain, and this package's
//! known-answer tests compare against those lines. A caller that wants 26.6
//! pixels sets a scale of `upem * 64` and gets that instead; nothing in the C
//! API records which was chosen, so `Font.scale` is exposed as a reader and
//! every measurement helper here documents the unit it is in.
//!
//! ## Memory
//!
//! HarfBuzz allocates through the C library - there is no `src/hb-malloc.cc` in
//! this release, and `src/hb.hh:555-558` defines `hb_malloc_impl`,
//! `hb_calloc_impl`, `hb_realloc_impl` and `hb_free_impl` as `malloc`,
//! `calloc`, `realloc` and `free`, in the arm that is not `HB_CUSTOM_MALLOC` - so
//! a Zig allocator can neither bound nor intercept a single byte any object here
//! owns, and this package claims no leak oracle. What it does instead is make
//! every ownership transition explicit and test it: `Blob`, `Face`, `Font` and
//! `Buffer` each own exactly one C object, each `deinit` clears its handle so a
//! second call is a no-op, and `FtFont` documents that it closes the `FT_Face`
//! it was given unless it was created in the *referenced* form.
//!
//! ## Errors
//!
//! HarfBuzz's shaping entry point answers `hb_bool_t`, not an error code: `true`
//! means the buffer holds shaped glyphs, `false` means it holds the original
//! codepoints and nothing was consumed. `shape` reports that as
//! `Error.ShapingFailed` rather than hiding it, and leaves the buffer exactly as
//! HarfBuzz left it. It reads the answer off `hb_shape_full`, which is where
//! this release keeps it; see `shape`.

const std = @import("std");

/// The translated HarfBuzz headers, including FreeType's through `<hb-ft.h>`,
/// or the generated dispatch over them under `-Druntime=true`.
pub const c = @import("c");

/// The sibling FreeType's facade, named by `build.zig` from the same
/// `-Dfreetype=<path>` that selected the compiled sibling.
///
/// **This is a public re-export, not a private import.** `FtFont.create` and
/// `FtFont.createReferenced` name `*freetype.c.FT_FaceRec` in their signatures,
/// and a parameter type a dependent cannot name is a function it cannot call.
/// Publishing the alias is what makes those signatures usable from outside this
/// package, and it costs one declaration. A dependent that also depends on the
/// sibling names the same type through its own import; it is one type either
/// way, because both reach the same include root, and importing the sibling's
/// *module* rather than its raw translation is deliberate for that reason.
pub const freetype = @import("freetype");

/// The loader core, linked builds only.
const rt = @import("rt");

/// Whether this build resolves HarfBuzz's entry points at run time.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Where a runtime-loaded provider comes from.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Why a runtime load did not happen.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

// -- Runtime loading -------------------------------------------------------

/// Resolve every `hb_*` entry point from an explicit provider.
///
/// Only meaningful under `-Druntime=true`; a linked build panics with the reason
/// rather than returning a success it cannot honour.
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

// -- Constants -------------------------------------------------------------

/// The HarfBuzz release these headers describe.
///
/// Read out of `src/hb-version.h:44`, `:50` and `:56`. `build.zig` refuses to
/// configure when `build.zig.zon`'s `.version` and this tuple disagree.
pub const version: std.SemanticVersion = .{
    .major = c.HB_VERSION_MAJOR,
    .minor = c.HB_VERSION_MINOR,
    .patch = c.HB_VERSION_MICRO,
};

/// `hb_direction_t`, re-exported rather than restated.
///
/// `src/hb-common.h` numbers `HB_DIRECTION_INVALID` 0 and the four real
/// directions 1..4. The type is upstream's so that a caller can pass a value
/// the shaper itself produced back into another call without a conversion.
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

/// What this module reports when a HarfBuzz entry point that answers
/// `hb_bool_t` answered `false`.
pub const Error = error{
    /// `hb_shape` returned `false`: the buffer still holds the original
    /// codepoints. HarfBuzz does not say why - an unknown script and an
    /// exhausted internal allocator look the same from here - so this is one
    /// honest tag and not a taxonomy.
    ShapingFailed,
    /// HarfBuzz reported that its own allocator failed, through the signal
    /// upstream documents for that case and no other:
    /// `hb_buffer_allocation_successful` (`src/hb-buffer.cc:1539-1542`).
    ///
    /// It is deliberately *not* a general "a constructor answered null" tag.
    /// The two tags below are the ones that would have been, because a null
    /// there does not mean what this one says.
    OutOfMemory,
    /// `hb_blob_create_from_file_or_fail` answered null
    /// (`src/hb-blob.h:103-104`).
    ///
    /// Upstream answers null for a file it could not open
    /// (`src/hb-blob.cc:627`, `:740`), for a `fstat`, `mmap` or read failure
    /// (`:631`, `:649`, `:762`), for its own ~536 MB ceiling on the fallback
    /// reader (`:750`) and for a failed allocation (`:622`, `:735`, `:751`)
    /// alike. This wrapper checked none of those, so it reports the null
    /// rather than a cause. A path that does not exist is the usual one; this
    /// tag does not claim it is the only one.
    FileNotLoaded,
    /// `hb_face_create_or_fail` answered null (`src/hb-face.h:62-64`).
    ///
    /// Upstream answers null when the blob holds no face at index 0
    /// (`src/hb-face.cc:293-294`) and when the face object could not be
    /// allocated, which leaves it immutable (`:297-298`). Bytes that are not a
    /// font are the usual one; this tag does not claim it is the only one.
    NoFace,
    /// A call was given an argument this module could not describe to the C
    /// API: a length that does not fit the C type, or a buffer too small to
    /// hold the answer.
    InvalidArgument,
};

// -- Blob ------------------------------------------------------------------

/// One `hb_blob_t`: the font bytes, or any bytes HarfBuzz was handed.
pub const Blob = struct {
    raw: ?*c.hb_blob_t = null,

    /// `hb_blob_create_from_file`.
    ///
    /// This is the *or fail* form (`src/hb-blob.h:103-104`): a missing or
    /// unreadable file answers null rather than an empty blob. The alternative
    /// form returns an empty blob for the same inputs, which is a fine thing
    /// for a shaper to see and a terrible thing for a caller to be unable to
    /// tell apart from an empty font.
    pub fn fromFile(path: [*:0]const u8) Error!Blob {
        const blob = c.hb_blob_create_from_file_or_fail(path) orelse
            return Error.FileNotLoaded;
        return .{ .raw = blob };
    }

    /// `hb_blob_create` over memory the caller owns.
    ///
    /// `HB_MEMORY_MODE_DUPLICATE`, so HarfBuzz copies the bytes on the spot
    /// and the slice may go out of scope as soon as this returns.
    ///
    /// The copy is the point, not an optimisation. `src/hb-blob.h:41-42` says
    /// of `HB_MEMORY_MODE_READONLY` only that neither side writes the data:
    /// "HarfBuzz client will never modify the data, and HarfBuzz will never
    /// modify the data" - nothing about owning it. `src/hb-blob.cc:129-134`
    /// is where the two differ, and it is `DUPLICATE` alone that copies and
    /// then downgrades itself to `READONLY`; a `READONLY` blob keeps the
    /// caller's pointer, so scribbling over the caller's bytes afterwards
    /// scribbles over the font. Taking a slice whose lifetime this function
    /// does not control and handing it straight through would make that a
    /// dangling pointer the caller has no way to see, which is why this takes
    /// the one mode that answers `true` for "the bytes may go".
    pub fn fromBytes(bytes: []const u8) Error!Blob {
        if (bytes.len > std.math.maxInt(c_uint)) return Error.InvalidArgument;
        // `hb_blob_create` never returns null: `src/hb-blob.cc:75-84` answers
        // `hb_blob_get_empty()` for a zero-length input and for a failed
        // allocation alike, and this release declares no
        // `hb_blob_allocation_successful` that would tell the two apart. There
        // is no failure to observe here, so this does not invent one.
        const blob = c.hb_blob_create(
            bytes.ptr,
            @intCast(bytes.len),
            c.HB_MEMORY_MODE_DUPLICATE,
            null,
            null,
        );
        return .{ .raw = blob };
    }

    /// `hb_blob_destroy`. Clears `raw`.
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

    /// `hb_blob_get_length`, in bytes.
    pub fn len(self: *const Blob) u32 {
        return c.hb_blob_get_length(self.handle());
    }
};

// -- Face ------------------------------------------------------------------

/// One `hb_face_t`: a named font's tables, with no metrics and no shaping.
pub const Face = struct {
    raw: ?*c.hb_face_t = null,

    /// `hb_face_create_or_fail`.
    ///
    /// The *or fail* form again (`src/hb-face.h:62-64`): a caller that cannot
    /// get a face must be able to tell, and `hb_face_create` answering an empty
    /// face would make a truncated font indistinguishable from a real one.
    ///
    /// A null here is `Error.NoFace`, and reading it as an allocation failure
    /// would be wrong: "these bytes are not a font" is the ordinary case.
    pub fn create(blob: *const Blob) Error!Face {
        const face = c.hb_face_create_or_fail(blob.handle(), 0) orelse
            return Error.NoFace;
        return .{ .raw = face };
    }

    /// `hb_face_destroy`. Clears `raw`.
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

    /// `hb_face_get_upem`: the design grid, in font units per em.
    ///
    /// Read straight out of the font's `head` table, which is where
    /// HarfBuzz's own table reader reads it from.
    pub fn upem(self: *const Face) u32 {
        return c.hb_face_get_upem(self.handle());
    }

    /// `hb_face_get_glyph_count`, from `maxp`.
    pub fn glyphCount(self: *const Face) u32 {
        return c.hb_face_get_glyph_count(self.handle());
    }

    /// `hb_face_get_glyph_name`, borrowed.
    ///
    /// An empty name means the font does not carry one; that is a normal answer
    /// for a font that stores names some other way, not a failure.
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

// -- Font ------------------------------------------------------------------

/// One `hb_font_t`: the metrics HarfBuzz shapes against.
pub const Font = struct {
    raw: ?*c.hb_font_t = null,

    /// A font over a face, with HarfBuzz's own OpenType font functions
    /// attached.
    ///
    /// This is the *no-FreeType* route: metrics come from the font's own `hmtx`
    /// and `vmtx` tables through `src/hb-ot-font.cc`, so it needs no FreeType
    /// at all and is exactly what upstream's shaping tests exercise.
    ///
    /// `hb_font_create` over a face, with the OpenType functions attached here:
    /// it returns the empty font object rather than null when allocation fails
    /// (`src/hb-font.cc:2110-2111`) and leaves the font functions unset
    /// (`src/hb-font.cc:2149`), so detecting the first and doing the second are
    /// both this constructor's job.
    ///
    /// There is no `hb_font_create_or_fail` in this release: no header in the
    /// tree declares one and no `.cc` under `src/` defines one.
    pub fn create(face: *const Face) Error!Font {
        const font = c.hb_font_create(face.handle());
        if (font == c.hb_font_get_empty()) return Error.OutOfMemory;
        c.hb_ot_font_set_funcs(font);
        return .{ .raw = font };
    }

    /// `hb_font_destroy`. Clears `raw`.
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

    /// `hb_font_set_scale`: what one position unit means, on each axis.
    ///
    /// The default is the face's `unitsPerEm`, which is why this package's
    /// known-answer tests need no call here at all. Passing `upem * 64` asks for
    /// 26.6 pixels instead.
    pub fn setScale(self: *Font, x_scale: c_int, y_scale: c_int) void {
        c.hb_font_set_scale(self.handle(), x_scale, y_scale);
    }

    /// `hb_font_get_scale`, as a reader rather than a re-derivation.
    pub fn scale(self: *const Font) struct { x: c_int, y: c_int } {
        var x: c_int = 0;
        var y: c_int = 0;
        c.hb_font_get_scale(self.handle(), &x, &y);
        return .{ .x = x, .y = y };
    }

    /// `hb_font_set_ppem`, which changes rasterization but not metrics.
    pub fn setPpem(self: *Font, x_ppem: c_uint, y_ppem: c_uint) void {
        c.hb_font_set_ppem(self.handle(), x_ppem, y_ppem);
    }

    /// `hb_font_get_glyph_h_advance`, in this font's scale units.
    pub fn glyphAdvance(self: *const Font, glyph: u32) i32 {
        return c.hb_font_get_glyph_h_advance(self.handle(), glyph);
    }
};

// -- Buffer ----------------------------------------------------------------

/// One `hb_buffer_t`: the text in, then the glyphs out.
pub const Buffer = struct {
    raw: ?*c.hb_buffer_t = null,

    pub fn create() Error!Buffer {
        // `hb_buffer_create` never returns null: `src/hb-buffer.cc:771-773`
        // documents that, and `:782-783` answers the empty buffer object when
        // its allocation fails. `hb_buffer_allocation_successful`
        // (`src/hb-buffer.cc:1539-1542`) is upstream's reader for exactly that,
        // so this is where an allocation failure is actually observable.
        const buffer = c.hb_buffer_create();
        if (c.hb_buffer_allocation_successful(buffer) == 0) return Error.OutOfMemory;
        return .{ .raw = buffer };
    }

    /// `hb_buffer_destroy`. Clears `raw`.
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

    /// `hb_buffer_clear_contents`, which keeps the settings.
    ///
    /// Called by `clear` rather than reached for directly, because a caller
    /// that empties a buffer almost always wants the script and direction it
    /// already set to survive.
    pub fn clear(self: *Buffer) void {
        c.hb_buffer_clear_contents(self.handle());
    }

    /// `hb_buffer_add_utf8` for the whole slice.
    ///
    /// `text_length` is an `int`, so a slice longer than `maxInt(c_int)` cannot
    /// be described. Comparing is the honest answer; splitting the input would
    /// silently shape two different strings.
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

    /// `hb_buffer_guess_segment_properties`.
    ///
    /// The convenience a caller almost always wants: script, direction and
    /// language are guessed from the buffer's own contents, and a buffer whose
    /// script was set explicitly keeps it.
    pub fn guessSegmentProperties(self: *Buffer) void {
        c.hb_buffer_guess_segment_properties(self.handle());
    }

    /// `hb_buffer_get_length`: codepoints before shaping, glyphs after.
    pub fn len(self: *const Buffer) u32 {
        var length: c_uint = 0;
        _ = c.hb_buffer_get_glyph_infos(self.handle(), &length);
        return length;
    }

    /// The glyph infos, borrowed from the buffer.
    ///
    /// Borrowed, and overwritten by the next shape on this buffer. An empty
    /// buffer answers an empty slice rather than null, so a caller never has to
    /// distinguish "shaped nothing" from "has no array".
    pub fn infos(self: *const Buffer) []const c.hb_glyph_info_t {
        var length: c_uint = 0;
        const pointer = c.hb_buffer_get_glyph_infos(self.handle(), &length) orelse
            return &.{};
        return pointer[0..length];
    }

    /// The glyph positions, borrowed on the same terms as `infos`.
    pub fn positions(self: *const Buffer) []const c.hb_glyph_position_t {
        var length: c_uint = 0;
        const pointer = c.hb_buffer_get_glyph_positions(self.handle(), &length) orelse
            return &.{};
        return pointer[0..length];
    }

    /// `hb_buffer_serialize_glyphs` in the documented text format.
    ///
    /// This is the format upstream's own shaping tests record their answers in,
    /// and `src/hb-buffer-serialize.cc:273-338` is the code that produces it:
    /// `[name=cluster+advance|...]`, with `@dx,dy` for a non-zero offset. This
    /// package's known-answer tests build a line with it and compare the result
    /// with the answer transcribed from
    /// `test/shape/data/in-house/tests/harfbust.tests`, which is an independent
    /// oracle: the expectation was authored by upstream, and the formatter is
    /// only how both sides are written down.
    ///
    /// Returns `Error.InvalidArgument` when the buffer does not fit, rather than
    /// a silently truncated line that would compare unequal for the wrong
    /// reason. `allocator` supplies the scratch.
    ///
    /// `font` is a `Font` or an `FtFont` by pointer, mutable or not, exactly as
    /// in `shape`.
    pub fn serializeText(
        self: *const Buffer,
        font: anytype,
        allocator: std.mem.Allocator,
    ) Error![]u8 {
        requireFontType(@TypeOf(font));

        // The longest legal line is `[` + one `name=cluster@dx,dy+adv,adv`
        // segment per glyph + `|` separators + `]`. 256 bytes per glyph plus 64
        // is generous for a name this API can produce and is re-checked against
        // `buf_consumed` below rather than trusted.
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

/// The two font owners this module shapes with: `Font` and `FtFont`, by pointer.
///
/// `Font` is declared above this point and `FtFont` below it, and both names
/// resolve here regardless of where in the file they are written.
///
/// Mutability is deliberately not part of the rule. `deinit` takes `*Font` and
/// `*FtFont`, so a caller that has to close the font it owns holds a `var` and
/// writes `&font`, and `&font` is a `*FtFont`. The check is on the pointee, so
/// the mutability a caller happens to hold is not a thing it has to arrange and
/// no caller has to know which form this facade wanted. What is refused is
/// everything else, with a `@compileError` naming it: a third type that fits
/// here is a design decision rather than an accident.
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

// -- Shape -----------------------------------------------------------------

/// `hb_shape_full` with a null shaper list, which is what `hb_shape` is.
///
/// Features are an array of `hb_feature_t`, and this wrapper deliberately does
/// not hide them: a shaping test that cannot set a feature cannot prove a
/// substitution happened, which is most of what shaping *is*. A caller that
/// wants none passes an empty slice, which is exactly
/// `hb_shape(font, buffer, NULL, 0)`.
///
/// It is `hb_shape_full` rather than `hb_shape` because `src/hb-shape.h:43-44`
/// declares `hb_shape` as `HB_EXTERN void`: this release dropped the return
/// value from the short form and kept it on the long one (`:46-52`), which is
/// still `hb_bool_t`. There is no way to see "all shapers failed" through
/// `hb_shape`, and `Error.ShapingFailed` is a real answer rather than an
/// invented one, so this calls the entry point that has it. The shaper list is
/// null, which selects the default shapers - `src/hb-shape.cc:194` is
/// `hb_shape_full (font, buffer, features, num_features, nullptr)`, so this is
/// upstream's own short form with the return value kept.
///
/// `font` is a `Font` or an `FtFont` by pointer, mutable or not: `&font` works for
/// a `var` and for a `const`, because `deinit` takes the mutable form. Both own
/// one `hb_font_t` and hand it out the same way, and shaping does not care where
/// the metrics came from: a FreeType-backed font is shapeable, so refusing one
/// here would refuse a font that works. What this module keeps apart is where the
/// metrics come from, not whether shaping works.
pub fn shape(font: anytype, buffer: *Buffer, features: []const c.hb_feature_t) Error!void {
    requireFontType(@TypeOf(font));
    if (features.len > std.math.maxInt(c_uint)) return Error.InvalidArgument;
    // A null shaper list, spelled as a null many-item pointer because that is
    // what `const char * const *` translates to; upstream's own short form
    // passes exactly this (`src/hb-shape.cc:194`).
    const no_shapers: [*c]const [*c]const u8 = @ptrFromInt(0);
    if (c.hb_shape_full(
        font.handle(),
        buffer.handle(),
        if (features.len == 0) &.{} else features.ptr,
        @intCast(features.len),
        no_shapers,
    ) == 0) return Error.ShapingFailed;
}

// -- FreeType-backed objects -----------------------------------------------

/// `hb_ft_font_create`: a `hb_font_t` whose metrics come from FreeType.
///
/// Always compiled: `-Dfreetype=none` is refused at configure time, so there is
/// no configuration in which this type exists and FreeType is not there. See the
/// module doc for the linkage decision.
pub const FtFont = struct {
    raw: ?*c.hb_font_t = null,

    /// `hb_ft_font_create`: a font whose metrics come from FreeType, over a face
    /// whose closing the caller arranges.
    ///
    /// Upstream's entry point has two arguments and so does this one:
    /// `src/hb-ft.h:109-110` declares
    /// `hb_ft_font_create (FT_Face ft_face, hb_destroy_func_t destroy)`, and
    /// `src/hb-ft.cc:1375` hands that `destroy` to the `hb_face_t` it builds.
    /// Whoever supplies it owns the closing decision, and upstream's own
    /// `_hb_ft_face_destroy` (`src/hb-ft.cc:127-131`, which calls
    /// `FT_Done_Face`) is static, so it cannot be borrowed from here: pass a
    /// callback of your own, or use `createReferenced`, which needs none.
    ///
    /// `hb_ft_font_create` has no null path (`src/hb-ft.cc:1369-1381`), so this
    /// cannot fail and does not pretend it might. One failure it cannot report
    /// is upstream's: if attaching FreeType's font functions runs out of memory
    /// it returns early (`src/hb-ft.cc:1127`) and leaves a font with the nil
    /// font functions, whose advances are then zero. Upstream gives no signal
    /// for that, and inventing one would mean re-deriving what it does not
    /// expose.
    pub fn create(ft_face: *freetype.c.FT_FaceRec, destroy: c.hb_destroy_func_t) FtFont {
        return .{ .raw = c.hb_ft_font_create(@ptrCast(ft_face), destroy) };
    }

    /// `hb_ft_font_create_referenced`: HarfBuzz takes its own reference to the
    /// `FT_Face` and the caller closes it.
    ///
    /// The whole difference is two lines upstream: `src/hb-ft.cc:1503` calls
    /// `FT_Reference_Face` and `:1504` passes upstream's own
    /// `_hb_ft_face_destroy` (`:127-131`) as the destroy callback. Both public
    /// constructors leave the `unref` field false - `src/hb-ft.cc:1378` is
    /// where that argument is passed - and only `hb_ft_font_set_funcs` sets it
    /// true (`:1858`), which is a different entry point with its own face. So
    /// the boolean is not what separates these two; the reference and the
    /// destroy callback are. Getting ownership wrong is a double free or a
    /// dangling pointer, never a warning, which is why these are two functions
    /// here and not a flag.
    ///
    /// It has no null path either (`src/hb-ft.cc:1500-1505`).
    pub fn createReferenced(ft_face: *freetype.c.FT_FaceRec) FtFont {
        return .{ .raw = c.hb_ft_font_create_referenced(@ptrCast(ft_face)) };
    }

    /// `hb_ft_font_get_ft_face`: the borrowed `FT_Face`, or null.
    ///
    /// `null` after `deinit`, and also for a font that is not FreeType-backed at
    /// all: `src/hb-ft.cc:327` compares the destroy function pointer before it
    /// reaches the face.
    ///
    /// The null is tested on the address rather than carried in the type:
    /// `include/freetype/freetype.h`'s `typedef struct FT_FaceRec_ *FT_Face`
    /// translates to a many-item pointer (`[*c]struct_FT_FaceRec_`), which has
    /// no null in its type, so a caller who wants `null` gets it here.
    pub fn ftFace(self: *const FtFont) ?*freetype.c.FT_FaceRec {
        const font = self.raw orelse return null;
        const face = c.hb_ft_font_get_ft_face(font);
        if (@intFromPtr(face) == 0) return null;
        return @ptrCast(face);
    }

    /// `hb_ft_font_set_load_flags`.
    ///
    /// The default is `FT_LOAD_DEFAULT | FT_LOAD_NO_HINTING`
    /// (`src/hb-ft.cc:119`), which is what makes a FreeType-backed advance equal
    /// to the font's own `hmtx` entry at a matching scale.
    pub fn setLoadFlags(self: *FtFont, flags: c_int) void {
        c.hb_ft_font_set_load_flags(self.handle(), flags);
    }

    /// `hb_ft_font_get_load_flags`, as a reader.
    pub fn loadFlags(self: *const FtFont) c_int {
        return c.hb_ft_font_get_load_flags(self.handle());
    }

    /// `hb_font_destroy`, through the same C function every `Font` uses, so one
    /// provider closes what it opened whichever form created it.
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

    /// `hb_font_set_scale`, on the FreeType-backed font.
    ///
    /// This is the call that decides what a position means, and for a
    /// FreeType-backed font it does more than rescale: `src/hb-ft.cc:177-184`
    /// passes these numbers to `FT_Set_Char_Size` - and again at `:191-193`
    /// for a bitmap font - so they also choose the ppem FreeType rasterizes and
    /// hints at.
    pub fn setScale(self: *FtFont, x_scale: c_int, y_scale: c_int) void {
        c.hb_font_set_scale(self.handle(), x_scale, y_scale);
    }
};