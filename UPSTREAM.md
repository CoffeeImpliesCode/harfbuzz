# UPSTREAM.md — HarfBuzz 14.5.1, as vendored by this SDK

Every claim in this file is read out of a file in this repository or attributed
to the source it came from. Where something could not be established, this file
says so instead of guessing. `SOURCE-CONFIRMED` means read out of a file;
nothing here has been executed, because the driver owns every gate.

## The release

| | |
|---|---|
| Project | HarfBuzz, the OpenType text shaping engine |
| Version | 14.5.1 |
| Version source | `src/hb-version.h:44` (`HB_VERSION_MAJOR 14`), `:50` (`HB_VERSION_MINOR 5`), `:56` (`HB_VERSION_MICRO 1`), `:63` (`HB_VERSION_STRING "14.5.1"`) |
| Release tarball | `https://github.com/harfbuzz/harfbuzz/releases/download/14.5.1/harfbuzz-14.5.1.tar.xz` |
| Tarball size | 20259340 bytes |
| Tarball SHA-256 | `7e2fa4e8c7c98e8d8140671f5772542afaaa6acccfbd746506886b6d85f7f8d6` |
| Upstream licence | the so-called "Old MIT" licence, `COPYING:1` |
| Vendored files | 932, 10691663 bytes — see `UPSTREAM.sha256` |
| Fork additions | `build.zig`, `build.zig.zon`, `zig/`, `runtime/`, `consumer/`, `tools/`, `tests.zig`, `smoke.zig`, `cross-test.profile.sh` and the records — no digest in `UPSTREAM.sha256`, by design |

### Where the tarball digest came from, precisely

Read out of the GitHub REST API on **2026-10-05**, from
`https://api.github.com/repos/harfbuzz/harfbuzz/releases/tags/14.5.1`: the first
asset is named `harfbuzz-14.5.1.tar.xz`, its `size` field is `20259340` and its
`digest` field is `sha256:7e2fa4e8c7c98e8d8140671f5772542afaaa6acccfbd746506886b6d85f7f8d6`.
The release was published `2026-09-30T23:41:49Z` and that asset was uploaded
`2026-10-01T00:13:03Z`.

It was **not** read out of this tree. Nothing in this repository recorded it:
the landing slice wrote the version pin and the build graph, and no file carried
the tarball digest. Rather than invent one, this record attributes it to the API
read above and names the date. Before this package's provenance claim is treated
as settled, the driver should re-fetch the release and check the bytes against
the digest; the 932 per-file digests do not depend on it, because they are taken
from the extracted tree that is here.

The release notes for 14.5.1 list a fix for a possible deadlock in
`hb_font_destroy()` after `hb_ft_font_set_funcs()`. `consumer/src/main.zig` takes
exactly that path and destroys the font afterwards, which is why the shared
lifetime of an `FT_Face` across `hb_ft_font_set_funcs` is documented there rather
than glossed over.

## What is compiled, and what that means for the vendored set

One translation unit: `src/harfbuzz.cc`, HarfBuzz's own amalgamation. It opens
69 `#include` lines (`src/harfbuzz.cc:1-69`) covering every `.cc` in the library,
including the platform shims (`hb-coretext-shape.cc`, `hb-directwrite.cc`,
`hb-gdi.cc`, `hb-glib.cc`, `hb-graphite2.cc`) and the FreeType integration
(`hb-ft.cc`, at `src/harfbuzz.cc:20`). No meson, no CMake, no autotools script is
executed and nothing is downloaded at build time.

What is *not* compiled, and why it is upstream's choice rather than this fork's:
`src/harfbuzz-subset.cc` and `src/harfbuzz-world.cc` are separate libraries with
their own installed headers and their own `pkg-config` templates
(`src/harfbuzz-subset.pc.in`), and `util/` is a set of command-line programs
rather than a library. This SDK is the buffer / shape / font library.

## What was vendored

