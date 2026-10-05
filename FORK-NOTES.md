# FORK-NOTES.md — the worker's open questions, HarfBuzz 14.5.1 SDK

Written by the role that finished the template files. **No gate was run by that
role**: every status below is `PENDING-VERIFICATION` or `NOT RUN`, and no claim
in this repository has been promoted to `VERIFIED`. What follows is what the next
person needs in order to run the gates without re-deriving any of it.

## What this role touched, and what it did not

Wrote: `tests.zig`, `smoke.zig`, `consumer/{build.zig,build.zig.zon,
src/main.zig}`, `UPSTREAM.md`, `UPSTREAM.sha256`, `tools/check-provenance.sh`,
`README.zig.md`, `NOTICE.md`, `FORK-LICENSE.md`, `package.nix`, `flake.nix`,
`devenv.nix`, `devenv.yaml`, `.envrc`, `.gitignore`,
`.github/workflows/verify.yml`. `CHANGELOG.md` was written here first and is
now owned by the correction-pass role, which has kept and extended it.

Did not touch: `build.zig`, `build.zig.zon`, `zig/`, `runtime/`,
`cross-test.profile.sh`, the vendored `src/`, `docs/`, `test/`, `COPYING`, the
sibling `freetype`, `README.md`, `README.upstream.md`, and the four top-level
workspace files. Findings about the untouched files are below, not edits.

## Findings for the driver

### Resolved by the correction pass (2026-10-05, verified in the tree after it landed)

Each was found here, reported, and fixed in a file this role does not own.
They are kept rather than deleted: a reader who asks "was this ever a problem?"
should find the answer and the file that now carries it.

1. **`README.mingw.md` in `.paths` and not vendored** — the blocker for the
   consumer gate, since the package-hashing step a dependency performs reads
   `.paths`. `.paths` no longer names it; `build.zig.zon` records why.
2. **Five unverifiable `meson.build:N` citations** — every one now reads
   `src/meson.build:<line>`, including the SOVERSION lines the delivered SONAME
   rests on (`src/meson.build:650-652` and `:673`). The claim is now checkable
   in-tree.
3. **`src/hb-malloc.cc` cited for a file this release does not have** —
   `runtime/library.zig:53` now says so and names `src/hb.hh:555-558`.
4. **Citation drift** — `harfbuzz.cc:32` → `:20`, `hb-version.h:44-52` →
   `:44/:50/:56`, `hb-ft.cc:126` → `:119`. Checked against the files in this
   tree on 2026-10-05; all three were comments, so none failed a build, and
   they mattered because they are what a later wave copies.
5. **`cross-test.profile.sh` carried a Lua SDK's prose** — rewritten; its four
   settings were always generic, so harness behaviour was never affected.
6. **`Blob.fromFile` reporting a missing file as `OutOfMemory`** — the collision
   is gone. `Error` now has `FileNotLoaded` (a null from
   `hb_blob_create_from_file_or_fail`, cause unnamed) and `NoFace` (a null from
   `hb_face_create_or_fail`), with `OutOfMemory` narrowed to HarfBuzz's own
   allocator signal (`hb_buffer_allocation_successful`,
   `src/hb-buffer.cc:1539-1542`). `tests.zig` was updated with it.
7. **The `FT_Face` type was not nameable from outside** — `zig/root.zig` now
   publishes the sibling as `pub const freetype`, and `FtFont.create` has
   upstream's real two-argument signature (`src/hb-ft.h:109-110`). This role
   added the FreeType-backed tests it had recorded as structurally impossible.
8. **Upstream's README had no preserved copy** — `README.upstream.md` is now the
   upstream bytes and `README.md` is the fork's front page; the `UPSTREAM.sha256`
   record moved with the bytes and `tools/check-provenance.sh` checks the
   naming.

### Resolved: `Font.create` named a C function 14.5.1 does not declare

