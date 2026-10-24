# Fork notes

## Source deviations

No upstream source files are patched. The fork adds its Zig facade under `zig/` and runtime loader under `runtime/`.

| Upstream file | Change | Reason |
|---|---|---|
| None | No source patches. | Keep the vendored source tree unchanged. |

## Build-graph deviations

- `build.zig` compiles upstream's `src/harfbuzz.cc` amalgamation as one C++ translation unit. It uses C++14, disables exceptions and RTTI, and does not run Meson, CMake, or Autotools.
- The build uses target-specific compile-line macros instead of generating `config.h`. It leaves optional backends disabled. It enables FreeType macros only when it compiles against the selected FreeType source tree.
- The required `freetype` package dependency is declared in `build.zig.zon`. Its source tree supplies headers, archive and Zig module in bundled, runtime and system HarfBuzz modes; `-Dfreetype=<path>` selects another source tree using that dependency's build recipe.
- The translation and installed include set cover the three upstream umbrellas and their 30 public headers, including `hb-script-list.h`. The subset library, world library, and `util/` programs are not built.
- RISC-V glibc translation receives the float-ABI macro derived from the target triple, matching the C compiler's ABI selection.
- Runtime mode generates dispatch from the target's translated headers. It routes HarfBuzz symbols through the provider and keeps `FT_*` declarations linked to FreeType. System mode links an installed HarfBuzz and translates its headers.
- Dynamic delivery uses upstream's SONAME, `libharfbuzz.so.0`. The build creates the relocatable `harfbuzz.pc` file and installs licence and provenance records.
- Zig 0.17 hides emulator opt-ins during configuration; the nested consumer step runs only native executables.
- Zig 0.17 exposes install-prefix and libc-runtime paths as lazy paths; the nested consumer build keeps its own prefix and omits optional libc-runtime forwarding.
- Zig 0.17 removes the nested build's global-cache option; the consumer step forwards `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LIB_DIR` through its environment.

## Known platform boundaries

- NetBSD: Aro cannot parse visibility `_Pragma` directives expanded by libc headers.
- 32-bit OpenBSD: Aro's `stddef.h` definition of `size_t` conflicts with OpenBSD's header definition.
- OpenBSD MIPS64: Aro does not define the endian macros required by the platform headers.
- 32-bit Windows: the bundled `malloc.h` uses `_ALLOCA_S_MARKER_SIZE` without defining it for that target.
- MIPS64 Linux: the amalgamated object exceeds the range of `R_MIPS_CALL16` relocations.
- WASI: wasi-libc rejects `<setjmp.h>` without WebAssembly exception-handling support. The required FreeType integration includes this header, so the HarfBuzz build cannot remove the boundary without dropping that integration.
