{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (ps: [
      ps.wordfreq
      ps.pytest
      ps.playwright
    ]))
    pkgs.espeak-ng
    pkgs.elmPackages.elm
    pkgs.elmPackages.elm-format
    pkgs.elmPackages.elm-test
    pkgs.elm2nix
    pkgs.ruff
  ];
  PLAYWRIGHT_BROWSERS_PATH = pkgs.playwright-driver.browsers;
}
