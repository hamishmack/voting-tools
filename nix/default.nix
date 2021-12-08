{ system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
, sourcesOverride ? {}
, ownHaskellNix ? null
}:
let
  sources = import ./sources.nix { inherit pkgs; }
    // sourcesOverride;
  iohkNix = import sources.iohk-nix {};
  haskellNix = if ownHaskellNix != null
    then ownHaskellNix
    else (import sources."haskell.nix" { inherit system sourcesOverride; });
  # use our own nixpkgs if it exists in our sources,
  # otherwise use iohkNix default nixpkgs.
  nixpkgs = if (sources ? nixpkgs)
    then (builtins.trace "Not using IOHK default nixpkgs (use 'niv drop nixpkgs' to use default for better sharing)"
      sources.nixpkgs)
    else (builtins.trace "Using Haskell.nix default nixpkgs"
      haskellNix.sources.nixpkgs-2105);

  # for inclusion in pkgs:
  overlays =
    # Haskell.nix (https://github.com/input-output-hk/haskell.nix)
    haskellNix.nixpkgsArgs.overlays
    # haskell-nix.haskellLib.extra: some useful extra utility functions for haskell.nix
    ++ iohkNix.overlays.haskell-nix-extra
    # iohkNix: nix utilities and niv:
    ++ iohkNix.overlays.iohkNix
    # iohkNix: utils
    ++ iohkNix.overlays.utils
    # our own overlays:
    ++ [
      (pkgs: _: with pkgs; {

        # commonLib: mix pkgs.lib with iohk-nix utils and our own:
        commonLib = lib // iohkNix // iohkNix.cardanoLib
          // import ./util.nix { inherit haskell-nix; }
          # also expose our sources and overlays
          // { inherit overlays sources; };

        svcLib = import ./svclib.nix { inherit pkgs; };
      })
      # And, of course, our haskell-nix-ified cabal project:
      (import ./pkgs.nix)
    ];

  pkgs = import nixpkgs {
    inherit system crossSystem overlays;
    config = haskellNix.nixpkgsArgs.config // config;
  };

in pkgs
