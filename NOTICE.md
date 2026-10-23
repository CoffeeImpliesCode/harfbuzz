# NOTICE

HarfBuzz contains material under several licences. Apply the licence for each path below; full texts are in the listed files.

| Path | Licence and attribution | Scope |
|---|---|---|
| `src/`, except `src/ms-use/` | Old MIT (`COPYING`) | HarfBuzz source and the library built from `src/harfbuzz.cc`. |
| `src/ms-use/` | MIT, Microsoft (`src/ms-use/COPYING`) | `IndicPositionalCategory-Additional.txt`, `IndicShapingInvalidCluster.txt`, `IndicSyllabicCategory-Additional.txt`. |
| `test/shape/data/in-house/fonts/` | SIL Open Font License 1.1 (`test/COPYING`) | 215 fonts; the Reserved Font Name clause applies. |
| `test/shape/data/in-house/tests/` | SIL Open Font License 1.1 (`test/COPYING`) | 86 expectation files. |
| Fork-authored files listed below | MIT (`FORK-LICENSE.md`) | The grant covers these files, not upstream material. |

`src/ms-use/COPYING` states: Copyright (c) Microsoft Corporation. The `test/shape/data/in-house/tests/*.tests` files have no individual notices and are covered by `test/COPYING`.

The 17 upstream copyright notices from `COPYING` are reproduced verbatim:

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

The MIT grant for fork-authored files covers: `build.zig`, `build.zig.zon`, `zig/root.zig`, `zig/translate.h`, `runtime/loader.zig`, `runtime/graph.zig`, `runtime/generate.zig`, `runtime/library.zig`, `runtime/sync.c`, `runtime/sync.h`, `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig`, `tools/check-provenance.sh`, `cross-test.profile.sh`, `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`, `.gitignore`, `README.md`, `README.zig.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `UPSTREAM.md`, and `UPSTREAM.sha256`.

`README.upstream.md` is excluded from that grant list. It is upstream's README, preserved byte for byte under the Old MIT licence and recorded in `UPSTREAM.sha256`. No upstream author is credited for fork-authored material; upstream copyright notices remain unchanged.