`zig/root.zig` called `hb_font_create_or_fail`. A tree-wide search found that
name only in that file: `src/hb-font.h` declares `hb_font_create`
(`src/hb-font.h:1117`) and nothing with an `_or_fail` suffix. The facade could
not compile, and the repair was not one line, because the entry point that call
stood in for was missing too: `hb_font_create` returns the *empty font object*
rather than null when its allocation fails (`src/hb-font.cc:2110-2111`) and
leaves the font functions unset (`src/hb-font.cc:2149`), so the OpenType
functions the whole test oracle rests on have to be attached explicitly.

Landed, read out of the tree and not compiled: `Font.create` calls
`hb_font_create` and then `hb_ot_font_set_funcs` (`zig/root.zig:338-343`),
`zig/translate.h:60` includes `<hb-ot.h>`, upstream's own umbrella, so the
single-header guard at `src/hb-ot-font.h:27-28` is satisfied as upstream intends
rather than worked around with `HB_NO_SINGLE_HEADER_ERROR`, and the allocation
failure now has a signal: `hb_font_create` answers the empty font object on
exactly one path, so the wrapper compares against `hb_font_get_empty()`
(`src/hb-font.h:1123`) instead of a null that cannot arrive.

### Resolved: the translated closure grew, and the installed headers followed it

`<hb-ot.h>` pulls in the OpenType umbrella (`src/hb-ot.h:33-43` — fetch, color,
deprecated, font, layout, math, meta, metrics, name, shape, var), so those headers
are translated and, under `-Druntime=true`, their entry points are symbols a
provider must export. `build.zig`'s `public_headers` grew to match: 29 entries
covering the whole closure of the three umbrellas, with `build.zig:177-186`
naming the two include lists behind it (`src/hb.h:31-45` and
`src/hb-ot.h:33-43`).

That is the whole of why it was worth closing rather than narrowing: a translated
declaration whose header is not installed is the silent mismatch this workspace's
own system-integration rule is about, so the third option was taken out of
running rather than chosen. `README.zig.md`'s install paragraph now names the
three umbrellas and the 29 headers, and this file's gate table agrees.

### Open, and owned by nobody: `zig/translate.h`'s own prose

`zig/translate.h:22-28` still says "the two headers above are the closure of that
surface", under a heading called "Why nothing else is listed", which its own line
60 contradicts now that it lists three umbrellas. It is prose and not a build
input, so nothing fails and no gate will catch it; it is nevertheless the last
sentence of the file that defines what this package compiles against, and it now
misdescribes that closure to anyone reading it. No agent in this exchange owns
`zig/translate.h`, so it is recorded here and flagged for the driver rather than
edited. Recorded in `CHANGELOG.md` as well.

### Resolved, in two steps, both in one day

`hb.shape` and `Buffer.serializeText` both took `*const Font`, so an `FtFont` -
an `hb_font_t` that is not a `Font` - could not be shaped through the facade at
all, and `tests.zig` had to reach for `hb.c.hb_shape` and
`hb.c.hb_buffer_serialize_glyphs` to prove anything about FreeType metrics.

The first repair widened both to `font: anytype` behind a `requireFont` that
compared the whole pointer *type* (`@TypeOf(font) != *const Font and ...`). That
fixed the shape of the problem — an `FtFont` was accepted at all — and it names
exactly two forms. Whether it also admitted `&font` on a `var` depended on a
rule neither of us has observed: an `anytype` parameter may or may not coerce
`*T` to `*const T`, and the pinned `lib/std` documents no rule either way. So
"the exact check broke `&font`" and "`&font` worked all along" are both
reasoning, not a finding, and neither is written down here as one.

