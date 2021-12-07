{ system ? builtins.currentSystem
, crossSystem ? null
# allows to cutomize haskellNix (ghc and profiling, see ./nix/haskell.nix)
, config ? {}
# override scripts with custom configuration
, customConfig ? {}
# allows to override dependencies of the project without modifications,
# eg. to test build against local checkout of nixpkgs and iohk-nix:
# nix build -f default.nix cardano-shell '{
#   iohk-nix = ../iohk-nix;
# }'
, sourcesOverride ? {}
# pinned version of nixpkgs augmented with overlays (iohk-nix and our packages).
, pkgs ? import ./nix { inherit system crossSystem config sourcesOverride; }
, gitrev ? pkgs.iohkNix.commitIdFromGitRepoOrZero ./.git
}:
with pkgs; with commonLib;
let

  haskellPackages = recRecurseIntoAttrs
    # the Haskell.nix package set, reduced to local packages.
    (selectProjectPackages votingToolsHaskellPackages);
  haskellPackagesMusl64 = recRecurseIntoAttrs
    # the Haskell.nix package set, reduced to local packages.
    (selectProjectPackages pkgs.pkgsCross.musl64.votingToolsHaskellPackages);
  voterRegistrationTarball = pkgs.runCommandNoCC "voter-registration-tarball" { buildInputs = [ pkgs.gnutar gzip ]; } ''
    cp ${haskellPackagesMusl64.voter-registration.components.exes.voter-registration}/bin/voter-registration ./
    mkdir -p $out/nix-support
    tar -czvf $out/voter-registration.tar.gz voter-registration
    echo "file binary-dist $out/voter-registration.tar.gz" > $out/nix-support/hydra-build-products
  '';

  self = {
    inherit votingToolsHaskellPackages voterRegistrationTarball;
    inherit haskellPackages hydraEvalErrors;

    inherit (pkgs.iohkNix) checkCabalProject;

    inherit (haskellPackages.voter-registration.identifier) version;
    # Grab the executable component of our package.
    inherit (haskellPackages.voter-registration.components.exes) voter-registration;
    inherit (haskellPackages.voting-tools.components.exes) voting-tools;

    # `tests` are the test suites which have been built.
    tests = collectComponents' "tests" haskellPackages;
    # `benchmarks` (only built, not run).
    benchmarks = collectComponents' "benchmarks" haskellPackages;

    nixosTests = pkgs.callPackage ./nix/nixos/tests/default.nix { inherit system; };

    checks = recurseIntoAttrs {
      # `checks.tests` collect results of executing the tests:
      tests = collectChecks haskellPackages;
    };

    shell = import ./shell.nix {
      inherit pkgs;
      withHoogle = true;
    };

    # integration-tests = import ./test/integration/vm.nix { inherit pkgs; };
  };
in self
