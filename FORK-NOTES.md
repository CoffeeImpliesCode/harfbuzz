# Fork notes

## Source deviations

No upstream source files are patched. The fork adds its Zig facade under `zig/` and runtime loader under `runtime/`.

| Upstream file | Change | Reason |
|---|---|---|
| None | No source patches. | Keep the vendored source tree unchanged. |

## Build-graph deviations

- `build.zig` compiles upstream's `src/harfbuzz.cc` amalgamation as one C++ translation unit. It uses C++14, disables exceptions and RTTI, and does not run Meson, CMake, Autotools, or a download.
- The build uses target-specific compile-line macros instead of generating `config.h`. It leaves optional backends disabled. It enables FreeType macros only when it compiles against the selected FreeType source tree.
- FreeType is a required sibling source dependency at `../freetype` by default. `-Dfreetype=<path>` selects another source tree. `-Dfreetype=none` is refused because the facade includes the FreeType API.
- The translation and installed include set cover the three upstream umbrellas and their 29 public headers. The subset library, world library, and `util/` programs are not built.
- RISC-V glibc translation receives the float-ABI macro derived from the target triple, matching the C compiler's ABI selection.
- Runtime mode generates dispatch from the target's translated headers. System mode links an installed HarfBuzz and translates its headers.
- Dynamic delivery uses upstream's SONAME, `libharfbuzz.so.0`. The build creates the relocatable `harfbuzz.pc` file and installs licence and provenance records.

## Known platform boundaries

- NetBSD: Aro cannot parse visibility `_Pragma` directives expanded by libc headers.
- 32-bit OpenBSD: Aro's `stddef.h` definition of `size_t` conflicts with OpenBSD's header definition.
- OpenBSD MIPS64: Aro does not define the endian macros required by the platform headers.
- 32-bit Windows: the bundled `malloc.h` uses `_ALLOCA_S_MARKER_SIZE` without defining it for that target.
- MIPS64 Linux: the amalgamated object exceeds the range of `R_MIPS_CALL16` relocations.
- WASI: wasi-libc rejects `<setjmp.h>` without WebAssembly exception-handling support. The required FreeType integration includes this header, so the HarfBuzz build cannot remove the boundary without dropping that integration.
