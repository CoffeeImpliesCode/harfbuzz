# Source-only package derivation for the HarfBuzz SDK.
#
# One file, consumed by both flake.nix and devenv.nix, so the two entry points
# cannot describe different packages. It builds nothing but this repository: the
# native source is upstream's `src/`, which is the complete HarfBuzz 14.5.1
# closure `src/harfbuzz.cc` includes in one translation unit, and build.zig owns
# every compile flag, the SONAME, the generated pkg-config file and the whole
# installed layout. Nothing here restates a C or C++ flag, fetches a tarball,
# runs meson, or installs an artifact of its own. The one edit it makes is the
# rpath of the ELF files the build installed: Zig records its own build cache
# there, and that directory does not exist once a binary is installed.
#
# ## The sibling FreeType, and why this derivation has an argument for it
#
# `src/harfbuzz.cc` includes `hb-ft.cc` unconditionally, and that file needs
# FreeType's headers and FreeType's code. So this package compiles against a
# FreeType *source tree*, not against an installed FreeType: `build.zig` puts
# `<path>/include` on the compile line, which is the layout FreeType's own
# source tree has and the one `hb-ft.h:34`'s `#include <ft2build.h>` resolves
# against.
#
# nixpkgs' `freetype` is deliberately **not** offered as the source of those
# headers. Its development output installs them under `include/freetype2/`, and
# mixing one tree's headers with another tree's library is the silent mismatch
# this workspace's system-integration rule is about. So `freetypeSource` is a
# path to a FreeType source tree, and the default is the sibling checkout beside
# this one.
#
# The default is a `builtins.path` on `../freetype`, which means evaluating this
# file needs a path outside the flake's own directory and therefore an impure
# evaluation (`nix build --impure .#static`, `nix develop --impure`, or a
# non-flake `nix-build`). That is the honest price of the sibling rule: a pure
# flake cannot reach a directory that is not its own source, and the alternative
# - silently linking nixpkgs' FreeType - would break the one linkage decision
# this package documents. A caller who has a different FreeType source tree
# passes `freetypeSource` and gets that one instead.
#
# No lock file is written here. `flake.lock` is this fork's own input; `devenv.lock`
# belongs to the driver.
#
# SPDX-License-Identifier: MIT
# See FORK-LICENSE.md for what that identifier covers, and NOTICE.md for the
# terms that cover everything in src/, docs/ and test/ -- which are not all MIT:
# src/ms-use/ is MIT with Microsoft's holder and the shaping corpus under test/
# is SIL OFL-1.1.

