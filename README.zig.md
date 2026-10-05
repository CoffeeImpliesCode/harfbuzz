# HarfBuzz 14.5.1 for Zig 0.16 — `README.zig.md`

This is this fork's Zig-facing document. `README.md` is the fork's front page and
this is the long form behind it; upstream's own README is preserved separately as
`README.upstream.md`, byte for byte, so a reader can compare the two without
diffing a rewritten upstream text. Every file below that names a line number names
it in one of those two, never in the fork's prose.

Every claim below is read out of a file in this repository unless it is marked
otherwise. **Nothing in this document has been executed by its author.** The
driver owns every gate; see [Support matrix](#support-matrix) for exactly what
has and has not run.

Order of this document is the workspace's: native-source deviations, then
native-build deviations, then the support matrix, then consumption.

## The import route

One published module, `dep.module("harfbuzz")`, whose source is `zig/root.zig`.
There is no second route and no second root file, so a dependent gets one
`hb_buffer_t` type whichever surface it uses.

```zig
const std = @import("std");
const hb = @import("harfbuzz");

var blob = try hb.Blob.fromBytes(font_bytes);      // HB_MEMORY_MODE_READONLY
defer blob.deinit();
var face = try hb.Face.create(&blob);
defer face.deinit();
var font = try hb.Font.create(&face);             // HarfBuzz's own OT font funcs
defer font.deinit();

var buffer = try hb.Buffer.create();
defer buffer.deinit();
try buffer.addUtf8("HarfBuZZ");
buffer.guessSegmentProperties();
buffer.setDirection(hb.direction_ltr);
try hb.shape(&font, &buffer, &.{});

const line = try buffer.serializeText(&font, allocator);
defer allocator.free(line);
// "[H=0+1022|a=1+990|r=2+710|f=3+574|B=4+980|u=5+1022|z=6+790|z=7+790]"
```

## Current native-source deviations

**There are none.** The 932 files in `UPSTREAM.sha256` — all of `src/`, all of
`docs/`, `test/` and the 14 top-level files that describe the release — are
upstream's bytes, unmodified. No upstream file was reformatted, patched or
deleted. `tools/check-provenance.sh` fails if a digest changes, if a file
appears under a vendored tree without one, or if the count of `COPYING` files
changes.

Three gaps between what the landed build files *cite* and what the tree
*contains* were found while writing these records, and a correction pass has
since repaired all three. They are kept because "was this ever wrong?" deserves
an answer:

1. `build.zig.zon`'s `.paths` named `README.mingw.md`, which is not vendored —
   and a missing `.paths` entry is a failure for the package hashing step a
   *dependency* performs, so it would have hit the consumer before anything
   compiled. The entry is gone and `build.zig.zon` says why.
2. The top-level `meson.build` is not vendored, so five citations in `build.zig`
   were unverifiable here, including the SOVERSION lines the delivered SONAME
   rests on. Every one now reads `src/meson.build:<line>`, which is in the tree.
3. There is no `src/hb-malloc.cc`; the allocator is `src/hb.hh:555`
   (`#define hb_malloc_impl malloc`). The claim was true and the citation was to
   a file this release does not have; `runtime/library.zig` now says both things.

`cross-test.profile.sh` also carried a Lua SDK's prose in its comments. Its four
settings were generic, so harness behaviour was never affected; the prose has
been rewritten. `CHANGELOG.md` entries 3 and 4 record that pass.

### Resolved blocker, and what it opened

This section used to say the facade could not compile. It no longer does, and the
repair is worth keeping because it reached three files:

`Font.create` called `hb_font_create_or_fail`, which 14.5.1 declares in no header
— the name appeared only in that one line — and the entry point that call stood
in for, `hb_ot_font_set_funcs`, was declared in a header the translation did not
reach. It now calls `hb_font_create` and attaches the OpenType functions itself
(`zig/root.zig:338-343`), `zig/translate.h:60` includes `<hb-ot.h>`, upstream's
own umbrella, so the single-header guard at `src/hb-ot-font.h:27-28` is satisfied
the way upstream intends rather than worked around with a macro — and the
allocation failure now has a signal: `hb_font_create` answers the *empty font
object* rather than null (`src/hb-font.cc:2110-2111`), so the wrapper compares
against `hb_font_get_empty()` (`src/hb-font.h:1123`), which is a real answer
instead of a check that could never fire.

The umbrella reaches eleven more headers (`src/hb-ot.h:33-43` — fetch, color,
deprecated, font, layout, math, meta, metrics, name, shape, var), so they are
translated, and under `-Druntime=true` their entry points are symbols a provider
must export. `build.zig`'s `public_headers` grew to match: 29 entries, the three
umbrellas' whole closure, with `build.zig:177-186` naming the two include lists
behind it (`src/hb.h:31-45` and `src/hb-ot.h:33-43`). That is what keeps the
installed closure and the translated closure the same set — a translated
declaration whose header is not installed is the silent mismatch this
workspace's rules are about.

One thing the repair left behind, in a file this role does not own:
`zig/translate.h:22-28` still says "the two headers above are the closure of that
surface" and heads a section called "Why nothing else is listed", which its own
line 60 now contradicts. It is prose, not a build input, so nothing fails; it is
recorded in `FORK-NOTES.md` for whoever owns that file.

## Native-build deviations, and why

**One translation unit.** `src/harfbuzz.cc` is HarfBuzz's own amalgamation and
the only compiled source: 69 `#include` lines covering the library, its platform
shims and `hb-ft.cc`. No meson, no CMake, no autotools, no build-time download,
no generated `config.h`.

**C++14 with no exceptions and no RTTI.** `-std=c++14 -fno-exceptions
-fno-rtti`. The dialect is c++14 rather than c++11 because `meson.build:40-46`
bumps it for exactly the toolchains whose standard library needs it; the two
flags are upstream's own, cited in `build.zig`'s module doc.

**The compile line carries the configuration, not a generated header.**
`HAVE_CONFIG_H` is never defined, so there is no `config.h` to regenerate per
target and nothing whose content could disagree with the target being built. The
facts that header would carry are resolved from the resolved target:
`HAVE_PTHREAD`, `HAVE_ATEXIT`, and the `HAVE_SYS_MMAN_H` / `HAVE_UNISTD_H` /
`HAVE_MMAP` / `HAVE_MPROTECT` family where the target's libc has those headers.
Every other `HAVE_*` — glib, icu, graphite2, cairo, coretext, directwrite,
uniscribe, gdi, wasm, png, zlib — is left undefined, which is upstream's
"all optional dependencies off" configuration.

**The sibling FreeType is a hard, declared dependency.** `src/harfbuzz.cc:20`
includes `hb-ft.cc` unconditionally, so this package compiles against the
sibling `../freetype` *source tree* and links that package's archive. It is a
relative path dependency (`build.zig.zon`), selected with `-Dfreetype=<path>` and
defaulting to `../freetype`. There is no search path, no registry fetch and no
system FreeType. `-Dfreetype=none` is **refused at configure time**, with the
reason printed: a facade that names `hb_ft_font_create` in a build that does not
contain it is a stub, and a second root file that exists only in the
no-FreeType configuration would make `dep.module("harfbuzz")` resolve to
different source depending on a build option.

**What is not compiled.** `src/harfbuzz-subset.cc` and
`src/harfbuzz-world.cc` are separate upstream libraries with their own headers
and `pkg-config` templates, and `util/` is command-line programs. This SDK is the
buffer / shape / font library. A consumer that wants the subset API writes its
own aggregate header and points a translation step at it.

**The SONAME.** Upstream's own, read out of `src/meson.build:650-652`, which sets
`hb_so_version` to `'0'` off the Microsoft-compiler path, and `:673`, which hands
it to the library as `soversion`: `libharfbuzz.so.0`. Zig derives a SONAME from
`version.major`, so `major` is 0 here for exactly that reason. The number `61451`
— `60000 + major*100 + minor*10 + micro` for 14.5.1 — is carried in `minor` and
`patch`, where it reaches the *file name* and not the SONAME, so the delivered
object is `libharfbuzz.so.0.61451.61451`.

**What is installed.** The archive or shared object, the 29 public headers this
library installs — the whole closure of the three umbrellas `zig/translate.h`
reaches, `<hb.h>` (`src/hb.h:31-45`), `<hb-ft.h>` and `<hb-ot.h>`
(`src/hb-ot.h:33-43`), which is the same set, so the installed closure and the
translated closure cannot drift — a relocatable `harfbuzz.pc`, and
`share/licenses/harfbuzz/` carrying `COPYING`, `test/COPYING` and every record
this fork writes.

**No required sibling import for a consumer.** A dependent that only shapes from
a font blob never touches `hb-ft.h`. The consumer package proves it: it depends
on this package alone and reaches FreeType through the `hb_ft_*` entry points
this package's translated header already declares.

## Support matrix

| Configuration | Command | Status |
|---|---|---|
| Static archive | `zig build` | **exit 0** on 2026-10-05 |
| Shared object, real SONAME | `zig build -Dlinkage=dynamic` | `PENDING-VERIFICATION` |
| Behavioural tests, Debug | `zig build test` | `PENDING-VERIFICATION` |
| Behavioural tests, ReleaseSafe | `zig build test -Doptimize=ReleaseSafe` | `PENDING-VERIFICATION` |
| Example program | `zig build smoke` | `PENDING-VERIFICATION` |
| Six-target compile check | `zig build check` | **exit 1** on 2026-10-05: five rows compile, `wasm32-wasi` fails |
| Consumer package | `zig build consumer`, `zig build run` in `consumer/` | `PENDING-VERIFICATION` |
| Runtime-loaded route | `zig build -Druntime=true test` with `HARFBUZZ_TEST_PROVIDER` | `PENDING-VERIFICATION`, not run |
| System-library mode | `zig build -fsys=harfbuzz` | declared, **NOT RUN** — no installed HarfBuzz has been exercised |
| 53-platform matrix | `cross-test` from the package root | **NOT RUN** |

The six check targets are `x86_64-linux-gnu`, `aarch64-linux-gnu`,
`aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` and
`wasm32-wasi`, and none is refused: `refused_check_targets` in `build.zig` is
empty and `checkMatrixPartition` stops the two lists from disagreeing. That the
WASI cell compiles was a reasoned expectation; on 2026-10-05 it was observed to
be false. All three of its steps stop in the pinned toolchain's wasi-libc,
`libc/include/wasm-wasi-musl/setjmp.h:13`, reached through FreeType's
`include/freetype/config/ftstdlib.h:166`, so `zig build check` exits 1 and the
cell stays visible rather than being dropped. See
[`FORK-NOTES.md`](FORK-NOTES.md). The other five rows compile, and
`riscv64-linux-gnu` needed one `-D` on the translation to agree with what the
C++ compiler already predefines.

`cross-test` builds and *runs* `tests.zig` across the published 53-platform
matrix using `cross-test.profile.sh`. A platform with no executor on the host
is recorded as `build_only` — compiled, never executed, never a pass.

## Consumption

### Positions, and the unit they are in

`hb_font_set_scale` decides what one position unit means, and the default is the
face's own `unitsPerEm`. With no call at all, HarfBuzz reports font design units,
which is what the recorded shaping lines contain. A caller that wants 26.6 pixels
sets `upem * 64`; every position then multiplies by exactly 64, because the
factor is `x_scale / upem`. Nothing in the C API records which was chosen, so
`Font.scale` is exposed as a reader and every measurement helper documents its
unit.

### Features

`shape` takes `[]const hb.c.hb_feature_t` and deliberately does not hide them. A
shaping test that cannot set a feature cannot prove that a substitution
happened, which is most of what shaping is. Passing an empty slice is exactly
`hb_shape(font, buffer, NULL, 0)`.

### Memory

HarfBuzz allocates through the C library (`src/hb.hh:555`), so a Zig allocator can
neither bound nor intercept one byte of it and this package claims no leak
oracle; the tests prove behaviour and never absence of leaks. What it does make
explicit is every ownership transition: `Blob`, `Face`, `Font`, `Buffer` and
`FtFont` each own exactly one C object, each `deinit` clears its handle so a
second close is a no-op, and `FtFont` documents that it closes the `FT_Face` it
was given unless it was created in the referenced form.

### Threading

HarfBuzz is thread-safe. HarfBuzz-over-FreeType is **not**:
`src/hb-ft.cc`'s own module documentation says FreeType is not thread-safe and
therefore these functions are not either. A process that shapes from several
threads must not put one `hb_ft_font_t` in more than one of them.

### Errors

| Tag | Meaning |
|---|---|
| `ShapingFailed` | `hb_shape` answered `false`: the buffer still holds the original codepoints. HarfBuzz does not say why, and one honest tag is better than a taxonomy this package cannot justify. |
| `OutOfMemory` | HarfBuzz reported that its *own* allocator failed, through `hb_buffer_allocation_successful` (`src/hb-buffer.cc:1539-1542`) — the signal upstream documents for that case and no other. |
| `FileNotLoaded` | `hb_blob_create_from_file_or_fail` answered null. Upstream answers null for a path it could not open, for an `fstat`, `mmap` or read failure, for its own ~536 MB ceiling and for a failed allocation alike, so this tag reports the null rather than a cause. |
| `NoFace` | `hb_face_create_or_fail` answered null: the blob holds no face at index 0 (`src/hb-face.cc:293-294`), or the face object could not be allocated. |
| `InvalidArgument` | a length that does not fit the C type, or a buffer too small to hold the answer |

The first three were one tag in the first cut of this package, and splitting them
is the honest answer rather than the tidy one: a null from those constructors
means several different things, and `OutOfMemory` is only true of one of them.
The taxonomy is cut where the code stopped — a null is reported, and the causes it
does not check are named rather than guessed.

### The FreeType-backed font

`FtFont.create(ft_face, destroy)` takes the closing decision from the caller:
`src/hb-ft.h:109-110` declares two arguments and `src/hb-ft.cc:1375` hands that
`destroy` to the `hb_face_t` it builds, so whoever supplies it decides who closes
the face. `FtFont.createReferenced(ft_face)` needs no callback — HarfBuzz takes
its own reference (`src/hb-ft.cc:1503`) and closes that one with its own static
destroy (`:1504`). Two functions rather than a flag because getting it wrong is a
double free or a dangling pointer and never a warning. Neither returns an error:
neither C entry point has a null path.

Both take `*freetype.c.FT_FaceRec`, and the facade publishes the sibling's module
as `hb.freetype`, so one dependency is enough: `hb.freetype.c.FT_New_Memory_Face`
opens a face and hands the same type straight to `FtFont.create`. Reaching for
this package's own `hb.c` instead would *not* do — translate-c types are nominal
per module, so the same struct reached through two modules is two unrelated Zig
types.

A dependent that only wants FreeType's metrics for a font it already has needs
none of that: `hb_ft_font_set_funcs` on an existing font attaches them, and
`consumer/src/main.zig` takes that route, reading the `FT_Face` back and shaping
again.

Both fonts are shaped the same way: `hb.shape` and `Buffer.serializeText` take
either one, and the check is on the pointee rather than on the pointer's
constness (`zig/root.zig:551-561`). `&font` on a `var` is the ordinary line and it
works; `deinit` takes the mutable form, so a caller that owns its font owns a
`var`, and mutability is deliberately not part of what this facade asks for.

**A shared `FT_Face` across `hb_ft_font_set_funcs` has its own rule**, and the
14.5.1 release notes name it: that release fixes a possible deadlock in
`hb_font_destroy()` after `hb_ft_font_set_funcs`. The consumer takes that path on
purpose and destroys the font afterwards. Whether a face that was *already*
borrowed by another font may be reused is a separate question this package does
not answer; the consumer creates its own library and face and keeps them out of
`hb_ft_font_set_funcs`' reach.

### The external ABI boundary

A provider for `-Druntime=true` must export every `hb_*` the translated header
declares: this configuration has no optional entry points, so a partial provider
is refused rather than half used. After the symbols resolve, the loader checks
two things and reports rather than aborts: that `hb_version` answers 14.5.1, and
that `hb_buffer_create` returns an object — the cheapest HarfBuzz object that
crosses the allocator boundary. It deliberately does **not** check shaping: that
would need a font, and a loader guessing at one would be testing the font rather
than the provider.

A HarfBuzz built without FreeType is a conforming provider for everything except
`hb-ft.h`, so the FreeType declarations `hb-ft.h` reaches are classified as noise
rather than as owed symbols. A provider's C++ ABI is part of its interface — the
same standard library, the same `-fno-exceptions` / `-fno-rtti` — so the version
check is a necessary condition and not a sufficient one.

Runtime loading, when used: one process-lifetime table per configured module,
explicit `.path` or `.system` selection, no fallback and no default location,
atomic publication, explicit retry after a failed load, and an ordinary
pre-initialization panic in every optimization mode. Linked calls stay direct.

### Options

| Option | Effect |
|---|---|
| `-Dlinkage=static` | the default: `libharfbuzz.a` |
| `-Dlinkage=dynamic` | a real shared object; refused on a target with no dynamic linker, with the target named |
| `-Dfreetype=<path>` | the FreeType source tree; `none` is refused with its reason |
| `-Druntime=true` | resolve every entry point through the platform loader |
| `-Dsystem=true` / `-fsys=harfbuzz` | link an installed library and translate *its* headers |
| `-Dtarget=<triple>` | build for one target |
| `-Doptimize=<mode>` | passed to every graph below |

Steps: `zig build` (default, installs), `zig build test`, `zig build smoke`,
`zig build check`, `zig build consumer`.

### C consumers

The install carries `lib/pkgconfig/harfbuzz.pc`, with `prefix` relative to
`pcfiledir` so the file is correct wherever `--prefix` put it. `Cflags` is the
installed include directory; `Libs.private` is `-lm`. That is the whole
interface a C build needs, and nothing about it depends on Zig.

### Nix and the development shell

`package.nix` builds nothing but this repository: one `zig build install` with
the caches under `$TMPDIR`, an rpath pass over the ELF files Zig installed, and
no C or C++ flag restated anywhere. `flake.nix` exposes it for the Unix systems
`package.nix` supports; it refuses a cross build rather than producing a
host-architecture library under a foreign name. `devenv.nix` is the canonical
shell and sets `LC_ALL=C`, which the recorded shaping lines depend on.

### Continuous integration

`.github/workflows/verify.yml` gates four things: the native build and its two
optimize modes, the six-target compile matrix with one step per target and no
tolerated failure, the consumer package, and the provenance script — which
installs no Zig at all, on purpose.

One precondition is asserted rather than assumed: **every job that builds this
package needs the sibling FreeType checkout beside it**, because
`build.zig.zon` resolves it as a relative path and the upstream release is not
published anywhere this workflow could fetch it from. The workflow checks for
the sibling and fails with that reason rather than pretending a package built
without it.

## What the driver still owes

Recorded in `CHANGELOG.md` and `FORK-NOTES.md`; repeated here so the front page
does not imply more than has been observed. Every row above marked
`PENDING-VERIFICATION` is a landing edit with no gate behind it yet.

The behavioural proof the tests carry is upstream's, not this fork's: lines 1, 2
and 4 of `test/shape/data/in-house/tests/harfbust.tests` and lines 1 and 5 of
`test/shape/data/in-house/tests/digits.tests`, transcribed with the file and line
they came from. Line 6 of `harfbust.tests` is deliberately unused — it is
qualified `@shapers=harfrust,uniscribe,directwrite`, and this build has no such
shaper, so a recorded answer for a shaper that is not compiled is not an
expectation this package can hold itself to.