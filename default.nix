{
  pkgs ? import <nixpkgs> { },
}:
let
  inherit (pkgs) lib;
  fs = lib.fileset;
in
rec {
  # The game's data files, built from the sources committed in data/sources.
  # This stage is deterministic and needs no network access; espeak-ng and
  # wordfreq's frequency lists come pinned by nixpkgs.
  data =
    pkgs.runCommand "sounding-data"
      {
        src = fs.toSource {
          root = ./.;
          fileset = fs.unions [
            ./pipeline/sounding_data
            ./data/sources
          ];
        };
        nativeBuildInputs = [
          (pkgs.python3.withPackages (ps: [ ps.wordfreq ]))
          pkgs.espeak-ng
        ];
        PYTHONDONTWRITEBYTECODE = 1;
      }
      ''
        cd $src
        PYTHONPATH=pipeline python -m sounding_data build --out $out
      '';

  # The static site: everything needed to serve the game.
  site = pkgs.stdenv.mkDerivation {
    pname = "sounding";
    version = "0.1.0";
    src = fs.toSource {
      root = ./frontend;
      fileset = fs.unions [
        ./frontend/src
        ./frontend/static
        ./frontend/elm.json
        ./frontend/assemble.sh
      ];
    };
    nativeBuildInputs = [
      pkgs.elmPackages.elm
      pkgs.esbuild
      pkgs.jq
    ];
    # elm2nix generates these two files; see the README.
    configurePhase = pkgs.elmPackages.fetchElmDeps {
      elmPackages = import ./frontend/elm-srcs.nix;
      elmVersion = "0.19.2";
      registryDat = ./frontend/registry.dat;
    };
    buildPhase = ''
      runHook preBuild
      elm make --optimize src/Main.elm --output=elm.unminified.js
      esbuild --minify elm.unminified.js --outfile=elm.js
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      patchShebangs assemble.sh
      ./assemble.sh elm.js ${data} $out
      runHook postInstall
    '';
  };
}
