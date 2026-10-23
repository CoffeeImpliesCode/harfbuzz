# Changelog

- `NOTICE.md` now lists upstream copyright holders verbatim and records licence scopes by path.
- `riscv64-linux-gnu` translation defines the target floating-point ABI macro required by libc headers.
- `wasm32-wasi` remains unsupported because the required FreeType `setjmp` path needs exception handling.
- `Font.create` uses upstream's `hb_font_create`, checks its empty-font sentinel and sets OpenType functions.
- The installed header set now includes the complete OpenType translation closure.
- `shape` and `Buffer.serializeText` accept `Font` and `FtFont`; `hb.freetype` is public.
- `FtFont.create` accepts the upstream destroy callback; `createReferenced` uses a referenced `FT_Face`.
- `Blob.fromFile` reports `FileNotLoaded`, `Face.create` reports `NoFace`, and `OutOfMemory` is limited to observable allocation failures.
- `Blob.fromBytes` and `Buffer.create` no longer test non-nullable constructor results.
- HarfBuzz 14.5.1 is packaged as the `harfbuzz` module and `libharfbuzz` artifact, with static, dynamic, runtime-provider and system-library modes.
- The package uses the sibling FreeType source tree; `-Dfreetype=none` is rejected.
- Package paths no longer name the absent `README.mingw.md` or duplicate `README.md`.