What is not in doubt is the second repair: checking the *pointee*
(`zig/root.zig:551-561`, with its reasoning at `:544-550`) admits both forms by
construction rather than by a coercion rule nobody has observed — a single-item
pointer whose child is `Font` or `FtFont`, with a distinct `@compileError` for a
slice, a many-pointer and a
third owner type. `tests.zig` had been written against the narrow form and bound
a `*const hb.FtFont` view at each of its three FreeType call sites. Those views
are gone: the calls read `&font` like every other caller, and that compiles under
either reading, which is why dropping them was safe without settling the
question.

### Open: whether one `FT_Face` may back two fonts at once

The 14.5.1 release notes list a fix for a possible deadlock in
`hb_font_destroy()` after `hb_ft_font_set_funcs()`. This package does not
attempt to characterise the sharing rules of an `FT_Face` across that call, and
the consumer deliberately keeps its own FreeType library and face out of that
path so the fix path is exercised without inventing an ownership answer.
`README.zig.md` says the same thing to a reader.

### Open: the two `.fingerprint` fields

`build.zig.zon` and `consumer/build.zig.zon` both carry no `.fingerprint`, and
both say why: Zig 0.16.0 requires the field and derives it from the package
name, the compiler prints the value when it is missing, and nobody here should
invent a number in the one field whose purpose is to not be guessable. Filling
them in from the compiler's own suggestion belongs to the driver.

### `OBSERVED` — the 53-platform `cross-test` matrix, and the six boundaries it found

Run 2026-10-05 from the package root, `cross-test --jobs 8 --build-jobs 8`
with this package's `cross-test.profile.sh` and the pinned compiler
`$ZIG_GLOBAL_CACHE_DIR/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig`,
0.16.0. Run id `20261005-191617-16721-31795`, all 53 Tier 1/2 targets,
**exit 1**: `pass=18 build_only=17 fail=18 partial=0`. Every executed cell ran
16 tests and reported `Build Summary: 9/9 steps succeeded; 16/16 tests passed`.
Full per-cell table, every cited header line and the minimal reproductions:
`/home/tmp2/gertullj/scratch/foundation-libs/cross/harfbuzz/CROSS-TEST-53.md`.
Beside it: the harness's own `cross-test-summary.json` and `console.log`, the
53 per-cell logs in `runs/20261005-191617-16721-31795/`, and the 13 isolation
probes in `probe/` with `probe/README.txt`.

Nothing was refused and nothing ran a failing test: `refused_check_targets` at
`build.zig:321` is empty, and every one of the 18 failures stopped the build
step, so those cells are `run=not_run` and no cell in this matrix reached a
failing assertion. The four classes the workspace names therefore hold 18
`pass`, 17 `build_only`, 0 refused and 0 runtime failures, and the remaining 18
cells are build failures, which the four do not cover.

The 18 build failures are six distinct boundaries, five of them inside the
pinned toolchain's own tree. Each was isolated from this package by
`zig translate-c` of a file that includes one libc header and nothing else.

1. **NetBSD `_Pragma` visibility pragmas - 9 cells.** `aarch64-netbsd`,
   `aarch64_be-netbsd`, `arm-netbsd`, `armeb-netbsd`, `mips-netbsd`,
   `mipsel-netbsd`, `powerpc-netbsd`, `x86-netbsd`, `x86_64-netbsd`.
   `libc/include/generic-netbsd/sys/cdefs.h:413` puts
   `_Pragma("GCC visibility pop")` in `__END_PUBLIC_DECLS`, which `:432`
   aliases to `__END_DECLS`; Aro expands it to `#pragma GCC visibility pop` and
   then parses that as C. `#include <string.h>` alone fails the same way.
2. **OpenBSD 32-bit `size_t` - 3 cells.** `arm-openbsd`, `powerpc-openbsd`,
   `x86-openbsd`. `lib/compiler/aro/include/stddef.h:8` defines `size_t`
   without setting `_SIZE_T_DEFINED_`, which every OpenBSD header uses as its
   guard (`generic-openbsd/strings.h:45-47`), so `strings.h:47` typedefs it a
   second time as `__size_t`. On 32 bits the two differ
   (`__SIZE_TYPE__` is `unsigned int`,
   `x86-openbsd-none/i386/_types.h:123` says `unsigned long`); on 64 bits they
   do not, which is why only these three cells fail. `<stddef.h>` then
   `<strings.h>` reproduces it with no package header present.
