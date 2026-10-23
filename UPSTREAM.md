# UPSTREAM

| Field | Value |
|---|---|
| Project | HarfBuzz, OpenType text shaping engine |
| Upstream | https://github.com/harfbuzz/harfbuzz |
| Release | 14.5.1, published 2026-09-30 |
| Source | `harfbuzz-14.5.1.tar.xz`, GitHub release asset; 20,259,340 bytes |
| SHA-256 | `7e2fa4e8c7c98e8d8140671f5772542afaaa6acccfbd746506886b6d85f7f8d6` |
| Digest source | GitHub Releases API, read 2026-10-05 |
| Commit | No source commit recorded; imported from the release tarball. |
| Licence | Old MIT (`COPYING`) |
| Imported set | 932 files, 10,691,663 bytes; per-file digests in `UPSTREAM.sha256` |

## Imported files

| Path | Files | Contents |
|---|---:|---|
| `src/` | 575 | Library sources, amalgamation, data tables and upstream scripts. |
| `docs/` | 33 | Documentation sources. |
| `test/` | 310 | Licence, shaping runner, 215 fonts and 86 expectation files. |
| Upstream top level | 14 | `.clang-format`, `.editorconfig`, `AUTHORS`, `AVAR2-INSTANCING.md`, `BUILD.md`, `CODE_OF_AI_CONDUCT.md`, `CONFIG.md`, `COPYING`, `NEWS`, `README.upstream.md`, `RELEASING.md`, `SECURITY.md`, `TESTING.md`, `THANKS`. |

`README.upstream.md` is upstream's `README.md`, preserved byte for byte. Its digest is recorded under `README.upstream.md` in `UPSTREAM.sha256`.

## Not imported

`util/`, `perf/`, `test/subset/`, `test/fuzzing/`, `test/api/`, `test/vector/`, the two third-party corpus directories under `test/shape/data/`, top-level `meson.build`, `README.mingw.md` and `README.python.md`.