* `src/` in full — 575 files: the library, the amalgamation, the `OT/` table
  readers and shapers, the ragel sources behind the Indic and Khmer shapers, the
  Unicode data tables, and upstream's own `check-*.py` scripts.
* `docs/` in full — 33 files, the manual sources and the gtk-doc sections file.
* `test/` — 310 files: `test/COPYING` (the SIL Open Font License for the corpus),
  `test/shape/`'s runner scripts, and `test/shape/data/in-house/` with its 215
  in-house fonts and its 86 `.tests` expectation files.
* The 14 top-level files that describe the release: `.clang-format`,
  `.editorconfig`, `AUTHORS`, `AVAR2-INSTANCING.md`, `BUILD.md`,
  `CODE_OF_AI_CONDUCT.md`, `CONFIG.md`, `COPYING`, `NEWS`,
  `README.upstream.md`, `RELEASING.md`, `SECURITY.md`, `TESTING.md`, `THANKS`.

`README.upstream.md` is upstream's own README, byte for byte, preserved under the
name this fork gives it so that `README.md` can be the fork's front page: that is
why its digest is recorded under `README.upstream.md` in `UPSTREAM.sha256`, and
`tools/check-provenance.sh` fails if those bytes change or if the manifest records
them under the fork's name. This fork's own documents are `README.md` (front
page), `README.zig.md` (the Zig-facing long form) and the records below.

The corpus under `test/shape/data/in-house/` is the reason the package has an
independent oracle at all: `*.tests` files record, per case, the font, the
options, the codepoints and the resulting glyphs with their clusters and
advances. `tests.zig` compares against transcribed lines of
`harfbust.tests` and `digits.tests` and against nothing of this fork's own
invention.

## What was not vendored, and the status of that claim

`build.zig.zon`'s own comment names what was left out: `util/` (command-line
programs, not a library), `perf/` (benchmarks), `test/subset/`, `test/fuzzing/`,
`test/api/`, `test/vector/` and the two third-party corpus directories under
`test/shape/data/`. That list is this repository's record, not an independent
verification of the tarball's contents: **no one has compared this tree against
an extracted 14.5.1 tarball**, so "the vendored set is the upstream set minus
those directories" is `SOURCE-CONFIRMED` as a statement about
`build.zig.zon` and unverified as a statement about the release. What *is*
verified is that the 932 files here are exactly the files `UPSTREAM.sha256`
records, and that their digests are the digests of the bytes now in this tree.

Three gaps between what the landed records cited and what the tree contained
were found while writing this record. A correction pass has since repaired all
three in the files that own them; they are kept here because a provenance record
that quietly forgets what it once claimed is not a record:

1. **`README.mingw.md` was named in `build.zig.zon`'s `.paths` and is not
   vendored.** Upstream's `README.upstream.md:114` points at it ("For
   cross-compiling to Windows from Linux or macOS, see README.mingw.md"), so it
   exists in the release. A `.paths` entry naming a missing file is a failure for
   the package hashing step a *dependency* performs. The entry has been dropped
   and `build.zig.zon` records why; the file is still not vendored, so this is a
   resolved defect and an unchanged tree.
2. **The top-level `meson.build` is not vendored**, which left five `build.zig`
   citations unverifiable here — the version, `cpp_std`, the SOVERSION lines the
   delivered SONAME rests on, the C++14 bump and the two no-exception/no-RTTI
   flags. All five now read `src/meson.build:<line>`, which is in this tree and
   does carry those facts, so each is checkable without the file that is absent.
3. **There is no `src/hb-malloc.cc`.** `build.zig` and `runtime/library.zig` both
   cited it for the fact that HarfBuzz allocates through the C library. The
   definition is in a header in this release: `src/hb.hh:555` is
   `#define hb_malloc_impl malloc`, with `:556`, `:557` and `:558` the calloc,
   realloc and free forms. The claim was true; the citation named a file this
   release does not have, and `runtime/library.zig` now says so and points at the
   header.