3. **OpenBSD mips64 `BYTE_ORDER` - 2 cells.** `mips64-openbsd`,
   `mips64el-openbsd`. `generic-openbsd/mips64/endian.h:40` `#error`s unless
   `__MIPSEL__` or `__MIPSEB__` is predefined, and Aro predefines neither.
   `<sys/endian.h>` alone reproduces it.
4. **Windows 32-bit `_ALLOCA_S_MARKER_SIZE` - 1 cell.** `x86-windows`.
   `any-windows-any/malloc.h:186` defines it only for `__ia64__`, `__x86_64`
   and `__aarch64__`, then uses it unguarded at `:193` and `:221`.
   `<malloc.h>` alone reproduces it and succeeds for `x86_64-windows`.
   **Left open on purpose:** defining it on the translation is an ABI choice,
   not a workaround - the header uses 16 on 64-bit and the 32-bit marker is a
   4-byte slot - and this repository has never executed a 32-bit Windows
   binary.
5. **MIPS64 call displacement - 2 cells.** `mips64-linux`, `mips64el-linux`.
   Both compile everything and fail only at the link, 5426 times each, with
   `relocation R_MIPS_CALL16 out of range: <n> is not in [-32768, 32767]`
   inside `harfbuzz.o`. That field is 16-bit signed and both ends of the call
   are in one object, which upstream builds as one translation unit by
   construction: `src/harfbuzz.cc` is 69 `#include` lines, generated by
   `src/meson.build:479-486`. `mips-linux` and `mipsel-linux` build, link and
   run 16/16 tests each, so this is the object size against the ISA's call
   range.
6. **WASI `setjmp.h` - 1 cell.** `wasm32-wasi`, already recorded above for
   `zig build check`: all three steps stop in
   `libc/include/wasm-wasi-musl/setjmp.h:13`. Same target, same header, same
   line, and no new finding.

The 17 `build_only` cells compiled and never ran, because this host has no
executor for them: `no_local_runner_{freebsd,maccatalyst,macos,netbsd,openbsd}`,
`unsupported_windows_arch`, `missing_wine` and `missing_wine64`. Compiled is
coverage, not a pass.

The gate table in `README.zig.md:181` and `README.md:109` still reads
`**NOT RUN**` for this matrix. Those rows are another role's to update; the
observed result is the receipt above.

## What could not be determined from this tree

* **The release tarball digest.** Nothing in this repository recorded it before
  this role wrote `UPSTREAM.md`. It was read from the GitHub REST API on
  2026-10-05 (`assets[0].digest` of the `14.5.1` release, asset
  `harfbuzz-14.5.1.tar.xz`, 20259340 bytes) and attributed to that read with its
  date, because inventing one was the alternative. Re-fetching the release is
  the driver's call; the 932 per-file digests do not depend on it.
* **Whether the vendored tree equals the tarball minus the omitted directories.**
  `build.zig.zon`'s own comment names what was left out (`util/`, `perf/`,
  `test/subset/`, `test/fuzzing/`, `test/api/`, `test/vector/` and the two
  third-party corpus directories under `test/shape/data/`). That is this
  repository's record, not a comparison against an extracted release, and no one
  has made that comparison. What is verified is that the 932 files here are
  exactly the files `UPSTREAM.sha256` records.
* **The upstream history.** No commit SHA, tag object or archive import record
  exists for this pin, because this is an archive import. None was invented.
* **Every behavioural claim.** Nothing has been run.

## What the driver still owes, and what each gate would establish

