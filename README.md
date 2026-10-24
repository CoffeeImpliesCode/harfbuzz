# HarfBuzz 14.5.1 for Zig 0.17.0

This package wraps upstream HarfBuzz 14.5.1, an OpenType text-shaping library.
It exposes a Zig facade and native C library built from vendored sources.

## Source deviations

No upstream source is patched. The 932 vendored files are recorded in `UPSTREAM.sha256`. The vendored file set has not been compared with an extracted release tarball. Omitted upstream paths are `util/`, `perf/`, `test/subset/`, `test/fuzzing/`, `test/api/`, `test/vector/`, and two third-party corpus directories under `test/shape/data/`.

## Build deviations

- The build compiles upstream's `src/harfbuzz.cc` as one C++ translation unit with C++14, exceptions disabled, and RTTI disabled.
- It does not run Meson, CMake, or Autotools. It generates no `config.h`; target-specific macros replace it, while optional upstream backends remain disabled.
- FreeType is fetched automatically through the pinned GitHub URL in `build.zig.zon`. It does not use a system FreeType, and `-Dfreetype=none` is refused.
- The subset library, world library, and `util/` programs are not built.
- Installation includes the static archive or shared object, 30 public headers, a relocatable `harfbuzz.pc`, and licence records.

## Support matrix

| Target | Boundary |
|---|---|
| `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` | Listed in the build's cross-target check. |
| `wasm32-wasi` | Unsupported and excluded from the automatic cross-target check: wasi-libc rejects `<setjmp.h>` reached through the required FreeType integration. Dynamic linkage also requires a dynamic linker, which WASI lacks. |

## Consumption

Fetch the package and add its pinned URL and hash to the consumer's `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/CoffeeImpliesCode/harfbuzz#v14.5.1
```

The dependency, module, and artifact names are all `harfbuzz`: use `dep.module("harfbuzz")` for the Zig facade and `dep.artifact("harfbuzz")` for the native library.
Nix builds preload the pinned FreeType source into Zig's global cache.

Build options:

- `-Dlinkage=static|dynamic`: static is the default; dynamic builds a shared object with SONAME `libharfbuzz.so.0` and requires a target with a dynamic linker.
- `-Dsystem=true` or `-fsys=harfbuzz`: use an installed HarfBuzz and translate its headers.
- `-Druntime=true`: resolve HarfBuzz entry points from an explicit runtime provider. FreeType declarations from `hb-ft.h` remain linked to FreeType.
- `-Dfreetype=<path>`: select another FreeType source tree for headers, archive and Zig module. Paths are absolute or relative to the HarfBuzz package root; the default is the `freetype` package dependency. Overrides use that dependency's build recipe and require the same source and Zig-wrapper layout. `none` is refused.
- `-Dtarget=<triple>` and `-Doptimize=<mode>`: select the target and optimization mode.

`zig build consumer -Druntime=true` forwards `HARFBUZZ_PROVIDER` (provider path) and `HARFBUZZ_PROVIDER_SYSTEM` (system soname) to the nested consumer build. You can also pass `-- --provider <absolute path>` or `-- --provider-system <soname>`.

C consumers can use the installed `harfbuzz.pc`; it provides the include directory and `-lm` as a private library dependency.
