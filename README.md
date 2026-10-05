# HarfBuzz 14.5.1 for Zig 0.16 — this package's README

This is the fork's front page: what this package does to upstream's HarfBuzz,
what it refuses to do, what has actually been run against it, and how to
consume it. Upstream's own README is preserved next to it as
[`README.upstream.md`](README.upstream.md), byte for byte, so a reader can
compare the two without diffing a rewritten upstream text. The long-form Zig
reference is [`README.zig.md`](README.zig.md); this file is the short one and
deliberately does not repeat it.

**Nothing in this package has been built, tested or run by the author of these
records.** Every claim below is `SOURCE-CONFIRMED` — read out of a file in this
tree — and every gate is `PENDING-VERIFICATION` until the driver runs it and
records the receipt. See [Support matrix](#support-matrix) for exactly what has
and has not run.

Release pin: HarfBuzz 14.5.1, from the release tarball
`harfbuzz-14.5.1.tar.xz` (20259340 bytes, sha256
`7e2fa4e8c7c98e8d8140671f5772542afaaa6acccfbd746506886b6d85f7f8d6`), an archive
import with no commit SHA because there is no commit to name. Provenance and the
API the digest was read through: [`UPSTREAM.md`](UPSTREAM.md).

## Current native-source deviations

**There are none.** The 932 files recorded in [`UPSTREAM.sha256`](UPSTREAM.sha256)
— all of `src/`, all of `docs/`, `test/` and the top-level files that describe
the release — are upstream's bytes, unmodified. No upstream file was
reformatted, patched or deleted, and no upstream licence text was touched.
`tools/check-provenance.sh` fails if a digest changes, if a file appears under a
vendored tree without one, or if the number of `COPYING` files changes.

Three file-set facts, all of them about what was *not* vendored:

- **Upstream's top-level `meson.build` is not here.** `src/meson.build` is, and
  it is what this package cites. Everything else upstream's build describes —
  `project()`, `cpp_std`, `cpp_args`, `hb_version_int` — lives in the top-level
  file, so no statement about upstream's own compiler settings can be sourced
  from this tree. Where that matters, `build.zig` says so rather than citing a
  file that is not in the package.
- **`README.python.md` and `README.mingw.md` are not here.** Upstream's README
  links both (lines 113 and 115 of that file). They are development notes about
  Python bindings and about cross-compiling from Linux or macOS, and this
  package does neither. The links in `README.upstream.md` stay as upstream wrote
  them; they point at files this package does not ship.
- **`util/`, `perf/`, `test/subset/`, `test/fuzzing/`, `test/api/`,
  `test/vector/` and the third-party corpus directories are not here**, with the
  justification recorded in `UPSTREAM.md`. None of them is in this package's
  compiled closure.

## Native-build deviations, and why

**One translation unit.** `src/harfbuzz.cc` is HarfBuzz's own amalgamation and
the only compiled source: 69 `#include` lines, all of them `.cc` files that
resolve against `src/`, reaching the platform shims and the FreeType integration
among others. No meson, no CMake, no autotools, no build-time download and no
generated `config.h`.

**C++14, no exceptions, no RTTI.** `-std=c++14 -fno-exceptions -fno-rtti`, and
all three are this fork's decision, not a citation — see the meson fact above.
HarfBuzz throws nothing and uses no RTTI, both settings shrink the object and
drop its exception table, and one dialect for every target is what keeps a cross
build from compiling the same source under two different rules.

**The compile line carries the configuration, not a generated header.**
`HAVE_CONFIG_H` is never defined, so there is no `config.h` to regenerate per
target and nothing whose content could disagree with the target being built. The
facts that header would carry are resolved from the resolved target:
`HAVE_PTHREAD`, `HAVE_ATEXIT`, and the `HAVE_SYS_MMAN_H` / `HAVE_UNISTD_H` /
`HAVE_MMAP` / `HAVE_MPROTECT` family where the target's libc has those headers.
Every other `HAVE_*` is left undefined, which is upstream's "all optional
dependencies off" configuration.

**The sibling FreeType is a hard, declared dependency.** `src/harfbuzz.cc:20`
includes `hb-ft.cc` unconditionally, so this package compiles against the
sibling `../freetype` *source tree* and links that package's archive. It is a
relative path dependency (`build.zig.zon`), selected with `-Dfreetype=<path>` and
defaulting to `../freetype`. There is no search path, no registry fetch and no
system FreeType. `-Dfreetype=none` is **refused at configure time**, with the
reason printed: `zig/root.zig` names `hb_ft_font_create`, and a facade that calls
an entry point the build does not contain is a stub.

**The SONAME is upstream's, and half of the constant is carried.** The SONAME
component is read out of the tree: `src/meson.build:650-652` sets
`hb_so_version` to `0` off a Microsoft compiler and `:673` passes it to the
`library()` call, and Zig takes the SONAME from `version.major`. The file-name
components are not sourceable here — `src/meson.build:643` shows the shape of
upstream's own version string, but `hb_version_int` is assigned in the top-level
`meson.build` this package does not vendor — so they are carried from upstream's
convention and `build.zig` says exactly that in its SONAME section.

**What is installed.** The archive or shared object, the 29 public headers this
library installs, a relocatable `harfbuzz.pc`, and `share/licenses/harfbuzz/`
carrying `COPYING`, `test/COPYING` and this fork's records, upstream's README
included as `README.upstream.md`.

## Support matrix

| Configuration | Command | Status |
|---|---|---|
| Static archive | `zig build` | **exit 0** on 2026-10-05 |
| Shared object, upstream's SONAME | `zig build -Dlinkage=dynamic` | `PENDING-VERIFICATION` |
| Behavioural tests, Debug | `zig build test` | `PENDING-VERIFICATION` |
| Behavioural tests, ReleaseSafe | `zig build test -Doptimize=ReleaseSafe` | `PENDING-VERIFICATION` |
| Example program | `zig build smoke` | `PENDING-VERIFICATION` |
| Six-target compile check | `zig build check` | **exit 1** on 2026-10-05: five rows compile, `wasm32-wasi` fails |
| Consumer package | `zig build consumer`, then `zig build run` in `consumer/` | `PENDING-VERIFICATION` |
| Runtime-loaded route | `zig build -Druntime=true test` with a named provider | `PENDING-VERIFICATION`, not run |
| System-library mode | `zig build -fsys=harfbuzz` | declared, **NOT RUN** |
| 53-platform matrix | `cross-test` from the package root | **NOT RUN** |

The six check targets are `x86_64-linux-gnu`, `aarch64-linux-gnu`,
`aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` and
`wasm32-wasi`, and none is refused. On 2026-10-05 `zig build check` was run
and exited 1 with exactly one failing row: `wasm32-wasi`, whose three steps all
stop inside the pinned toolchain's wasi-libc,
`libc/include/wasm-wasi-musl/setjmp.h:13`, reached through FreeType's
`include/freetype/config/ftstdlib.h:166`. Five rows compile. The earlier claim
that every one of them compiles was a reasoned expectation and it was wrong; the
full diagnosis is in [`FORK-NOTES.md`](FORK-NOTES.md), and `riscv64-linux-gnu`
needed one `-D` on the translation, now recorded in `CHANGELOG.md` entry 5.

Known gaps are listed in [`CHANGELOG.md`](CHANGELOG.md) rather than here, so
there is one place to strike them from.

## Consumption

One published module, `dep.module("harfbuzz")`, whose source is `zig/root.zig`:

```zig
const hb = @import("harfbuzz");

var blob = try hb.Blob.fromBytes(font_bytes);   // HB_MEMORY_MODE_READONLY
defer blob.deinit();
var face = try hb.Face.create(&blob);
defer face.deinit();
var font = try hb.Font.create(&face);            // HarfBuzz's own OT font funcs
defer font.deinit();

var buffer = try hb.Buffer.create();
defer buffer.deinit();
try buffer.addUtf8("HarfBuZZ");
buffer.guessSegmentProperties();
try hb.shape(&font, &buffer, &.{});
```

Positions are in the face's own `unitsPerEm` unless `Font.setScale` says
otherwise, features are passed rather than hidden (`[]const hb.c.hb_feature_t`),
and HarfBuzz's allocator is the C library's, so a Zig allocator can neither
bound nor intercept it and this package claims no leak oracle.

Errors are four honest tags and no taxonomy this package cannot justify:

| Tag | Meaning |
|---|---|
| `ShapingFailed` | `hb_shape` answered false: the buffer still holds the original codepoints |
| `OutOfMemory` | HarfBuzz reported that its own allocator failed, through `hb_buffer_allocation_successful` |
| `FileNotLoaded` | `hb_blob_create_from_file_or_fail` answered null: a path that cannot be opened, a read failure, an allocation failure, or the fallback reader's size ceiling — the wrapper checked none of those apart |
| `NoFace` | `hb_face_create_or_fail` answered null: the blob holds no face at index 0, or the face object could not be allocated |

The FreeType route re-exports the sibling's facade as `hb.freetype`, because
`FtFont.create` and `FtFont.createReferenced` name `*freetype.c.FT_FaceRec` in
their signatures and a parameter type a dependent cannot name is a function it
cannot call. `create` takes upstream's second argument, the destroy callback,
because upstream's own is static; `createReferenced` needs none.

Both font owners can be shaped with: `shape` and `Buffer.serializeText` take a
`Font` or an `FtFont` by pointer, mutable or not, because `hb_shape` does not care
where the metrics came from.

A dependent that does not depend on the sibling at all can still shape from a
font blob and reach FreeType through the `hb_ft_*` entry points this package
already declares — `consumer/src/main.zig` is that route.

C consumers get `lib/pkgconfig/harfbuzz.pc` with a `pcfiledir`-relative prefix,
so the installed file is correct wherever `--prefix` put it. `package.nix` builds
nothing but this repository; `devenv.nix` is the canonical shell and sets
`LC_ALL=C`, which the recorded shaping lines depend on.

Records: [`UPSTREAM.md`](UPSTREAM.md) and [`UPSTREAM.sha256`](UPSTREAM.sha256)
for provenance, [`NOTICE.md`](NOTICE.md) for the per-file licence inventory,
[`FORK-LICENSE.md`](FORK-LICENSE.md) for this fork's own grant,
[`CHANGELOG.md`](CHANGELOG.md) for every change and every known gap, and
[`FORK-NOTES.md`](FORK-NOTES.md) for the open questions.