| Gate | What it would establish |
|---|---|
| `sha256sum -c UPSTREAM.sha256` | the 932 vendored files are the bytes this record names |
| `tools/check-provenance.sh` | the same, plus the exact file set, an upstream-only manifest, agreement between the two digest records, all three `COPYING` files and coverage of the four oracle fixtures |
| `zig build` | the one-translation-unit C++ build links, installs, and produces the 29 public headers, the `pkg-config` file and the licence records |
| `zig build test` (Debug, then ReleaseSafe) | HarfBuzz shapes `HarfBuZZ`, `HarfRuSt` and `HarfBust` into the three recorded lines, and the Arabic run into the recorded right-to-left line |
| `zig build smoke` | the example prints every answer and closes on one line |
| `zig build check` | all six cross targets compile, tests and example included, running nothing |
| `zig build consumer` and `cd consumer && zig build run` | the module resolves from another package, and the sibling FreeType is compiled, linked and answering through its own face loader |
| `zig build -Dlinkage=dynamic` | the shared object and its `libharfbuzz.so.0` soname |
| `zig build -Druntime=true` with `HARFBUZZ_TEST_PROVIDER` | the runtime route from inside; without a provider the tests must fail loudly rather than skip |
| `cd consumer && zig build run -Druntime=true -- --provider <path>` | the same from outside, including a provider that is not on the default search path |
| `zig build -fsys=harfbuzz` | system mode, against an installed HarfBuzz whose headers are the ones translated. **No such installation has been exercised**, so this row is `NOT RUN` |
| `cross-test` from the package root | the published 53-platform matrix, with `build_only` recorded for any platform without an executor |

Two environment facts a run needs, both from upstream rather than from this
package:

* `LC_ALL=C`. `test/shape/run-tests.py:19` sets it, `hb_language_get_default()`
  reads the locale, and a recorded line taken under "C" is not guaranteed under
  another locale. `devenv.nix` and `verify.yml` both set it.
* The sibling FreeType checkout beside this one. Every build option here resolves
  it as a relative path and nothing downloads it.

## Lessons, in the shape a later wave can apply

**A citation to a file the release does not contain is indistinguishable from a
correct one until something checks it.** Condition: an SDK vendored from an
archive, with a build graph written in the same pass. Symptom: `build.zig`
citing `meson.build:28` and `src/hb-malloc.cc`, neither of which exists in the
tree, while the four citations around them are exactly right. Fix: run one
existence check over every path the landed files cite, before writing the
records, and put the misses in the report rather than in a comment. Targets
bound: any archive-import SDK in this workspace; any library whose build graph
was written from memory of upstream rather than from the vendored bytes.

**A transitive module import is invisible at the call site and fatal at the
boundary.** Condition: a facade whose private imports appear in public
signatures. Symptom: `FtFont.create` takes `*freetype.c.FT_FaceRec`, which a
dependent cannot name, and a consumer that re-depends on the sibling gets a
*second* module instance — the same headers, two unrelated Zig types, and a type
error rather than a helpful message. Fix: when a public signature names a type
from a private import, either re-export it or route the test through the
public surface (`hb_ft_font_set_funcs`); do not add the second dependency to make
the types match. Targets bound: this wave's contract-migration facades, any SDK
with a sibling package.

**Zig 0.16 removed `std.fs.cwd()` and `std.process.argsAlloc`.** Condition:
writing a 0.16 program from 0.11/0.12 memory. Symptom: `std.fs.cwd()` does not
resolve (`std.Io.Dir.cwd()` takes an `Io`; `readFileAlloc` takes `(io, path,
gpa, Io.Limit)`), and there is no `argsAlloc` — `std.process.Init` carries
`arena`, `gpa`, `io`, `environ_map` and `minimal.args`, and
`minimal.args.toSlice(arena)` is the cross-platform way to get arguments.
`pub fn main()` with no parameters is still supported; `main(init:
std.process.Init)` and `main(init: std.process.Init.Minimal)` both are too. Fix:
resolve an unfamiliar API by reading the pinned compiler's `lib/std`, which is
what the workspace rules already say. Targets bound: every file written in this
wave that touches the filesystem, arguments or the environment.

