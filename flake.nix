# SPDX-License-Identifier: MIT

{
  description = "HarfBuzz 14.5.1, the OpenType text shaping engine, packaged for Zig 0.17";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";
  };

  outputs = { self, nixpkgs }:
    let
      # Nix builds use these systems. package.nix rejects cross builds.
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
            zig = pkgs.zig_0_17;
          };
        in
        {
          static = mk "static";

          shared = mk "dynamic";

          default = mk "static";
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          # Upstream's shaping runner sets `LC_ALL=C` because
          # `hb_language_get_default()` reads the locale (`test/shape/run-tests.py:19`).
          packages = [ pkgs.zig_0_17 pkgs.gnumake pkgs.pkg-config ];
          LC_ALL = "C";
        };
      });
    };
}