{
  description = "Flake for development workflows.";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    rainix.url = "github:rainlanguage/rainix";
    rain.url = "github:rainlanguage/rain.cli";
    # rain.cli pulls its own rainix; make it follow ours so the lock has a
    # single rainix (and one rust toolchain / nixpkgs) instead of two revs.
    rain.inputs.rainix.follows = "rainix";
  };

  outputs =
    {
      flake-utils,
      rainix,
      rain,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = rainix.pkgs.${system};
      in
      rec {
        packages = {
          # `script/build-meta.sh` runs `rain meta build` out of this.
          rain-cli = rain.defaultPackage.${system};
        }
        // rainix.packages.${system};

        devShells.default = pkgs.mkShell {
          inherit (rainix.devShells.${system}.default) shellHook;
          packages = [
            packages.rain-cli
            pkgs.gh
          ];
          inputsFrom = [ rainix.devShells.${system}.default ];
        };
      }
    );
}
