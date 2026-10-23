# FORK-LICENSE.md — the grant for this fork's own files

`NOTICE.md` inventories the files and their terms. This grant covers fork-authored files only.

## Upstream files

The 932 files listed in `UPSTREAM.sha256` are HarfBuzz 14.5.1 from `harfbuzz-14.5.1.tar.xz`. They are unmodified and remain under upstream's "Old MIT" licence in `COPYING`. `NOTICE.md` lists the 17 copyright holders, including Google, Inc. Nothing here re-grants, narrows, widens or conditions that licence. This file does not claim that Google, Inc., Behdad Esfahbod, Red Hat, Inc., David Turner, Werner Lemberg, Adobe, Inc., Igalia S.L. or any other named holder wrote, reviewed or endorsed fork code, or is affiliated with the fork.

`src/ms-use/COPYING` covers upstream Microsoft MIT files under `src/ms-use/`. The 215 fonts and 86 `.tests` files in `test/shape/data/in-house/` are unmodified upstream release files under `test/COPYING` (SIL Open Font License 1.1, including its Reserved Font Name clause). These upstream terms remain unchanged.

## Fork-authored files

The fork-authored material is the Zig build, facade and translation header; tests, example and consumer; runtime route; packaging; integrity script; and documentation listed in `NOTICE.md`. The six files under `runtime/` are the loader, descriptor, build graph, generator and two synchronization C files. All six are fork work, not upstream material or third-party-derived. The MIT grant covers those fork-authored files, not upstream files.

### Grant

**Fork-authored files are released under the MIT License:**

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

Copies of fork-authored files must keep the copyright and permission notices.

The repository owner authorized this project-level grant. HarfBuzz's primary upstream term is Old MIT, so MIT is selected. The owner is unnamed and no individual copyright holder is asserted; MIT is not the only term available for independently authored work.

### SPDX identifier

```
MIT
```

`MIT` identifies fork-authored files and the compiled core's plain Old MIT term; it does not identify the whole tree. Fork-authored source, build, packaging and script files carry `SPDX-License-Identifier: MIT`. Documentation and digest records have no SPDX header; `NOTICE.md` identifies them.

## Other material and limits

HarfBuzz depends on sibling `../freetype` for `hb_ft_font_*`. Its source, licence and records are in that package, outside this grant and this inventory; consumers receive both packages.

Under `-Druntime`, the dispatch and patched translation are generated in the build cache from `zig/translate.h` and upstream headers. They are not fetched, installed or shipped.

This grant excludes upstream HarfBuzz, `src/ms-use/`, `test/shape/data/in-house/` and sibling FreeType. It does not discharge HarfBuzz's attribution obligations. Consumers shipping the static or shared HarfBuzz 14.5.1 library must retain notices in `COPYING`; `NOTICE.md` records their installed path, `share/licenses/harfbuzz/`, after `zig build`.
