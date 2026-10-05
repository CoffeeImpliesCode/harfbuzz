# Canonical development environment for the HarfBuzz SDK.
#
# This is the environment a contributor should be in. It installs tools and
# nothing else: `packages` deliberately does not contain the SDK's own package,
# because entering a shell must not require building a library to have it.
#
# The package itself is defined once, in ./package.nix, and shared with
# flake.nix, so the two entry points cannot describe different builds. `outputs`
# below name that same derivation lazily -- they are attributes, not builds, so
# nothing is realised until `devenv build outputs.static` or
# `devenv build outputs.shared` is actually run.
#
# devenv.lock is not written here: the driver owns locks, and `build.zig.zon`
# `.paths` deliberately does not name it either.
#
# Three facts about the environment a task actually runs in are handled once, in
# the `let` below, and every task uses them: devenv materialises a task as a
# generated shell program that inherits the caller's working directory; `zig
# build` defaults both its local cache and its install prefix to directories
# inside the working tree; and `build.zig.zon` resolves the sibling FreeType as a
# relative path, so a task that runs anywhere but this checkout has no FreeType
# to compile against. None of that is visible from a task body, and all three
# decide whether a task can find this checkout or must write into it.
#
# SPDX-License-Identifier: MIT

{ pkgs, ... }:

let
  # Kept as a value rather than inlined, so the version assertion below and the
  # package list cannot disagree about which compiler is meant.
  zig = pkgs.zig_0_16;

  harfbuzz = linkage: pkgs.callPackage ./package.nix { inherit linkage; };

  # The directory this module was evaluated against. `./.` is a path literal
  # resolved relative to the file that names it, so this is this checkout and
  # never the directory `devenv` was started from. `builtins.toString` converts
  # that path instead of interpolating it into a string, so what the tasks below
  # receive is this working tree: a plain `${./.}` would carry the path's store
  # context and copy this whole SDK into the read-only store, and that copy is
  # not the tree `build.zig` and `UPSTREAM.sha256` describe. No host path is
  # written in this file -- the value is read out of the module's own location,
  # so it tracks wherever this checkout is.
  sdk_root = builtins.toString ./.;

  # The sibling FreeType, as `build.zig.zon` resolves it: one directory up from
  # this package. Named here so the precondition is one fact rather than three
  # tasks each spelling it differently.
  freetype_root = builtins.toString ../freetype;

  # Where a task's build output goes. `zig build` keeps its local cache in
  # `.zig-cache/` and installs into `zig-out/`, both relative to the working
  # directory, and this checkout is a working tree on a volume mount that has to
  # stay byte-identical. A directory the caller exported always wins and is never
  # overwritten; otherwise it comes from `XDG_CACHE_HOME`, then `TMPDIR`, and this
  # file names no location of its own.
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

  # The same rule with the one extra requirement a task has: it must be able to
  # name that directory. An environment with nowhere outside the checkout to
  # write stops here, with the reason, instead of filling the tree.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      echo "harfbuzz devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all" >&2
      echo "unset, so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # The sibling FreeType is a hard dependency of every build here: `src/hb-ft.cc`
  # is inside the single translation unit, and `build.zig` compiles it against
  # the sibling's source include root. A task that cannot see the sibling would
  # fail with a compile error about `<ft2build.h>`, which says nothing about the
  # cause. This check says the cause.
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

  # What every task below starts with. devenv materialises a task as a generated
  # shell program that inherits the caller's working directory, so a task entered
  # from a scratch project directory would otherwise run its body where there is
  # no `build.zig` and no `UPSTREAM.sha256`. A per-task `cwd` would not reach
  # that generated program.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    ${require_freetype}
    cd "${sdk_root}" || exit 1
  '';

  # `LC_ALL=C` is exported by every task, not set once in `packages`: it decides
  # an answer. Upstream's own shaping-test runner sets it
  # (`test/shape/run-tests.py:19`) because `hb_language_get_default()` reads the
  # locale, and the recorded expectations in `test/shape/data/in-house/tests/`
  # were taken under "C". Under another locale the OpenType language system a
  # shaper selects can differ, and the oracle comparison would fail for a reason
  # that has nothing to do with this package.
  locale_c = ''
    export LC_ALL=C
  '';

  # The flags every native build here shares: this workspace's eight jobs,
  # fixed, then the printed step list and a local cache outside the checkout.
  # `"''$@"` stays after them, so whatever a caller appended is still passed on
  # and still comes later.
  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # The consumer package is a second build graph with its own manifest, so it
  # gets its own cache directory rather than sharing one with the library.
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

  # The shell hook exports the same two directories the tasks use, by the same
  # rule, so an ordinary `devenv shell` session also leaves this checkout alone.
  # A value the caller exported is kept exactly as it is, and with nothing to
  # choose from the hook chooses nothing: only a task, which has to name the
  # directory, refuses to run.
  enterShell = ''
    ${zig_caches}
    ${locale_c}
  '';

  # Lazy on purpose: naming a derivation realises nothing, and entering the shell
  # does not build either variant. `devenv build outputs.<name>` is the real
  # packaging route.
  outputs.static = harfbuzz "static";
  outputs.shared = harfbuzz "dynamic";
  outputs.default = harfbuzz "static";

  tasks = {
    # Delivery output goes outside the checkout. The default step installs, and
    # `zig-out/` is a directory in the working tree, so the install prefix is
    # named here; the pkg-config file and the rpath the build normalises are
    # prefix-relative, so the installed tree is the same shape wherever it lands.
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

    # These run or compile; none of them installs, so each needs only the
    # external cache directory.
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

    # The dependent package in `consumer/`, built and run as itself. It reaches
    # the library through the relative path dependency in its own manifest, so
    # this is the proof that `dep.module("harfbuzz")` works from outside this
    # package -- and, through it, that the sibling FreeType is linked and
    # answering: the program reads an `FT_Face` back through FreeType's own face
    # loader and shapes the same line twice.
    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        ${locale_c}
        cd consumer
        zig build run ${consumer_flags}
      '';
    };

    # The checker runs against this checkout's own bytes and file set, which is
    # what `UPSTREAM.sha256` describes, so it is entered here rather than in the
    # directory the task happened to start in. It needs no compiler, no Zig cache
    # and no build output, which is why it does not call `in_sdk` for the cache
    # part and only changes directory.
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

    # These two are the only bodies that do not enter this checkout, and that is
    # deliberate. They run a nested `devenv build`, which reads the project the
    # caller entered and whose delivery output is a store path, never a directory
    # in this tree.
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