## The two cross-target cells that were red, one fixed and one bound

`zig build check` walks six targets. On 2026-10-05 two of them were red and both
were red inside a `setjmp.h` this package does not own: neither belongs to
HarfBuzz, and both are reached through `zig/translate.h`'s `#include <hb-ft.h>`,
which opens FreeType's `ft2build.h` at `src/hb-ft.h:34-35`. They have different
causes and different answers, so they are recorded separately.

### `riscv64-linux-gnu` — the translator and the C++ compiler disagreed about one macro

* **Condition.** `zig build check` with no `-Dtarget`, walking the
  `riscv64-linux-gnu` row.
* **Symptom.** `src/harfbuzz.cc` and the sibling FreeType's units compiled; the
  two `translate-c` steps did not:

  ```text
  /home/tmp2/gertullj/zig-global-cache/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/lib/libc/include/riscv-linux-gnu/bits/setjmp.h:35:3: error: unsupported FLEN
  # error unsupported FLEN
  ```

  `Build Summary: 2/6 steps succeeded (1 failed)` on the single-cell run.
* **Cause, read out of the pinned toolchain.** `bits/setjmp.h:32-36` gives the
  RISC-V `jmp_buf` twelve callee-saved `double` registers when
  `__riscv_float_abi_double` is defined, none when `__riscv_float_abi_soft` is,
  and raises `#error unsupported FLEN` for `__riscv_float_abi_single`, the only
  ABI left with no layout there. Clang and Aro disagree about which one that is:
  `zig cc -target riscv64-linux-gnu` predefines `__riscv_float_abi_double`
  (observed with an `#error` probe that names the macro), so both C++ compiles
  are fine, while `translate-c` predefines none of the three and stops on the
  same line.
* **Fix.** `build.zig` gives the translation the macro the compiles were given.
  `translateCRiscvFloatAbi` derives it from the target being built — `d` gives
  `__riscv_float_abi_double`, `f` without `d` gives
  `__riscv_float_abi_single`, neither gives `__riscv_float_abi_soft` — and hands
  it to `translate.defineCMacro`, so the facade is translated against the ABI
  the libraries were compiled with. It goes on the translation only: clang
  already predefines it on every compile line. It is null off RISC-V, so no
  other architecture sees a `-D` it did not need, and a `single`-ABI target
  still fails inside glibc rather than having its failure translated away.
* **Result, observed.** `zig build check -Dtarget=riscv64-linux-gnu` exited 0
  after the change, `Build Summary: 9/9 steps succeeded`, with `translate-c
  success 633ms` and `translate-c success 268ms` for this package and the
  sibling. Before it, the same command exited 1.
* **Targets bound.** Zig 0.16.0, and the `riscv32`/`riscv64` rows of any build
  graph that translates a header reaching `<setjmp.h>` under glibc. The entry
  rests on Aro's predefine set for RISC-V, so a toolchain that teaches
  `translate-c` the macro retires it, and until then the `-D` is the only way
  to make the translation agree with the compile.

### `wasm32-wasi` — a platform boundary, and this package cannot move it

* **Condition.** The `wasm32-wasi` row of `zig build check`.
* **Symptom.** All three steps of the row fail, this package's own
  `translate-c`, the sibling FreeType's `translate-c`, and the sibling
  FreeType's C library, with the pinned toolchain's own message:

  ```text
  /home/tmp2/gertullj/zig-global-cache/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/lib/libc/include/wasm-wasi-musl/setjmp.h:13:2: error: Setjmp/longjmp support requires Exception handling support, which is [not yet standardized](https://github.com/WebAssembly/proposals?tab=readme-ov-file#phase-3---implementation-phase-cg--wg). To enable it, compile with `-mllvm -wasm-enable-sjlj` and use an engine that implements the Exception handling proposal.
  #error Setjmp/longjmp support requires Exception handling support, which is [not yet standardized](https://github.com/WebAssembly/proposals?tab=readme-ov-file#phase-3---implementation-phase-cg--wg). To enable it, compile with `-mllvm -wasm-enable-sjlj` and use an engine that implements the Exception handling proposal.
  ```

  `zig build check` exits 1 and will keep doing so.
