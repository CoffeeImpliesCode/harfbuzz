# CHANGELOG.md — HarfBuzz Zig package

Numbered. Every entry is a change to *this package*; upstream's own release
history is in `NEWS`, preserved as it was shipped.

**No entry below is a verified result.** Nothing in this package has been
built, tested or run by the author of these entries. Every entry that describes
behaviour is `SOURCE-CONFIRMED` — read out of `src/` or out of this
repository's own files — and the gates named in each entry are
`PENDING-VERIFICATION` until the driver runs them and records the receipt.

---

## 1. Native source and build graph

**Date:** 2026-10-05
**Upstream pin:** HarfBuzz 14.5.1, from the release tarball
`harfbuzz-14.5.1.tar.xz` (20259340 bytes, sha256
`7e2fa4e8c7c98e8d8140671f5772542afaaa6acccfbd746506886b6d85f7f8d6`).

No commit SHA is recorded for this pin, and that is deliberate rather than an
omission waiting to be filled in: this is an archive import, not a clone, so
there is no commit in this repository's history that corresponds to it and none
is invented. The digest's source and read date are in `UPSTREAM.md`.

### Added — native source

- `src/` in full (575 files), `docs/` in full (33), `test/` (310: the shaping
  corpus, its 215 in-house fonts, its 86 `.tests` expectation files and
  upstream's runner scripts), and the 14 top-level files that describe the
  release. 932 files, 10691663 bytes, whole and unmodified; every one
  digest-recorded in `UPSTREAM.sha256`.
- `README.upstream.md` is upstream's own README, byte for byte: its sha256 is
  the digest `UPSTREAM.sha256` records for upstream's `README.md`. This fork's
  front page is `README.md`, its long-form Zig reference is `README.zig.md`, and
  `build.zig.zon` `.paths` names all three once each.

### Added — build graph

- `build.zig` compiling exactly one translation unit, `src/harfbuzz.cc`, as C++
  with `-std=c++14 -fno-exceptions -fno-rtti`. No meson, no CMake, no autotools,
  no build-time download and no generated `config.h`: the configuration reaches
  the compile line as `HAVE_PTHREAD`, `HAVE_ATEXIT` and the `HAVE_*MMAP*` family,
  each resolved from the target being built.
- `build.zig.zon`: `.name = .harfbuzz`, `.version = "14.5.1"` cross-checked
  against `src/hb-version.h:44`, `:50` and `:56` at configure time, and one
  declared dependency — the sibling FreeType, as a relative path.
- Options: `-Dlinkage=static|dynamic`, `-Dfreetype=<path>`, `-Druntime=true`,
  `-Dsystem=true` (also `-fsys=harfbuzz` / `-fno-sys=harfbuzz`), `-Dtarget`,
  `-Doptimize`. Steps: default (install), `test`, `smoke`, `check`, `consumer`.
- The shared object is `libharfbuzz.so.0.61451.61451` with soname
  `libharfbuzz.so.0`. The `0` is read out of `src/meson.build:650-652` and `:673`
  (see entry 4); the other two components are carried from upstream's version
  convention rather than sourced from this tree.
- `-Dfreetype=none` is **refused at configure time**, with the reason printed.
  A facade that names `hb_ft_font_create` in a build that does not contain it is
  a stub, and a second root file that exists only in the no-FreeType
  configuration would make `dep.module("harfbuzz")` resolve to different source
  depending on a build option. Refusing is the third option, and it is the only
  honest one.

### Added — Zig surface

- `zig/translate.h`, which includes `<hb.h>` and `<hb-ft.h>` whole and defines no
  macro of its own, so the translation cannot disagree with the real headers by
  omission.
- `zig/root.zig`: `Blob`, `Face`, `Font`, `Buffer`, `FtFont`, `shape`, the
  direction and cluster-level re-exports, and the `load` / `loadedSource` pair
  for the runtime route.
- `runtime/`: the loader, this SDK's descriptor, the build half, the generator
  and the two C files that supply the synchronization the descriptor binds.

---

## 2. Behavioural tests, consumer, records and packaging

### Added — tests, with an upstream oracle

- `tests.zig` compares shaped output against lines recorded by upstream in
  `test/shape/data/in-house/tests/`: `harfbust.tests` lines 1, 2 and 4, and
  `digits.tests` lines 1 and 5. The corpus travels whole and is digest-covered,
  so the oracle is bytes somebody else wrote rather than a restatement of this
  package's own behaviour.
- `harfbust.tests:6` is deliberately unused: it is qualified
  `@shapers=harfrust,uniscribe,directwrite`, and this build has no such shaper.
  A recorded answer for a shaper that is not compiled is not an expectation this
  package can hold itself to.
- A tiny TrueType table reader in `tests.zig` checks the fixture's `head` and
  `maxp` independently of HarfBuzz, so the design grid and glyph count are read
  twice over the same bytes by two implementations that share no code.
- The recorded lines are reproduced the way upstream's runner produces them:
  `add_utf8`, `guess_segment_properties`, then the direction the line names —
  `test/shape/run-tests.py:19` sets `LC_ALL=C` for this, and
  `hb_language_get_default()` reads the locale, so the tests and the workflow
  both set it.
- The suite covers shaping advance (codepoints to glyphs, clusters, per-glyph
  codepoints, total advance), the scale boundary (font units to 26.6 is exactly
  x64, and the glyphs do not change), direction, buffer clearing and setting
  retention, the read-only blob ownership transition, the close transition, both
  constructor error paths and the runtime provider.
- No leak check, and the reason is in the file: HarfBuzz allocates through the
  C library, so the test framework has no oracle for it.

### Added — example program

- `smoke.zig`: shapes three strings out of two of upstream's own fonts, prints
  every answer, and compares against the recorded lines with the file and line
  each came from. It also walks both error paths, because an example that cannot
  fail is not evidence.

### Added — consumer package

- `consumer/` is a separate package that depends on this one by relative path
  and needs nothing else. Its program proves the buffer/shape/font surface works
  from outside, and it proves the **sibling FreeType is really linked and
  running**: `hb_ft_font_set_funcs` attaches FreeType font functions to an
  existing font, the returned `FT_Face` is read back *through* FreeType, and the
  font is then shaped again and must produce the identical line — the metrics
  having moved from HarfBuzz's own `hmtx` reader to FreeType's scaler.
- Options are forwarded rather than ignored, so `-Dlinkage=dynamic` and
  `-Druntime=true` cannot silently go unchecked.
- `-Druntime=true` with no provider is a hard error naming both spellings
  (`--provider`, `--provider-system`, `HARFBUZZ_PROVIDER`,
  `HARFBUZZ_PROVIDER_SYSTEM`). There is no default location and no fallback.
- The fixtures are read from the library tree at run time rather than embedded,
  because `consumer/` is its own package and `@embedFile` cannot name a path
  outside it. `HARFBUZZ_FIXTURE_DIR` overrides the location.

### Added — records

- `UPSTREAM.md`: the release, the digest with the API read it came from and the
  date, what is vendored, what is not, the three gaps between what the build
  files cite and what the tree contains, and the citation drift table.
- `UPSTREAM.sha256`: 932 records, generated from the bytes in this tree.
- `tools/check-provenance.sh`: digests, the exact vendored file set, an
  upstream-only manifest check, agreement between the two release-digest
  records, all three `COPYING` files, and coverage of the four oracle fixtures.
  No compiler needed, which is the point.
- `NOTICE.md`: the per-file inventory. Three licences, not one — Old MIT for the
  compiled core, MIT with Microsoft's holder for `src/ms-use/`, SIL OFL-1.1 for
  the shaping corpus under `test/`.
- `FORK-LICENSE.md`: the grant for the fork's own files, under MIT, with the
  owner's authorisation recorded and no upstream author attributed to any of it.
- `README.zig.md`: this fork's front page, in the required order — native-source
  deviations, native-build deviations, support matrix, consumption.
- `FORK-NOTES.md`: the worker's open questions.

### Added — packaging and CI

- `package.nix` builds nothing but this repository: one `zig build install` with
  both Zig caches under `$TMPDIR`, an rpath pass over the installed ELF files,
  and no C or C++ flag restated anywhere. It refuses a cross build rather than
  producing a host-architecture library under a foreign name.
- `flake.nix` exposes it as `static`, `shared` and `default`, and its dev shell
  is parity only: entering a shell must not build a library.
- `devenv.nix` is the canonical shell, and sets `LC_ALL=C` for the reason above.
- `.github/workflows/verify.yml` gates the native build and both optimize modes,
  the six-target compile matrix with one step per target and no tolerated
  failure, the consumer package, and the provenance script. It is entirely this
  fork's: upstream ships CI of its own and this file does not retarget another
  maintainer's infrastructure.
- Every CI job asserts the sibling FreeType precondition explicitly rather than
  assuming it, because a relative path dependency cannot be fetched by a runner
  that has no checkout for it.

---

## 3. Known gaps in this package, recorded rather than papered over

- **The release digest is not read out of this tree.** It was read from the
  GitHub REST API on 2026-10-05 and attributed to that read. See `UPSTREAM.md`.
- **`hb_font_create_or_fail` was repaired after this pass reported it.** The
  blocker in section 4 is closed, and the two consequences it opened were closed
  in the same pass. Who made the repair is not established by anything in this
  tree, and no gate has observed any of it.
- **Most gates are still unrun, and two are not.** As of entry 5
  (2026-10-05) `zig build` has exited 0 and `zig build check` has exited 1 with
  five of six targets compiling; every row of the support matrix in
  `README.zig.md` that names a test, a smoke run, a consumer run or the
  runtime-loaded route is still `PENDING-VERIFICATION`, system-library mode is
  still `NOT RUN`, and the 53-platform `cross-test` matrix has not been started.

---

## 4. Correction pass: citations, package paths and the facade contract

**Date:** 2026-10-05
**Status of every line below:** `SOURCE-CONFIRMED`; nothing here was executed.

### Fixed — `build.zig.zon` `.paths`

- **`README.mingw.md` is dropped from `.paths`.** It is not vendored, and
  `.paths` is what the package-hashing step a dependent performs reads, so the
  entry failed `b.dependency("harfbuzz", ...)` before anything compiled. Upstream
  links it from `README.upstream.md:115`, and that link is now a link to a file
  this package does not ship; the reason is stated in the comment at
  `build.zig.zon:69-74`.
- **`README.md` is no longer listed twice** (it was at both ends of the list).
  `.paths` now names `README.upstream.md` once (upstream's bytes) and `README.md`
  once (this fork's front page). All 43 entries were checked against the tree:
  every one exists and none repeats.

### Fixed — citations that pointed at a file or line that is not there

- **The five top-level `meson.build` citations are gone.** Upstream's top-level
  `meson.build` is not vendored, so `cpp_std`, `cpp_args` and `hb_version_int`
  cannot be sourced from this tree at all. `build.zig`'s module doc now states
  `-std=c++14 -fno-exceptions -fno-rtti` as this fork's decision with the reason,
  and its SONAME section says in full which part of `abi_version` is sourced
  (`major = 0`, from `src/meson.build:650-652` and `:673`) and which is carried
  (`minor` and `patch`, `61451`, not verifiable here).
- **`src/hb-malloc.cc` is replaced everywhere by `src/hb.hh:555-558`**
  (`build.zig`'s memory claims, `zig/root.zig`'s module doc,
  `runtime/library.zig`'s ABI-boundary list). The claim was true; the file was
  not.
- **`src/harfbuzz.cc:32` → `:20`** for the `hb-ft.cc` include, in `build.zig` and
  in `build.zig.zon`.
- **`src/hb-version.h:44-52` → `:44`, `:50`, `:56`** in `build.zig`,
  `build.zig.zon`, `zig/root.zig` and `runtime/library.zig`. No range in that
  header holds all three macros: `HB_VERSION_MICRO` is on line 56.
- **`src/hb-ft.cc:126` → `:119`** for the default load flags
  (`zig/root.zig`), and **`src/hb-ft.cc:186-190` → `:177-184`** (and `:191-193`
  for a bitmap font) for the `FT_Set_Char_Size` call in `FtFont.setScale`.
- **`src/hb-ft.cc:30` → `:32`** for `HAVE_FREETYPE` in `build.zig`: line 30 is
  `#include "hb.hh"`.
- **`FT_Get_Transform`'s "since 2.4" was wrong.** The sibling's own header
  documents it as `@since 2.11`
  (`../freetype/include/freetype/freetype.h:3711-3712`). `build.zig:387-392` now
  says that, names the five call sites (`src/hb-ft.cc:520`, `:572`, `:612`,
  `:720`, `:860`) beside the guard at `:186`, and keeps the pinned-version
  citation `:5170-5172`, which is `FREETYPE_MAJOR`/`MINOR`/`PATCH` — 2.14.3.
- **`src/harfbuzz.cc:1-80` → `:1-69`**; the amalgamation has 69 lines.
- **`hb_version()`'s answer is now cited to where it is written**,
  `src/hb-common.cc:640-642`, under its declaration at `src/hb-version.h:79-82`,
  rather than to `src/hb-version.h:80-84`.
- **`-Dfreetype=none` is documented as what the code does**: refused at
  configure time (`build.zig:727-739`), not a configuration that defines
  `HB_NO_FREETYPE`. Three places said the opposite of the code.

### Fixed — the front page, and `cross-test.profile.sh`

- **`README.md` is now this fork's front page** in the workspace's order:
  native-source deviations, native-build deviations, support matrix, consumption.
  Upstream's README moved to `README.upstream.md` with its bytes intact — the
  file's sha256 is the digest `UPSTREAM.sha256` already recorded for it.
  `build.zig` installs both under `share/licenses/harfbuzz/`.
- **`cross-test.profile.sh` describes HarfBuzz.** It was a Lua SDK's text. The
  four settings are unchanged and still generic. What replaced the prose: one
  translation unit (`src/harfbuzz.cc`, 69 `#include` lines, all resolving), the
  sibling FreeType's 38 sources, `runtime/sync.c` only under `-Druntime=true`,
  the generated inputs a cell really gets (the translate-c output of
  `zig/translate.h` and the ELF version script), and the fact that there is no
  `config.h` and no meson step. It carries an SPDX line now, as `runtime/sync.h`
  already did.

### Fixed — the facade's error contract

- **`Error.OutOfMemory` no longer covers two cases it never checked.**
  `hb_blob_create_from_file_or_fail` answers null for a file that could not be
  opened, an `mmap` or read failure, the fallback reader's size ceiling *and* a
  failed allocation, so `Blob.fromFile` now answers `Error.FileNotLoaded`;
  `hb_face_create_or_fail` answers null when the blob holds no face at that index,
  so `Face.create` now answers `Error.NoFace`. `OutOfMemory` is kept for the one
  case upstream reports as an allocation failure and this package can observe:
  `hb_buffer_allocation_successful`.
- **`Blob.fromBytes` and `Buffer.create` no longer test a return value that cannot
  be null.** `hb_blob_create` answers the empty blob (`src/hb-blob.cc:75-84`) and
  `hb_buffer_create` the empty buffer (`src/hb-buffer.cc:782-783`).
- **`hb.freetype` is now a public re-export.** `FtFont.create` and
  `FtFont.createReferenced` name `*freetype.c.FT_FaceRec`; a parameter type a
  dependent cannot name is a function it cannot call.
- **`FtFont.create` now has upstream's two arguments.** `src/hb-ft.h:109-110`
  declares `hb_ft_font_create (FT_Face, hb_destroy_func_t)`; the wrapper was
  calling it with one. Upstream's own destroy callback is static, so a caller
  supplies one, or uses `createReferenced`, which needs none. Neither entry
  point has a null path, so neither returns an error union any more.
- **`create`/`createReferenced` no longer claim a `unref` boolean separates
  them.** Both leave it false (`src/hb-ft.cc:1378`); only
  `hb_ft_font_set_funcs` sets it true (`:1858`). What separates them is
  `FT_Reference_Face` plus `_hb_ft_face_destroy` (`:1503-1504`).
- **`shape` and `Buffer.serializeText` now take an `FtFont` too.** Both took
  `*const Font`, and an `FtFont` is an `hb_font_t` that is not a `Font`, so a
  FreeType-backed font could not be shaped through the facade at all — the C
  entry point does not care where the metrics came from. Both parameters are now
  `anytype`, checked by `requireFont` (`zig/root.zig:539-561`) against the
  *pointee* being `Font` or `FtFont`, in either mutability. `&font` on a `var`
  and on a `const` both pass by construction, whatever a compiler does about
  coercing a mutable pointer to a const one: that coercion is not something this
  package has observed, and the check is written so that it does not rest on it.
  `deinit` takes the mutable form, so a caller that owns the font holds a `var`,
  and the rule it has to learn is "pass your font", not "pass your font as a
  const pointer". Every existing call still compiles unchanged.

### Resolved after this pass, and what it opened

- **`Font.create`'s call to `hb_font_create_or_fail` is gone.** What this pass
  reported as open: that function is declared by no header and defined by no
  `.cc` in this tree, so the facade could not compile; `hb_font_create` exists
  (`src/hb-font.cc:2144-2163`) but returns the *empty font object* rather than
  null when its allocation fails (`:2110-2111`) and leaves the font functions
  unset (`:2149`); and `hb_ot_font_set_funcs` — declared at
  `src/hb-ot-font.h:39-40`, defined at `src/hb-ot-font.cc:1025` — was outside the
  translated closure, because `zig/translate.h` included only `<hb.h>` and
  `<hb-ft.h>`.
  `zig/translate.h:54-60` now includes `<hb-ot.h>` as well, which is the route
  the `src/hb-ot-font.h:27-28` guard forces — `hb-ot-font.h` refuses a direct
  include — and `Font.create` calls `hb_font_create` and then
  `hb_ot_font_set_funcs`. The repair landed in files this entry does not own,
  after this pass reported the blocker; who made it is not established by
  anything read out of this tree.
- **What that repair opened, closed here.** Both consequences were in files this
  pass owns:
  - `build.zig`'s `public_headers` installed 17 headers and named no `hb-ot*`
    header, while `zig/translate.h:60` reached the OpenType umbrella: a
    translated declaration whose header is not installed, which is the mismatch
    this workspace's rules are about. The list now carries `src/hb-ot.h` and
    the eleven headers `src/hb-ot.h:33-43` includes — 29 in all — and its doc
    comment names the two include lists behind it (`build.zig:177-186`). The
    installed closure and the translated closure are the same set again.
  - `Font.create`'s allocation check could not fire: it compared a pointer that
    upstream never answers as null. It now compares against
    `c.hb_font_get_empty()` — what `src/hb-font.cc:2111` answers on a failed
    allocation, declared at `src/hb-font.h:1123` — so the branch reports what it
    names and can fire.
- **`zig/translate.h:22-28` still says two headers are the closure and that
  nothing else is listed**, which its own line 60 now contradicts. It is not
  this pass's file; the records role should read it before that text ships.
- **Three files outside this pass's scope named `README.upstream.md` where they
  named `README.md`**: `tools/check-provenance.sh` (its file list and its
  "README.md still carries upstream's heading" check), `UPSTREAM.sha256` (its
  `README.md` record), and `.github/workflows/verify.yml:4` (which cites
  `README.md:7-13` for upstream's badges). The records role has since moved the
  manifest record to `README.upstream.md`, made the provenance script require the
  upstream heading there and fail if the manifest still records `README.md`, and
  repointed the workflow's citation.

## 5. One `-D` on the translation, and one platform boundary recorded

`zig build check` walks six targets. On 2026-10-05 two rows were red inside a
`setjmp.h` this package does not own — for both of them, FreeType's, reached
through `<hb-ft.h>`. One was fixable here and is; the other is not and is now
written down where a reader will meet it.

### Fixed — `riscv64-linux-gnu`

HarfBuzz's own `src/harfbuzz.cc` compiled for that target and the facade's
`translate-c` step did not, with
`libc/include/riscv-linux-gnu/bits/setjmp.h:35:3: error: unsupported FLEN` on
the way in from `include/freetype/config/ftstdlib.h:166`. glibc lays out a
RISC-V `jmp_buf` only for `__riscv_float_abi_double` and
`__riscv_float_abi_soft`; clang predefines the first for `riscv64-linux-gnu`
and Aro, which runs `translate-c`, predefines none of the three. `build.zig`
now derives the macro clang would use from the target being built and hands it
to `translate.defineCMacro`, so the facade is translated against the ABI the
library was compiled with. It goes on the translation only, and only on RISC-V.
Observed: `zig build check -Dtarget=riscv64-linux-gnu` went from exit 1 to exit
0, `Build Summary: 9/9 steps succeeded`.

### Recorded — `wasm32-wasi`

All three steps of the row fail, this package's own translation and the sibling
FreeType's translation and library, with the pinned toolchain's own message,
`libc/include/wasm-wasi-musl/setjmp.h:13: error: Setjmp/longjmp support
requires Exception handling support`, which that header raises unless
`__wasm_exception_handling__` is defined. `src/hb-ft.h:34` opens `<ft2build.h>`
and `include/freetype/config/ftstdlib.h:166` includes `<setjmp.h>` with no
guard, and `include/freetype/config/ftoption.h` offers no `FT_CONFIG_OPTION_*`
that turns it off, so no configuration in this package reaches it. The row stays
in `check_targets`, `refused_check_targets` stays empty, and `zig build check`
exits 1: a failing cell that stays visible, not a dropped one and not a pass.
`-Dfreetype=none` would compile by removing the FreeType integration, which is
the whole reason this package has a sibling dependency, so it was not used. The
full diagnosis and the two things that would have to change — the toolchain's
wasi-libc, or a documented upstream deviation — are in
[`FORK-NOTES.md`](FORK-NOTES.md). No vendored header was edited and no
replacement `setjmp.h` was vendored.

## 6. The 53-platform matrix, run and recorded

`cross-test` was run from the package root on 2026-10-05 with this package's
`cross-test.profile.sh`, `--jobs 8 --build-jobs 8`, and the pinned compiler
0.16.0 at `$ZIG_GLOBAL_CACHE_DIR/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig`.
Run id `20261005-191617-16721-31795`, all 53 Tier 1/2 targets, **exit 1**:
`pass=18 build_only=17 fail=18 partial=0`.

The 18 executed cells each ran 16 tests and reported `Build Summary: 9/9 steps
succeeded; 16/16 tests passed`; `x86_64-linux` natively and the other 17 under
QEMU user mode. 17 cells compiled and never ran, for want of an executor on
this host. No cell was refused — `refused_check_targets` is empty — and none
ran a failing test, because every failure stopped the build step.

The 18 build failures are six boundaries, five of them inside the pinned
toolchain's own headers and Aro, and each was isolated from this package by
translating a file that includes one libc header and nothing else:

* 9 NetBSD cells, on `_Pragma("GCC visibility pop")` in
  `generic-netbsd/sys/cdefs.h:413`.
* 3 32-bit OpenBSD cells, on Aro's `stddef.h:8` defining `size_t` without the
  `_SIZE_T_DEFINED_` guard every OpenBSD header relies on.
* 2 OpenBSD mips64 cells, on the `BYTE_ORDER` `#error` in
  `generic-openbsd/mips64/endian.h:40`.
* `x86-windows`, on `_ALLOCA_S_MARKER_SIZE`, which
  `any-windows-any/malloc.h:186` defines only for 64-bit Windows.
* 2 mips64 cells, which compile and fail only at the link with 5426
  out-of-range `R_MIPS_CALL16` relocations inside the one upstream object.
* `wasm32-wasi`, the same `wasm-wasi-musl/setjmp.h:13` boundary already
  recorded in section 5.

Nothing was skipped, weakened or relabelled to make a cell pass, and the
`x86-windows` macro was left undefined on purpose rather than guessed at, since
its 32-bit value is an ABI statement. Per-cell outcomes, every cited header
line, the 13 isolation probes and the harness's own 53 logs are in
`/home/tmp2/gertullj/scratch/foundation-libs/cross/harfbuzz/CROSS-TEST-53.md`
and `FORK-NOTES.md`. The `**NOT RUN**` rows for this matrix in `README.zig.md`
and `README.md` belong to another role and were not edited here.
## 7. Licence records: `NOTICE.md` carries the holders, and a checker race is fixed

### Changed

* **`NOTICE.md:20` and `NOTICE.md:23-51` now carry upstream's copyright notices
  verbatim.** The table row read "the 17 notices at `COPYING:5-21`, from Behdad
  Esfahbod, Red Hat, Google, …" — a prose list that said *Google* where upstream
  writes *Google, Inc.*, and reproduced none of the years.
  `tools/check-provenance.sh:125-128` asserts `Google, Inc.` in `COPYING`,
  `NOTICE.md` and `FORK-LICENSE.md`; `NOTICE.md` was the one of the three
  without it.

  All 17 lines are now in a fenced block copied out of `COPYING:5-21`,
  including `Copyright © 2010-2022  Google, Inc.`, and the table row points at
  that block instead of paraphrasing it. No holder was reworded and no year
  restated that `COPYING` does not carry. `FORK-LICENSE.md:12-13` already said
  the full list "is reproduced in [`NOTICE.md`](NOTICE.md)"; it now is.

  `SOURCE-CONFIRMED`

* **`tools/check-provenance.sh` — `manifest_has` replaces
  `awk … UPSTREAM.sha256 | grep -qx`.** Four assertions read the manifest through
  that pipeline. Under `set -o pipefail` it is a race: `grep -q` exits on its
  first match, awk's next write raises SIGPIPE, and the pipeline's status becomes
  141. Measured on an untouched `UPSTREAM.sha256`, the assertion for
  `test/shape/data/in-house/fonts/HarfBust.ttf` failed **27 times out of 60**, so
  `tools/check-provenance.sh` reported "the oracle fixture … is not covered by
  UPSTREAM.sha256" on a tree where all 932 digests had just matched. As a
  negative assertion (`UPSTREAM.sha256 records a fork-owned file`, and the
  `README.md` check) the same race hid a real finding.

  The path list is now read once into `manifest_paths` at
  `tools/check-provenance.sh:67`, and `manifest_has` (line 109) matches against
  it through a herestring, which has no pipe to close, so the exit status is
  grep's alone. The same variable replaces the extraction at lines 68 and 73.
  The assertions are unchanged: same paths, same failure messages, and they
  still fail when a path is genuinely absent. Measured after the change:
  `manifest_has` on a recorded path failed **0 times in 200** trials where the
  old pipeline failed 27 in 60; it returns 1 for `README.md`, which is
  deliberately not in the manifest; and `tools/check-provenance.sh` exited **0
  on 50 consecutive runs** in two batches of 25. Nothing was deleted or
  weakened.

### Not proved

  Nothing about the build. No `zig build`, no test, no smoke, no consumer run and
  no cell of the 53-platform matrix in section 6 is moved by this entry, and it
  moves nothing to `VERIFIED`.
