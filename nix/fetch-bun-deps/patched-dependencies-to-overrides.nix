{
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mkOption types;
in
{
  options.perSystem = mkPerSystemOption {
    options.fetchBunDeps.patchedDependenciesToOverrides = mkOption {
      description = ''
        Helper function that converts a `patchedDependencies` attribute set
        into a valid `overrides` set for use with `fetchBunDeps`.

        # Example

        ```nix
        let
          packageJsonPath = ./package.json;
          packageJsonContents = lib.importJSON packageJsonPath;
          patchedDependencies = lib.mapAttrs (_: path: ./. + "/''${path}") (
            packageJsonContents.patchedDependencies or { }
          );
          patchOverrides = bun2nix.patchedDependenciesToOverrides {
            inherit patchedDependencies;
          };
        in
        bun2nix.fetchBunDeps {
          bunNix = ./bun.nix;
          overrides = patchOverrides;
        }
        ```
      '';
      type = types.functionTo types.attrs;
    };
  };

  config.perSystem =
    { pkgs, ... }:
    {
      fetchBunDeps.patchedDependenciesToOverrides =
        {
          patchedDependencies ? { },
        }:
        lib.mapAttrs (
          name: patchFile: pkg:
          pkgs.runCommandLocal "patched-${name}" { nativeBuildInputs = [ pkgs.patch ]; } ''
            mkdir $out
            cp -r ${pkg}/. $out

            echo "Applying patch for ${name}..."
            patch -p1 -d $out < ${patchFile}
          ''
        ) patchedDependencies;
    };
}
