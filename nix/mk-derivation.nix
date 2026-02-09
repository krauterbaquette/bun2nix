{ lib, flake-parts-lib, ... }:
let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mkOption types;
in
{
  options.perSystem = mkPerSystemOption {
    options.mkDerivation.function = mkOption {
      description = ''
        Bun `mkDerivation` function.

        Similar to `stdenv.mkDerivation` but comes with
        additional specifics for creating bun packages.

        A lot of the implementation details exist inside
        the setup hook consumed by this function. This function's
        main role is to provide a more idiomatic interface for simple
        builds while the hook serves anything more custom.
      '';
      type = types.functionTo types.package;
    };
  };

  config.perSystem =
    { config, pkgs, ... }:
    {
      mkDerivation.function = lib.extendMkDerivation {
        constructDrv = pkgs.stdenv.mkDerivation;

        extendDrvArgs =
          _finalAttrs:
          {
            packageJson ? null,
            dontPatchShebangs ? false,
            nativeBuildInputs ? [ ],
            # Bun binaries built by this derivation become broken by the default fixupPhase
            dontFixup ? !(args ? buildPhase),
            bunCompileToBytecode ? true,
            bunCompileToESM ? false,
            ...
          }@args:

          assert lib.assertMsg (!(args ? bunNix)) ''
            bun2nix.mkDerivation: `bunNix` cannot be passed to `bun2nix.mkDerivation` directly.
            It should be wrapped in `bun2nix.fetchBunDeps` like follows:

            # Example
            ```nix
            bunDeps = bun2nix.fetchBunDeps {
              bunNix = ./bun.nix;
            };
            ```
          '';

          assert lib.assertMsg (args ? bunDeps || packageJson != null) ''
            Please set `bunDeps` in order to use `bun2nix.mkDerivation`
            to build your package.

            # Example
            ```nix
            stdenv.mkDerivation {
              <other inputs>

              nativeBuildInputs = [
                bun2nix.hook
              ];

              bunDeps = bun2nix.fetchBunDeps {
                bunNix = ./bun.nix;
              };
            }
          '';

          assert lib.assertMsg (args ? pname || packageJson != null)
            "bun2nix.mkDerivation: Either `pname` or `packageJson` must be set in order to assign a name to the package. It may be assigned manually with `pname` which always takes priority or read from the `name` field of `packageJson`.";

          assert lib.assertMsg (args ? version || packageJson != null)
            "bun2nix.mkDerivation: Either `version` or `packageJson` must be set in order to assign a version to the package. It may be assigned manually with `version` which always takes priority or read from the `version` field of `packageJson`.";

          let
            pkgJsonContents = builtins.readFile packageJson;
            package = if packageJson != null then (builtins.fromJSON pkgJsonContents) else { };

            pname = args.pname or package.name or null;
            version = args.version or package.version or null;
            module = args.module or package.module or null;
            inferedCompileToESM =
              # ESM compilation was introcued in bun v1.3.9
              # see https://bun.com/blog/bun-v1.3.9#esm-bytecode-in-compile
              (builtins.compareVersions pkgs.bun.version "1.3.9" >= 0)
              # infer bytecode compilation type from packageJSON
              && (packageJson != null)
              && packageJson ? type
              && packageJson.type == "module";
          in

          assert lib.assertMsg (pname != null) ''
            bun2nix.mkDerivation: Either `name` must be specified in the given `packageJson` file, or passed as the `name` argument.

            `package.json`:
            ```json
            ${pkgJsonContents}
            ```
          '';

          assert lib.assertMsg (version != null) ''
            bun2nix.mkDerivation: Either `version` must be specified in the given `packageJson` file, or passed as the `version` argument.

            `package.json`:
            ```json
            ${pkgJsonContents}
            ```
          '';

          assert lib.assertMsg (bunCompileToESM && (builtins.compareVersions pkgs.bun.version "1.3.9") == -1)
            ''
              bun2nix.mkDerivation: Compiling to ESM bytecode is only supported from bun version >= 1.3.9.

              You are compile with: bun v${pkgs.bun.version}
            '';
          {
            inherit
              pname
              version
              dontFixup
              dontPatchShebangs
              ;

            inherit (args) bunDeps;

            bunBuildFlags =
              if (args ? bunBuildFlags) then
                args.bunBuildFlags
              else
                lib.optionals (module != null) (
                  [
                    "${module}"
                    "--outfile"
                    "${pname}"
                    "--compile"
                    "--minify"
                    "--sourcemap"
                  ]
                  ++ lib.optional bunCompileToBytecode "--bytecode"
                  ++ lib.optional (bunCompileToESM || inferedCompileToESM) "--format=esm"
                );

            meta.mainProgram = pname;

            nativeBuildInputs = nativeBuildInputs ++ [
              config.mkDerivation.hook
            ];
          };
      };
    };
}
