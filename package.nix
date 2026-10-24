# SPDX-License-Identifier: MIT
# FORK-LICENSE.md covers this file. NOTICE.md maps the licences in `src/`, `docs/`, and `test/`.
# The build uses one FreeType source tree for `hb-ft.cc` headers and library.

{ lib
, stdenv
, fetchFromGitHub
, zig
, patchelf
  # `-Dlinkage` selects the output; an empty value uses build.zig's default.
, linkage ? "static"
, optimize ? "ReleaseSafe"
  # The FreeType source tree `src/hb-ft.cc` compiles against.
, freetypeSource ? fetchFromGitHub {
    owner = "CoffeeImpliesCode";
    repo = "freetype";
    rev = "47ca6f6bd095a48da89e1cd815808007c322d553";
    hash = "sha256-Bc85DHUCypmnwgVay717KA5Nr1xSITzCV6gRUzBQIJQ=";
  }
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

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

# `patchelf` rewrites ELF rpaths only, not Mach-O.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

# This derivation builds natively; Zig's cross-target matrix is separate.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "harfbuzz";
  version = "14.5.1";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # Run Zig in installPhase, not in separate configure or build phases.
  dontConfigure = true;
  dontBuild = true;

  # The C++ library needs the C++ runtime at link time.
  nativeBuildInputs = [ zig stdenv.cc.libcxx ] ++ lib.optional isElfTarget patchelf;

  # Build and link the same FreeType source tree used for its headers.
  propagatedBuildInputs = [ stdenv.cc.libc stdenv.cc.libcxx ];

  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches outside the unpacked source tree.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
    cp -r --no-preserve=mode ${freetypeSource} "$ZIG_GLOBAL_CACHE_DIR/p/freetype-2.14.3-8tKp3y0bMQHwVTbgOv-zJxJGTB71bBusVFzi2Lr1eFbD"

    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Remove TMPDIR rpaths rejected by Nix but keep store paths and `$ORIGIN`.
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

  # The install layout comes from `zig build install`.

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

      The compiled library is C++ and requires the C++ runtime. It builds
      against the pinned FreeType source tree preloaded into Zig's global cache.
    '';
    # The output includes MIT and OFL-1.1 files; NOTICE.md maps their paths.
    license = with lib.licenses; { mit = true; ofl = true; };
    platforms = lib.platforms.unix;
  };
}