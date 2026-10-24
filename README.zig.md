# Zig facade API

## Top-level declarations

- `c`: translated HarfBuzz headers and native declarations.
- `freetype`: the FreeType dependency module used by `FtFont` signatures.
- `version`: `std.SemanticVersion` read from the translated HarfBuzz version macros.
- `runtime_loaded`, `LoadSource`, `LoadError`: runtime-loading configuration and types.
- `load(source)`: resolve all HarfBuzz entry points from an explicit provider. It is valid only in a runtime-loaded build; a linked build panics.
- `loadedSource()`: the published provider, or `null`.
- `Direction` and `ClusterLevel`: HarfBuzz's direction and cluster-level types, with their constants re-exported.

## Errors

`Error` contains:

- `ShapingFailed`: `hb_shape` returned false; the buffer retains its input codepoints.
- `OutOfMemory`: HarfBuzz reported failure through an allocation-success signal.
- `FileNotLoaded`: blob creation from a path returned null; the cause may be open, read, size-limit, or allocation failure.
- `NoFace`: face creation at index zero returned null.
- `InvalidArgument`: a length does not fit the C API or an output buffer is too small.

## Owned objects

Each wrapper owns one HarfBuzz object. Call `deinit()` to destroy it; `deinit()` clears the handle. `isOpen()` reports whether the handle remains open. `handle()` panics after `deinit()`.

### `Blob`

- `fromFile(path)`: open a NUL-terminated path; returns `FileNotLoaded` on null.
- `fromBytes(bytes)`: copies the input bytes into a HarfBuzz blob; rejects lengths above `c_uint` with `InvalidArgument`.
- `len()`: byte length.

### `Face`

- `create(blob)`: create face index zero; returns `NoFace` on null.
- `upem()`: units per em from the font's design grid.
- `glyphCount()`: glyph count from `maxp`.
- `glyphName(glyph, buffer)`: name borrowed from the caller's buffer, or `null` when unavailable.

### `Font`

- `create(face)`: create a font and attach HarfBuzz's OpenType font functions; returns `OutOfMemory` if HarfBuzz returns its empty font object.
- `setScale(x, y)` / `scale()`: set or read the position scale. The default is the face's units per em; `upem * 64` selects 26.6 pixel units.
- `setPpem(x, y)`: set pixels per em for rasterization; this does not change metrics.
- `glyphAdvance(glyph)`: horizontal advance in the font's scale units.

### `Buffer`

- `create()`: allocate a buffer; returns `OutOfMemory` when HarfBuzz reports allocation failure.
- `addUtf8(text)`: add the full UTF-8 slice; rejects lengths above `c_int` with `InvalidArgument`.
- `setDirection(dir)`, `direction()`, `setClusterLevel(level)`, `guessSegmentProperties()`: configure or read buffer properties.
- `clear()`: remove contents while preserving settings.
- `len()`: codepoint count before shaping, glyph count after shaping.
- `infos()` / `positions()`: borrowed slices, overwritten by the next shape on this buffer.
- `serializeText(font, allocator)`: return a caller-owned text serialization; free it with the same allocator. Returns `InvalidArgument` if the result cannot fit.

### `FtFont`

- `create(ft_face, destroy)`: wrap a FreeType face and pass `destroy` to HarfBuzz; the caller chooses who closes the face.
- `createReferenced(ft_face)`: HarfBuzz takes its own face reference; the caller still closes its reference.
- `ftFace()`: return the borrowed FreeType face, or `null`.
- `setLoadFlags(flags)` / `loadFlags()`: set or read FreeType load flags.
- `setScale(x, y)`: set scale and the FreeType size used for rasterization.

## Shaping

`shape(font, buffer, features)` accepts a pointer to `Font` or `FtFont` and a slice of `c.hb_feature_t`. It returns `ShapingFailed` if HarfBuzz returns false and `InvalidArgument` if the feature count does not fit `c_uint`.

HarfBuzz owns memory through the C allocator. The allocator passed to `serializeText` owns only the returned byte slice.

HarfBuzz's core is thread-safe. The FreeType-backed API is not; do not share an `FtFont` across threads.