* **Cause, read out of the pinned toolchain.**
  `libc/include/wasm-wasi-musl/setjmp.h:10-15` opens `/* WASI has no setjmp */`
  and raises that `#error` unless `__wasm_exception_handling__` is defined, so
  the refusal is in wasi-libc's own header. Everything above it is FreeType's:
  `src/hb-ft.h:34` opens `<ft2build.h>` and `FT_FREETYPE_H`, and
  `include/freetype/config/ftstdlib.h:166` includes `<setjmp.h>` with no guard.
* **Why this package cannot configure its way out.** FreeType's
  `include/freetype/config/ftoption.h` ships no `FT_CONFIG_OPTION_*` that turns
  the include off, so no macro this package can define reaches it. Defining
  `__wasilibc_unmodified_upstream` or `__wasm_exception_handling__` from a build
  would silence the header and leave declarations with no implementation behind
  them. `-Dfreetype=none` would compile by dropping the FreeType integration,
  which is the one reason this package has a sibling dependency at all, so it
  would deliver a smaller SDK rather than a built one.
* **Fix.** None here, and none in this repository. The two real moves are both
  outside it: the pinned toolchain's wasi-libc gaining the exception-handling
  proposal, or a documented upstream deviation in FreeType guarding
  `ftstdlib.h:166`. Vendoring a replacement `setjmp.h` or editing a vendored
  header would break upstream integrity, so neither was done.
* **Status of the cell.** Not a pass and not a refusal. `wasm32-wasi` stays in
  `check_targets` and `refused_check_targets` stays empty, so the row keeps
  failing loudly rather than disappearing from the matrix.
* **Targets bound.** `wasm32-wasi` on Zig 0.16.0's wasi-libc, for any build of
  this package that keeps `HAVE_FREETYPE`. The boundary is not HarfBuzz's: it
  is FreeType's header and the toolchain's libc, and libpng meets the same one
  from its own `src/pngconf.h:48-50`.

### Receipts, for both rows

Both were run in this tree on 2026-10-05 with the pinned Zig 0.16.0 at
`/home/tmp2/gertullj/zig-global-cache/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig`,
`-j8 --summary all`, default optimize mode, `--cache-dir` under
`/home/tmp2/gertullj/cache/foundation-libs/wave10-fresh/harfbuzz`. `zig build`
exited 0. `zig build check` exited 1 with `Build Summary: 42/49 steps succeeded
(3 failed)`, all three failures inside the `wasm32-wasi` row, and
`zig build check -Dtarget=riscv64-linux-gnu` exited 0 with
`Build Summary: 9/9 steps succeeded` — it exited 1 before the `-D` landed. Logs:
`local://harfbuzz-check-six-targets-2026-10-05.log`,
`local://harfbuzz-check-riscv64-linux-gnu-2026-10-05.log`,
`local://harfbuzz-zig-build-2026-10-05.log`.

`tools/check-provenance.sh` reports all 932 upstream files matching
`UPSTREAM.sha256` and the vendored file set exactly the recorded 918, so nothing
under `src/`, `docs/` or `test/` was touched. It then exits 1 on two
records-level checks that are not about this section — "the manifest records no
fork-owned file" and "upstream's copyright notice is missing from `NOTICE.md`" —
which this pass did not cause and did not attempt to fix; they belong to
`UPSTREAM.sha256` and `NOTICE.md`, which no change here touched.