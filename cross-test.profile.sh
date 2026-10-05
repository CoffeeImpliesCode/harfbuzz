# SPDX-License-Identifier: MIT
# See FORK-LICENSE.md for what that identifier covers.
#
# cross-test settings profile for the HarfBuzz 14.5.1 Zig SDK.
#
# `cross-test` looks for this file at the root of the project it is run from
# (or names it with --profile; --no-profile ignores it). It is trusted Bash that
# the harness `source`s, so this file is *settings only*: ordinary variable
# assignments and nothing else. No command runs, no compiler is probed, and no
# path in here names a host.
#
# There is deliberately no CROSS_MATRIX. The published 53-platform Zig 0.16
# Tier 1/2 table is the matrix this package is checked against, and a matrix
# named here would replace it. There is no TARGETS array either, for the same
# reason: a subset selected here would narrow the run rather than add to it.
# Both belong on the command line, where --targets selects from the active
# matrix and never adds to it.
#
# CROSS_BUILD_STEP stays the standard `test` step, which is what this profile
# states explicitly. There are no `cross_build_command` / `cross_artifact`
# hooks here, so the harness keeps its standard Zig-build mode and runs
# `zig build test -Dtarget=TARGET` per target with a fresh cache. `test` is a
# Run step over the test artifact built for the target it was asked for
# (`build.zig:774-784`), so a host target runs, a foreign target runs only
# where the host supplies an executor for it (QEMU user mode, Wine, wasmtime),
# and a foreign target with no executor is the harness's cell to report as
# build-only coverage -- compiled, never executed, and never counted as a pass.
# The compile-only sweep is a different step: `check` builds one test artifact
# and one example per target and runs nothing (`build.zig:789-799`). This
# profile does not select it, and does not narrow `test` to a subset.
#
# What one cell compiles. HarfBuzz itself is **one** translation unit,
# `src/harfbuzz.cc`. Its 69 `#include` lines are 69 `.cc` files, every one of
# which resolves against `src/`, and they reach the headers, the generated
# ragel sources behind the Indic and Khmer shapers and the Unicode tables
# behind them; `src/` as a whole carries 145 `.cc` files and 289 `.hh` headers,
# of which this build compiles one object. `src/harfbuzz.cc:1` opens
# `"OT/Var/VARC/VARC.cc"`, which is why the source directory is also the
# include path. Beside that object a cell builds the sibling FreeType archive
# -- 38 sources across that package's `base_sources`, `module_sources` and
# `base_extensions` lists -- and, when `-Druntime=true` reaches the cell,
# `runtime/sync.c` compiled with `-DRT_SYNC_PREFIX=harfbuzz_rt` into the
# generated dispatch (`runtime/graph.zig:544-548`).
#
# The generated inputs a cell gets are the ones this package owns: the
# translate-c output of `zig/translate.h`, which includes `<hb.h>` and
# `<hb-ft.h>` and through the latter FreeType's `<ft2build.h>`, plus the ELF
# version script `build.zig:413-425` writes for a shared object (`hb_*` global,
# everything else local, under the version node `HARFBUZZ_14`). There is no
# `config.h`: `HAVE_CONFIG_H` is never defined, so the generated header upstream
# includes under that macro (`src/hb-config.hh:34-36`) is never reached, and
# the configuration arrives as macros resolved from the target being built.
# There is no meson, no CMake and no autotools step, no build-time download and
# no `gen-hb-version.py` run: `src/hb-version.h` is the release's own file.
#
# Four build jobs. The dominant cost in a cell is one large C++ translation
# unit, and no amount of parallelism inside a cell shortens a single one; what
# jobs buy here is the sibling's sources and the translate step running beside
# it. The two timeouts are unchanged from the profile this one replaced, and
# they are not a measurement: nothing in this package has been timed, so they
# are the numbers to record a run against, not a claim about how long a cell
# takes.
#
# Nothing here narrows the gate to what is expected to work. Which platforms
# HarfBuzz itself supports is upstream's statement, not this profile's: every
# optional backend (glib, ICU, graphite2, cairo, coretext, directwrite,
# uniscribe, gdi, wasm, png, zlib) is left undefined, which is upstream's "all
# optional dependencies off" configuration, and the sibling FreeType brings its
# own platform surface with it. `build.zig` refuses no target:
# `refused_check_targets` is empty and `checkMatrixPartition` panics if the two
# lists ever disagree. A cell that fails is a fact to record and diagnose; it is
# not a reason to drop the cell, sample the tests or remap Debug to an
# optimized mode to make it pass.

CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=3600
CROSS_TIMEOUT=1800