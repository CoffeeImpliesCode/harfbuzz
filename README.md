# HarfBuzz 14.5.1 for Zig 0.16

This package wraps upstream HarfBuzz 14.5.1, an OpenType text-shaping library.
It exposes a Zig facade and native C library built from vendored sources.

## Source deviations

No upstream source is patched. The 932 vendored files are recorded in `UPSTREAM.sha256`. The vendored file set has not been compared with an extracted release tarball. Omitted upstream paths are `util/`, `perf/`, `test/subset/`, `test/fuzzing/`, `test/api/`, `test/vector/`, and two third-party corpus directories under `test/shape/data/`.

## Build deviations

- The build compiles upstream's `src/harfbuzz.cc` as one C++ translation unit with C++14, exceptions disabled, and RTTI disabled.
- It does not run Meson, CMake, Autotools, or a build-time download. It generates no `config.h`; target-specific macros replace it, while optional upstream backends remain disabled.
- FreeType is always included. The build compiles against the sibling `../freetype` source tree by default. It does not use a system FreeType, and `-Dfreetype=none` is refused.
- The subset library, world library, and `util/` programs are not built.
- Installation includes the static archive or shared object, 29 public headers, a relocatable `harfbuzz.pc`, and licence records.

## Support matrix

| Target | Boundary |
|---|---|
| `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` | Listed in the build's cross-target check. |
| `wasm32-wasi` | wasi-libc rejects `<setjmp.h>` reached through the required FreeType integration. |

## Consumption

Add the package to a consumer's `build.zig.zon`:

```zon
.dependencies = .{
    .harfbuzz = .{ .path = "../harfbuzz" },
},
```

The dependency, module, and artifact names are all `harfbuzz`: use `dep.module("harfbuzz")` for the Zig facade and `dep.artifact("harfbuzz")` for the native library.

Build options:

- `-Dlinkage=static|dynamic`: static is the default; dynamic builds a shared object with SONAME `libharfbuzz.so.0` and requires a target with a dynamic linker.
- `-Dsystem=true` or `-fsys=harfbuzz`: use an installed HarfBuzz and translate its headers.
- `-Druntime=true`: resolve entry points from an explicit runtime provider.
- `-Dfreetype=<path>`: select another FreeType source tree; the default is `../freetype`, and `none` is refused.
- `-Dtarget=<triple>` and `-Doptimize=<mode>`: select the target and optimization mode.

C consumers can use the installed `harfbuzz.pc`; it provides the include directory and `-lm` as a private library dependency.