{ lib
, stdenv
, zig
, patchelf
, # Zig's own `std.builtin.LinkMode` spelling, passed straight through as
  # `-Dlinkage`. "static" and "dynamic" are two variants of one derivation, and
  # `""` passes nothing at all so the SDK's own default policy runs unchanged.
  # The default is this fork's choice, and `outputs.static` in flake.nix says so
  # too; upstream ships both kinds.
, linkage ? "static"
, optimize ? "ReleaseSafe"
, # The FreeType source tree `src/hb-ft.cc` compiles against. See the header.
, freetypeSource ? builtins.path { path = ../freetype; name = "freetype-sibling"; }
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

# Everything except build outputs, version control and developer-tool state.
# Filtering by directory name rather than by an allow list means a file added
# here later is packaged without editing this file, while `.zig-cache/`,
# `zig-out/`, `.devenv/`, `.direnv/` and `result` stay out of a published output
# at any depth, including under consumer/.
#
# The upstream manuals, the shaping corpus, upstream's own build files and
# upstream's README are deliberately kept: they are upstream material with
# digests in UPSTREAM.sha256, and the audit surface is the whole upstream tree.
# `tools/check-provenance.sh` runs against the working tree and not against this
# filtered copy, so nothing here can narrow what that gate sees.
src = lib.cleanSourceWith {
  src = ./.;
  filter = path: _type:
    let name = builtins.baseNameOf (toString path); in
    !(lib.elem name [
      ".git"
      ".direnv"
      ".devenv"
      ".zig-cache"
      "zig-cache"
      "zig-pkg"
      "zig-out"
      "result"
    ]);
};

# patchelf rewrites ELF rpaths and does not read Mach-O, so the rpath
# normalisation in the install phase exists for ELF targets only, and the tool is
# a build input exactly where that code runs.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# These packages build for the compiler's own native target. A cross build here
# would mean hand-building a libc-suffixed triple that has to track nixpkgs, so
# this derivation refuses one instead of silently producing a host-architecture
# library under a foreign name. The comparison is against stdenv's own
# platforms, which are pure values; `builtins.currentSystem` is not evaluable
# in a sandbox and is not used. A remote builder is unaffected: this compares
# build against host, not against any particular machine.
#
# That refusal does not narrow the SDK's own cross-target gate: `zig build check`
# walks `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`,
# `x86_64-windows-gnu`, `riscv64-linux-gnu` and `wasm32-wasi` from a source tree
# with no Nix involvement at all, and the driver's cross-test matrix runs the
# `test` step over the published 53 platforms. A limitation of *this packaging
# route* is recorded as such and is not a claim about the library.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "harfbuzz";
  version = "14.5.1";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # The real work is one `zig build install` in installPhase below. Disabling
  # configure and build phases keeps the Zig setup hook from running a first,
  # differently-flagged build of its own; `dontInstall` is deliberately NOT set,
  # because that is what would disable the real install phase.
  dontConfigure = true;
  dontBuild = true;

  # The C++ standard library is a build input, not an optional extra: the whole
  # library is one C++ translation unit, so anything that links this package's
  # archive needs the C++ runtime as well as libc. `build.zig` sets
  # `link_libcpp` on the *library* module for that reason.
  nativeBuildInputs = [ zig stdenv.cc.libcxx ] ++ lib.optional isElfTarget patchelf;

  # The C library and the C++ runtime are what a dependent inherits from this
  # package. FreeType is deliberately absent from this list: it is passed as a
  # source tree through `-Dfreetype`, because `build.zig` compiles against its
  # headers and links this graph's own build of the archive rather than a
  # pre-built one, and declaring an installed FreeType here would describe a
  # linkage this package does not have.
  propagatedBuildInputs = [ stdenv.cc.libc stdenv.cc.libcxx ];

  # The driver owns every gate for this SDK, and a Nix build is not a
  # verification receipt. No check phase is declared here rather than a check
  # phase that runs something smaller than the real gates; the commands that do
  # verify this package are in README.zig.md and CHANGELOG.md.
  doCheck = false;
  dontUseZigCheck = true;

  # The FreeType source tree, resolved to a store path so the build sees the
  # same tree on every machine and never the caller's working directory.
  freetypeTree = freetypeSource;

  installPhase = ''
    runHook preInstall

    # Both caches go under the Nix-provided TMPDIR, outside the unpacked source
    # tree, so a build cannot write into $src and so two parallel derivations
    # cannot share state. Any caller-supplied cache variables are left alone:
    # they are the caller's scratch, not this file's to clear.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns the source list, the C and C++ flags, the SONAME, the
    # generated pkg-config file and every installed path. Declaring any of them
    # here as well would create a second place where they can disagree with the
    # build graph.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      -Dfreetype=${freetypeTree} \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Zig records the build cache in the rpath of anything that links a dynamic
    # artifact it has just built, so an installed binary names a directory that
    # is gone, and Nix rejects an installed file that names its build directory
    # at all. Both Zig caches above are under $TMPDIR, so dropping those entries
    # and no other removes it: the $ORIGIN/../lib build.zig adds, and every
    # store path a real dependency needs, stay. Symlinks are resolved first so a
    # soname link is rewritten through to the object and never replaced by a copy
    # of it. The loop's `bin/*` glob covers nothing today -- this package
    # installs no program -- and is kept so a future consumer binary in the same
    # tree is covered by the same pass rather than by a new one.
    ${lib.optionalString isElfTarget ''
      for elf in "$out"/bin/* "$out"/lib/*.so*; do
        [ -f "$elf" ] || continue
        elf=$(readlink -f "$elf")
        rpath=$(patchelf --print-rpath "$elf") || rpath=""
        kept=""
        rest=$rpath
        while [ -n "$rest" ]; do
          entry="''${rest%%:*}"
          case "$entry" in
            "$TMPDIR"/*) ;;
            *) if [ -z "$kept" ]; then kept=$entry; else kept=$kept:$entry; fi ;;
          esac
          if [ "$entry" = "$rest" ]; then rest=""; else rest="''${rest#*:}"; fi
        done
        [ "$kept" = "$rpath" ] || patchelf --set-rpath "$kept" "$elf"
      done
    ''}

    runHook postInstall
  '';

  # The layout this derivation produces is the build graph's, not this file's:
  # $out/lib/libharfbuzz.a (or libharfbuzz.so.0.61451.61451 with
  # libharfbuzz.so.0 and libharfbuzz.so beside it), the 17 public headers
  # installed flat under $out/include, $out/lib/pkgconfig/harfbuzz.pc, and
  # $out/share/licenses/harfbuzz/ with upstream's grant, the corpus licence and
  # this fork's records. Both variants keep it; only the artifact kind differs.
  # Nothing is copied or generated by hand here, so `zig build install --prefix
  # $out` and `nix build` produce one layout by construction rather than two
  # that have to be kept in agreement.

  enableParallelBuilding = true;

  meta = {
    description = "HarfBuzz 14.5.1, the OpenType text shaping engine, built from the official release sources";
    longDescription = ''
      The complete HarfBuzz 14.5.1 release source -- the library, its public
      headers, the platform shapers, the OpenType table readers, the Unicode
      data and the shaping test corpus -- imported whole and compiled with Zig
      from upstream's own single-translation-unit amalgamation, with no meson, no
      CMake and no build-time download. Ships the library, the public headers, a
      pkg-config file and every licence the tree contains.

      The compiled library is C++ and requires the C++ runtime. It is built
      against the sibling FreeType *source tree* rather than an installed
      FreeType; see the header of this file for why that is an argument and not
      a nixpkgs dependency.
    '';
    # The compiled library is MIT (the "Old MIT" licence, `COPYING`). The
    # *shipped tree* is not one licence, and this attribute is where a consumer
    # looks, so it is the multiple-licence attribute set rather than the single
    # id that describes only the artifact: MIT covers HarfBuzz's own material
    # and src/ms-use/, and OFL-1.1 covers the shaping corpus under test/.
    # NOTICE.md is the per-file inventory.
    license = with lib.licenses; { mit = true; ofl = true; };
    platforms = lib.platforms.unix;
  };
}