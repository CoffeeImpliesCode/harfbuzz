# SPDX-License-Identifier: MIT

{ pkgs, ... }:

let
  # Use the compiler pinned by build.zig.zon.
  zig = pkgs.zig_0_16;

  harfbuzz = linkage: pkgs.callPackage ./package.nix { inherit linkage; };

  # Resolve this checkout from the Nix file without adding it to the store.
  # Tasks use this path so relative dependencies resolve from the source tree.
  sdk_root = builtins.toString ./.;

  # Sibling FreeType source tree selected by build.zig.
  freetype_root = builtins.toString ../freetype;

  # Keep Zig caches outside the source tree and respect caller-provided paths.
  zig_caches = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/harfbuzz/zig-local-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$TMPDIR/harfbuzz/zig-local-cache"
      fi
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/harfbuzz/zig-global-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/harfbuzz/zig-global-cache"
      fi
    fi
    if [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_LOCAL_CACHE_DIR"
    fi
    if [ -n "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    fi
  '';

  # Require an external local cache before build tasks run.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      echo "harfbuzz devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all" >&2
      echo "unset, so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # FreeType is required. Report a missing source tree before compiling.
  require_freetype = ''
    if [ ! -f "${freetype_root}/build.zig.zon" ]; then
      echo "harfbuzz devenv: the sibling FreeType source tree is not at" >&2
      echo "${freetype_root}." >&2
      echo "src/harfbuzz.cc includes hb-ft.cc unconditionally, so this package" >&2
      echo "compiles against that tree's include/ directory and links its archive." >&2
      echo "Check out the sibling beside this one, or pass -Dfreetype=<path>." >&2
      exit 1
    fi
  '';

  # Run each build task from this checkout root.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    ${require_freetype}
    cd "${sdk_root}" || exit 1
  '';

  # Shaping tests require `LC_ALL=C` because `hb_language_get_default()` reads
  # the locale (`test/shape/run-tests.py:19`).
  locale_c = ''
    export LC_ALL=C
  '';

  # Keep caller flags after the build defaults.
  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # Keep the consumer graph in a separate cache directory.
  consumer_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/consumer" "''$@"
  '';
in
{
  packages = [
    zig
    pkgs.gnumake
    pkgs.pkg-config
  ];

  assertions = [
    {
      assertion = zig.version == "0.16.0";
      message = "The HarfBuzz SDK requires Zig 0.16.0; nixpkgs resolved zig_0_16 to ${zig.version}";
    }
  ];

  # Interactive shells use the same cache defaults as task runs.
  enterShell = ''
    ${zig_caches}
    ${locale_c}
  '';

  # Output derivations stay lazy until requested.
  outputs.static = harfbuzz "static";
  outputs.shared = harfbuzz "dynamic";
  outputs.default = harfbuzz "static";

  tasks = {
    # Install outside the checkout to avoid writing into the source tree.
    "sdk:build" = {
      description = ''
        Compile the single C++ translation unit `src/harfbuzz.cc` against the
        sibling FreeType (default step) and install the delivery tree -- library,
        the 17 public headers, harfbuzz.pc and share/licenses/harfbuzz/ -- under
        the external cache rather than in this checkout.
      '';
      exec = ''
        ${in_sdk}
        ${locale_c}
        zig build --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/static" ${native_flags}
      '';
    };

    "sdk:build:shared" = {
      description = ''
        Compile the same translation unit as a shared object instead of an archive
        -- libharfbuzz.so.0.61451.61451 with SONAME libharfbuzz.so.0, from
        upstream's own libtool triple -- and install it under its own prefix.
      '';
      exec = ''
        ${in_sdk}
        ${locale_c}
        zig build -Dlinkage=dynamic --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic" ${native_flags}
      '';
    };

    "sdk:test" = {
      description = ''
        Run the behavioural tests in Debug. They compare HarfBuzz's output with
        lines recorded by upstream in test/shape/data/in-house/tests/, so the
        locale matters as much as the compiler.
      '';
      exec = ''
        ${in_sdk}
        ${locale_c}
        zig build test -Doptimize=Debug ${native_flags}
      '';
    };

    "sdk:test:release-safe" = {
      description = "Run the same behavioural tests in ReleaseSafe";
      exec = ''
        ${in_sdk}
        ${locale_c}
        zig build test -Doptimize=ReleaseSafe ${native_flags}
      '';
    };

    "sdk:smoke" = {
      description = ''
        Run the example program: it shapes three strings out of two of upstream's
        own fonts and prints the answers next to the recorded ones.
      '';
      exec = ''
        ${in_sdk}
        ${locale_c}
        zig build smoke ${native_flags}
      '';
    };

    "sdk:check" = {
      description = ''
        Compile the library, the facade, the tests and the example for all six
        cross targets without running any of them. One C++ translation unit plus
        FreeType's, per cell, so this is the slowest task here.
      '';
      exec = ''
        ${in_sdk}
        ${locale_c}
        zig build check ${native_flags}
      '';
    };

    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        ${locale_c}
        cd consumer
        zig build run ${consumer_flags}
      '';
    };

    "sdk:provenance" = {
      description = ''
        Check the 932 recorded upstream digests, the exact vendored file set, the
        upstream-only manifest, agreement between the two release-digest records,
        all three COPYING files and the four oracle fixtures. This is a
        source-integrity check, not a build gate.
      '';
      exec = ''
        cd "${sdk_root}" || exit 1
        bash tools/check-provenance.sh
      '';
    };

    # Nix outputs use store paths, not checkout directories.
    "sdk:package:static" = {
      description = ''
        Build the static Nix variant through devenv's own lazy output. No lock is
        needed by this path; `devenv build outputs.static` resolves the pinned
        input from devenv.lock, which the driver owns.
      '';
      exec = "devenv build outputs.static";
    };

    "sdk:package:shared" = {
      description = "Build the shared Nix variant through devenv's own lazy output";
      exec = "devenv build outputs.shared";
    };
  };
}