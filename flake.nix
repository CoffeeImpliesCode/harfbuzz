# Flake interface for the HarfBuzz SDK.
#
# Portable counterpart to devenv.nix. Both call ./package.nix, so the package a
# flake builds and the package devenv builds are the same derivation; this file
# only decides which systems are exposed and which variants of that derivation
# they get.
#
# Canonical development is `devenv shell` (see devenv.nix and .envrc). This
# flake exists so the SDK can be built and consumed off this host. `nix develop`
# here is parity, not the canonical entry point, and it deliberately does not
# build the SDK: entering a shell must not require building a library.
#
# One thing to know before evaluating this: package.nix compiles `src/hb-ft.cc`
# against a FreeType *source tree*, and its default is the sibling checkout at
# `../freetype`. A path outside the flake's own directory needs an impure
# evaluation, so the commands below carry `--impure`. That is deliberate: the
# alternative would be nixpkgs' installed FreeType, whose headers live under
# `include/freetype2/` rather than the source layout `hb-ft.h` includes from.
# See the header of package.nix.
#
# The nixpkgs revision named in `inputs` below is the pin the rest of this
# workspace carries, read out of the sibling forks rather than invented here.
# flake.lock pins it, and the driver owns that file: it is deliberately absent
# here, and `build.zig.zon .paths` does not name it either, so a fetched package
# never hashes a missing entry.
#
# SPDX-License-Identifier: MIT

{
  description = "HarfBuzz 14.5.1, the OpenType text shaping engine, packaged for Zig 0.16";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
  };

  outputs = { self, nixpkgs }:
    let
      # HarfBuzz's own delivery is `libharfbuzz.a` or a real shared object, and
      # `src/harfbuzz.cc` reaches `<pthread.h>`, `<unistd.h>` and `<sys/mman.h>`
      # on every Unix it is built for. These are the systems package.nix builds
      # on, which is a property of that derivation (it refuses a cross build)
      # and not a claim that HarfBuzz cannot be built for Windows -- `zig build
      # check` walks `x86_64-windows-gnu`, and the compile-only matrix there is a
      # separate gate with its own receipt.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "x86_64-freebsd"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        let
          mk = linkage: pkgs.callPackage ./package.nix {
            inherit linkage;
            zig = pkgs.zig_0_16;
          };
        in
        {
          # The default delivery is `static`, and it is a fork decision rather
          # than upstream's: `build.zig` chooses it.
          static = mk "static";

          # A separate variant of the same derivation, not a second SDK.
          # "shared" names the artefact; the flag it passes is Zig's own
          # `-Dlinkage=dynamic`, which produces `libharfbuzz.so.0.61451.61451`
          # with SONAME `libharfbuzz.so.0`, from upstream's own libtool triple
          # `60000 + major*100 + minor*10 + micro`.
          shared = mk "dynamic";

          default = mk "static";
        });

      # Parity only. The canonical development environment is devenv.nix. The
      # shell here carries the tools the gates in `.github/workflows/verify.yml`
      # need and nothing else: the SDK is not a package in this shell, because
      # `zig build` is how it is built and entering a shell must not do that.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          # `LC_ALL=C` is not cosmetic here. Upstream's own shaping-test runner
          # sets it (`test/shape/run-tests.py:19`) because
          # `hb_language_get_default()` reads the locale, and the recorded
          # expectations this package's tests compare against were taken under
          # "C".
          packages = [ pkgs.zig_0_16 pkgs.gnumake pkgs.pkg-config ];
          LC_ALL = "C";
        };
      });
    };
}