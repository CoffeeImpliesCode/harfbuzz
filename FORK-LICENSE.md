# FORK-LICENSE.md — the grant for this fork's own files

[`NOTICE.md`](NOTICE.md) is the inventory: which files are upstream's, which are
this fork's, and which term covers each. This file is the grant itself, for the
second group only.

## 1. The native source is not covered by anything below

The 932 files listed in `UPSTREAM.sha256` are HarfBuzz's, whole from
`harfbuzz-14.5.1.tar.xz` and never edited. They are the so-called "Old MIT"
licence (`COPYING:1`), whose copyright notices begin at `COPYING:5` and run to
`COPYING:21` — Google, Inc. (`COPYING:5`, © 2010-2022) among the seventeen
holders, and the full list is reproduced in [`NOTICE.md`](NOTICE.md). Nothing in
this file re-grants, narrows, widens or conditions that term, and nothing here
asserts that Google, Inc., Behdad Esfahbod, Red Hat, Inc., David Turner,
Werner Lemberg, Adobe, Inc. or any named author wrote, reviewed or endorsed a
line of fork code.

Two subdirectory licences travel with that source and are also untouched:
`src/ms-use/COPYING` (MIT, Microsoft Corporation) and `test/COPYING` (SIL Open
Font License 1.1, for the shaping corpus). Neither is re-granted here either.

## 2. The fork-authored material

Everything else in this repository — the Zig build, the typed facade and its
translation header, the tests, the example, the consumer package, the
runtime-loading route, the packaging, the integrity script and the documentation
— was written for this fork. The runtime-loading route is the six files under
`runtime/`: the reusable loader, this SDK's descriptor, the build half that wires
them together, the build-time generator, and the two C files that supply the
synchronization the descriptor binds. All six are fork work under this grant;
none of them is upstream material and none is derived from a third-party source.

### Grant

**Those files are released under the MIT License**, matching the primary
upstream term of this project, whose text is:

```
MIT License

Copyright (c) 2026 the contributors to this fork

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

The same obligation MIT imposes on this fork applies to this text: keep the
notice with copies of the fork's files.

### Authority for that grant

The owner of this repository authorized per-project licensing for fork-authored
additions as part of the SDK contract migration, with the term chosen per project
to match that project's primary upstream terms where that is appropriate.
HarfBuzz's primary upstream term is the "Old MIT" licence, which *is* the MIT
licence — the same permission, the same single condition, the same warranty
disclaimer, with the copyright notice carried per file rather than once. MIT is
therefore the choice, and it is not a narrowing: upstream's copyleft obligations
are absent because upstream grants none. The authorization is recorded here and
in [`NOTICE.md`](NOTICE.md); the term above is the owner's, reached by that
authorization and not by any upstream grant.

The owner is not named and no individual copyright holder is invented: the
copyright line above is deliberately the collective one.

### SPDX identifier

```
MIT
```

The plain registered identifier, with no `LicenseRef-` wrapper, and the reason
is sharper here than for a project with a single term. **This tree is not one
licence**: the compiled core is Old MIT, `src/ms-use/` is MIT with a different
holder, and the shaping corpus under `test/` is OFL-1.1. A consumer scanning a
source file for `MIT` must not read that as a statement about the package, which
is exactly why [`NOTICE.md`](NOTICE.md) exists and why it carries the inventory
rather than leaving it to be inferred. `MIT` is the accurate identifier for the
fork-authored files and for the compiled core; inventing a `LicenseRef-` for
either would misrepresent a plain grant as a variant one.

Every fork-authored **source, build, packaging and script** file carries
`SPDX-License-Identifier: MIT` in its header comment, and
[`NOTICE.md`](NOTICE.md) names each of them one by one, including the three that
carry no identifier and why. The documentation and digest records are prose and
data, and `NOTICE.md` names each of them explicitly so that a scanner finding no
identifier in `README.zig.md` reads a recorded reason rather than an apparent
gap.

### What this does not do

* It does not re-license, sublicense or add a condition to any HarfBuzz file.
* It does not extend to the shaping corpus, which is OFL-1.1 with its Reserved
  Font Name clause, or to `src/ms-use/`, which is Microsoft's MIT.
* It does not assert that Google, Inc., Behdad Esfahbod, Red Hat, Inc., Igalia
  S.L., Adobe, Inc. or any other named holder authored, reviewed, endorsed or is
  affiliated with the fork's files.
* It does not discharge HarfBuzz's attribution obligation. A consumer who ships a
  HarfBuzz 14.5.1 library, static or shared, still owes the notices at
  `COPYING:5-21`; see [`NOTICE.md`](NOTICE.md) for where they travel, which is
  `share/licenses/harfbuzz/` after `zig build`.
* It does not claim that MIT is the only term the owner could have chosen for
  independently authored work. It is the term chosen, and it happens to match
  upstream's.

## 3. Material carried but not authored here

Two things travel with this package that are neither upstream HarfBuzz nor fork
source.

**The shaping corpus is upstream's, under its own licence.** The 215 fonts and 86
`.tests` files under `test/shape/data/in-house/` come from the release and are
covered by `test/COPYING` (OFL-1.1). They are *used* by this package's tests as
an oracle and they are not modified; that is material carried, and
`UPSTREAM.sha256` gives each of them a digest like any other upstream file.

**The sibling FreeType is a separate package.** HarfBuzz's `hb_ft_font_*`
surface cannot be compiled or linked without FreeType, so this package depends on
the sibling `../freetype` at build time. Its source, its licence and its records
live in that package and travel with it into any consumer's build graph; this
file grants nothing over it and this package's `NOTICE.md` does not inventory
it. A consumer of this SDK receives both.

The two files this build generates are not carried material either, and the
distinction is worth keeping exact rather than dropping a category to make the
sentence short. Under `-Druntime`, `runtime/generate.zig` writes the dispatch and
its patched translation into the build cache rather than into this tree, and both
are built from the translation of `zig/translate.h` and upstream's own headers
that this same build has just produced for the target being built. Nothing is
fetched to make them, no third-party code is in them, and neither is installed
or shipped.

## 4. Why a separate file at all

`NOTICE.md` names which fork-authored files carry an `SPDX-License-Identifier`
line and which carry the same grant in prose without one. This file exists so
that the authority, the grant text and the limits of that grant live in one
place, next to the inventory rather than scattered across the files themselves.
It also exists because the inventory has three entries in it and the shortest
true sentence about them — "this package is MIT" — would be false.