`README.python.md` is named by upstream's `README.upstream.md:113` and is not
vendored either, and `build.zig.zon` says so where it names the omission. The two
omissions together are the reason this tree has 14 top-level files rather than
16: nothing in the compiled closure, the provenance records or the test oracle
reads either of them.

## Citation drift inside the landed files

Same origin — the landing slice's own line references — recorded here so a later
wave does not have to re-derive them. All were checked against the files in this
tree on 2026-10-05, and the correction pass has since rewritten every row below
to the actual line. The table is kept as the record of what the citations were:
a provenance document that lists only today's correct claims cannot show a
reviewer what to check next time.

| Cited as | Actual | Files |
|---|---|---|
| `src/harfbuzz.cc:32` includes `hb-ft.cc` | `src/harfbuzz.cc:20` | `build.zig:9`, `build.zig.zon:25-26` |
| `src/hb-version.h:44-52` holds the three version macros | `:44`, `:50`, `:56` — `HB_VERSION_MICRO` is on line 56, outside that range | `build.zig:149`, `build.zig.zon:8-12`, `zig/root.zig:109` |
| `src/hb-ft.cc:126` is the default load flags | `src/hb-ft.cc:119` | `zig/root.zig:548` |
| `src/hb-malloc.cc` is the allocator | `src/hb.hh:555-558` | `build.zig`'s sibling note, `runtime/library.zig:53` |

Citations that were checked and are correct: `src/hb.hh:448` (`HAVE_ATEXIT`),
`src/hb-mutex.hh:50-57` (the pthread mutex branch), `src/hb-blob.cc:31-37` (the
`HAVE_SYS_MMAN_H` / `HAVE_UNISTD_H` includes), `src/hb-blob.cc:417`
(`HAVE_SYS_MMAN_H` and `HAVE_MPROTECT`), `src/hb-ft.cc:30` (`HAVE_FREETYPE`),
`src/hb-ft.cc:186` (`HAVE_FT_GET_TRANSFORM`), `src/hb-buffer-serialize.cc:273`
and `:520` (the text serializer), `src/hb-ot-font.cc:1025`
(`hb_ot_font_set_funcs`).

## The sibling FreeType, and why it is a hard dependency

`src/harfbuzz.cc:20` includes `hb-ft.cc` unconditionally. That file needs
FreeType's headers and FreeType's code, so this package compiles against the
sibling `../freetype` **source tree** and links that package's own archive.
`build.zig` puts `<path>/include` on the compile line and defines
`HAVE_FREETYPE` and `HAVE_FT_GET_TRANSFORM`; `zig/translate.h` includes
`<hb-ft.h>`, which includes `<ft2build.h>`, so the translation closure is
FreeType's closure too.

The decision is a relative path dependency (`build.zig.zon`, `.freetype =
.{ .path = "../freetype" }`), overridable with `-Dfreetype=<path>`, and
`-Dfreetype=none` is refused at configure time rather than half supported.
Nothing here is fetched from a registry and no system FreeType is ever linked.

FreeType's own provenance, licence and records live in the sibling package. This
file does not restate them, and this package's `NOTICE.md` records only what
HarfBuzz's tree contains.

## System-library mode

`-fsys=harfbuzz` / `-Dsystem=true` links an installed `libharfbuzz` instead of
compiling `src/`. The rule is the workspace's: a system mode translates the
headers it actually links. `build.zig` therefore runs `addTranslateC` over the
*selected system's* `hb.h` / `hb-ft.h` in that mode and over this tree's
headers otherwise, so a bundled new-release header is never paired with an older
installed library. No installed HarfBuzz has been exercised on this host, so the
mode is declared and **NOT RUN**, never satisfied.

## Verifying this record

```sh
sha256sum -c UPSTREAM.sha256        # the 932 vendored files
tools/check-provenance.sh           # the same, plus the file set and the licences
```

Neither command compiles anything. The behavioural gates are `zig build test`,
`zig build smoke`, `zig build check` and `zig build consumer`, all owned by the
driver; see `README.zig.md` and `CHANGELOG.md` for what has and has not been run.