/* SPDX-License-Identifier: MIT
 * See FORK-LICENSE.md for what that identifier covers.
 *
 * The one header this package translates. `zig build` runs translate-c over
 * this file.
 *
 * ## Which headers those are
 *
 *   - `<hb.h>` is HarfBuzz's own umbrella header and the documented single
 *     include for a client. `src/hb.h:31-45` is its include list: `hb-blob.h`,
 *     `hb-buffer.h`, `hb-common.h`, `hb-deprecated.h`, `hb-draw.h`,
 *     `hb-face.h`, `hb-font.h`, `hb-map.h`, `hb-paint.h`, `hb-set.h`,
 *     `hb-shape.h`, `hb-shape-plan.h`, `hb-style.h`, `hb-unicode.h` and
 *     `hb-version.h`. That covers the whole buffer / shape / font surface this
 *     package's facade wraps, and the buffer serializer
 *     (`hb_buffer_serialize_glyphs`) that the tests use.
 *   - `<hb-ft.h>` is the FreeType integration: `src/hb-ft.h:34-35` opens
 *     `<ft2build.h>` and `FT_FREETYPE_H`. That is what makes
 *     `hb_ft_font_create` and `hb_ft_face_create_referenced` reachable, and it
 *     is the whole reason this package has a sibling dependency at all.
 *
 * ## Why nothing else is listed
 *
 * `src/meson.build`'s installed set is much larger - the subset, the raster,
 * the vector and the draw APIs - and each of those is a separate upstream
 * library with its own header. This package is a buffer/shape/font SDK.
 *
 * Three umbrellas are listed above, not two. `<hb-ot.h>` is there because
 * `src/hb-ot-font.h:27-28` refuses a direct include, and `Font.create` needs
 * `hb_ot_font_set_funcs` (`src/hb-ot-font.h:39-40`) to give a font its metrics
 * from the font's own tables; it pulls in eleven more headers
 * (`src/hb-ot.h:33-43`), which is why `public_headers` in `build.zig` carries
 * 30 entries. Those 30 are the closure of the shaping surface this package
 * publishes. A consumer that wants the subset API still writes its own
 * aggregate and points this file at it.
 *
 * ## What is deliberately not here
 *
 * No declaration is copied out of a HarfBuzz header, and this file defines no
 * macro of its own. The compile-line macros - `HAVE_FREETYPE`,
 * `HAVE_PTHREAD`, `HAVE_ATEXIT` and the `HAVE_MMAP` family - describe the
 * target and build configuration. `-Dfreetype=none` is refused.
 *
 * In particular `HAVE_CONFIG_H` is *not* defined. `src/hb-config.hh:34-36`
 * includes a generated `config.h` only under that macro, and this build puts
 * the two facts that file would carry - `HAVE_PTHREAD` and `HAVE_FREETYPE` -
 * directly on the compile line instead. Same information, no generated header,
 * and nothing that has to be regenerated per target.
 *
 * `hb-ft.h` reaches FreeType's headers, so this file's C library include
 * closure is FreeType's closure plus HarfBuzz's own `<stddef.h>` and
 * `<stdint.h>`. `runtime/graph.zig`'s `libc_noise` is written for that union,
 * and it is also why this package's default build puts the sibling FreeType's
 * `include/` directory on the compile line: `hb-ft.h:34` includes
 * `<ft2build.h>` by bare name, and a header included by bare name needs its own
 * directory on the path (see AGENTS.md section 5).
 */

#include <hb.h>
#include <hb-ft.h>
// `hb-ot-font.h` refuses a direct include (`src/hb-ot-font.h:27-28`), so the
// OpenType umbrella is included for it. Without it the facade has no
// `hb_ot_font_set_funcs`, and a `Font` created over a face would carry nil
// font functions instead of metrics.
#include <hb-ot.h>