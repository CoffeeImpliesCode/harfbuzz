# NOTICE.md — per-file licence inventory, HarfBuzz 14.5.1 SDK

HarfBuzz is not one licence. `COPYING:1` says so in its own first line — "the
so-called *Old MIT* license" — and `COPYING:2-3` adds the rule that makes a
single label wrong here: "For parts of HarfBuzz that are licensed under
different licenses see individual files names COPYING in subdirectories where
applicable." This file is that inventory. A consumer looking at the artifact
should read this before reading the licence id.

Apache-2.0's `NOTICE` obligations do not apply: nothing in this tree is
Apache-2.0, and no file has been altered, so there is no "files changed"
statement to make. Zlib's marking obligation does not apply either.

## The compiled core

| | |
|---|---|
| Licence | the so-called "Old MIT" licence |
| Full text | `COPYING` — the permission and the two paragraphs of warranty disclaimer, `COPYING:26-42` |
| Copyright holders | the 17 notices at `COPYING:5-21`, reproduced verbatim below |
| What it covers | all 575 files under `src/`, and the compiled library this package builds from `src/harfbuzz.cc` |

The 17 notices at `COPYING:5-21`, verbatim, each with its own years exactly as
upstream writes them:

```
Copyright © 2010-2022  Google, Inc.
Copyright © 2015-2020  Ebrahim Byagowi
Copyright © 2019,2020  Facebook, Inc.
Copyright © 2012,2015  Mozilla Foundation
Copyright © 2011  Codethink Limited
Copyright © 2008,2010  Nokia Corporation and/or its subsidiary(-ies)
Copyright © 2009  Keith Stribley
Copyright © 2011  Martin Hosken and SIL International
Copyright © 2007  Chris Wilson
Copyright © 2005,2006,2020,2021,2022,2023  Behdad Esfahbod
Copyright © 2004,2007,2008,2009,2010,2013,2021,2022,2023  Red Hat, Inc.
Copyright © 1998-2005  David Turner and Werner Lemberg
Copyright © 2016  Igalia S.L.
Copyright © 2022  Matthias Clasen
Copyright © 2018,2021  Khaled Hosny
Copyright © 2018,2019,2020  Adobe, Inc
Copyright © 2013-2015  Alexei Podtelezhnikov
```

Those lines are `COPYING:5-21` copied out; no holder is paraphrased and no year
is restated that `COPYING` does not carry. `FORK-LICENSE.md` names them in its
own prose and points here for the full list. `COPYING:23` adds "For full
copyright notices consult the individual files in the package", and those
per-file headers were not edited: they are in the 932 files `UPSTREAM.sha256`
covers.

## Per-file and per-directory exceptions

Two subdirectory licence files exist in this tree, and they are the whole of the
exception set. `tools/check-provenance.sh` fails if that count ever changes, so
a third exception cannot be added without this file being updated.

### `src/ms-use/COPYING` — the MIT licence, Microsoft Corporation

`src/ms-use/` holds three Unicode data files upstream took from Microsoft:
`IndicPositionalCategory-Additional.txt`, `IndicShapingInvalidCluster.txt` and
`IndicSyllabicCategory-Additional.txt`, with `src/ms-use/COPYING` beside them.
Its text is the standard MIT permission and warranty disclaimer
(`src/ms-use/COPYING:5-25`) and its holder is "Copyright (c) Microsoft
Corporation." (`src/ms-use/COPYING:3`). These files are data, not compiled code;
the Indic shaper reads them at build time through upstream's own table
generator, which this package does not run.

### `test/COPYING` — the SIL Open Font License 1.1

`test/COPYING:1-5` states that the SIL Open Font License, Version 1.1, applies
to many of the fonts in that folder, and `test/COPYING:11` is the full licence
text ("SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007"). It covers the 215
fonts under `test/shape/data/in-house/fonts/` and the 86 expectation files under
`test/shape/data/in-house/tests/`.

This is the licence that travels furthest from the compiled core: the library is
Old MIT, the fixtures this package's tests hold themselves to are OFL-1.1, and
the two are not interchangeable. The OFL's Reserved Font Name clause applies to
the font files, so none of them may be renamed in a distribution.

## What this fork added

Fork-authored material is not covered by any upstream grant; upstream's terms do
not themselves grant rights to it. Under the workspace owner's per-project
authorisation, every file this fork adds to this package is granted under the MIT
licence, matching the character of the project's primary upstream terms. The
grant is `FORK-LICENSE.md`, and it covers:

`build.zig`, `build.zig.zon`, `zig/root.zig`, `zig/translate.h`,
`runtime/loader.zig`, `runtime/graph.zig`, `runtime/generate.zig`,
`runtime/library.zig`, `runtime/sync.c`, `runtime/sync.h`, `tests.zig`,
`smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`,
`consumer/src/main.zig`, `tools/check-provenance.sh`,
`cross-test.profile.sh`, `package.nix`, `flake.nix`, `devenv.nix`,
`devenv.yaml`, `.envrc`, `.gitignore`, `.github/workflows/verify.yml`, `README.md`,
and the records `README.zig.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`,
`UPSTREAM.md`, `UPSTREAM.sha256`.

`README.upstream.md` is **not** in that list and must not be added to it: it is
upstream's own README, byte for byte, preserved under the name this fork gives
it so `README.md` can be the fork's front page. It is upstream material under
upstream's Old MIT grant, it carries a digest in `UPSTREAM.sha256`, and
`tools/check-provenance.sh` fails if its bytes change or if the manifest records
it under the fork's name instead.

None of that is attributed to any upstream author. Every upstream copyright
notice in the tree is preserved verbatim, including the two exception licences
above.

Of those, the source, build, packaging and script files carry
`SPDX-License-Identifier: MIT` in their header comment. Four do not, and the
reason is recorded rather than left as an apparent gap:
`consumer/build.zig.zon` is package metadata whose grammar admits only comments
and fields, `.gitignore` is a list of path patterns with no code in it,
`README.md` is prose whose licence the whole of this package states here and in
`FORK-LICENSE.md` rather than in a tag inside it, and `UPSTREAM.sha256` is digest
data. Each is covered by the grant in [`FORK-LICENSE.md`](FORK-LICENSE.md) on the
same terms as the files that do carry the identifier.

## Files that carry no notice at all

`test/shape/data/in-house/tests/*.tests` are expectation data with no per-file
notice; they are covered by `test/COPYING` as files of that folder. Upstream's
own statement is the whole of the record for them, and this file does not invent
one.

## Verifying this inventory

```sh
tools/check-provenance.sh
```

It checks that `COPYING` still carries the Old MIT statement and the upstream
copyright notices, that both subdirectory licences are still present, that this
file names both exceptions, and that the owner authorisation text in
`FORK-LICENSE.md` is intact. It needs no compiler.