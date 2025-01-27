{ lib
, haskellLib
, nixpkgs
, useFastWeak
, useReflexOptimizer
, enableLibraryProfiling
, enableTraceReflexEvents
, useTextJSString
, useWebkit2Gtk
, enableExposeAllUnfoldings
, __useTemplateHaskell
, ghcSavedSplices-8_6
, ghcSavedSplices-8_10
, haskellOverlaysPre
, haskellOverlaysPost
}:

let
  inherit (nixpkgs.buildPackages) thunkSet runCommand fetchgit fetchFromGitHub fetchFromBitbucket;
  inherit (nixpkgs) hackGet;
in

rec {
  optionalExtension = cond: overlay: if cond then overlay else _: _: { };

  versionWildcard = versionList:
    let
      versionListInc = lib.init versionList ++ [ (lib.last versionList + 1) ];
      bottom = lib.concatStringsSep "." (map toString versionList);
      top = lib.concatStringsSep "." (map toString versionListInc);
    in
    version: lib.versionOlder version top && lib.versionAtLeast version bottom;

  foldExtensions = lib.foldr lib.composeExtensions (_: _: { });

  getGhcVersion = ghc: ghc.version;

  ##
  ## Conventional roll ups of all the constituent overlays below.
  ##

  # `super.ghc` is used so that the use of an overlay does not depend on that
  # overlay. At the cost of violating the usual rules on using `self` vs
  # `super`, this avoids a bunch of strictness issues keeping us terminating.
  combined = self: super: foldExtensions [
    user-custom-pre

    reflexPackages
    profiling
    untriaged

    (optionalExtension enableExposeAllUnfoldings exposeAllUnfoldings)

    #(NEW;Dylan Green):
    # We no longer need to set gold as "lld" is default on the
    # android toolchain now
    #(OLD;Dylan Green):
    # Force "gold" on Android due to a linker bug on bfd
    # Also force -fPIC on for Android, we need it either way

    # NOTE(Dylan Green): Please do not only enable based on CPU arch, this will cause
    # more problems then it's worth
    # arm* needs the same linker options, x86* -> arm* does not

    (optionalExtension (super.ghc.stdenv.targetPlatform.isAndroid or false) (self: super:
    {
        mkDerivation = drv: super.mkDerivation (drv // {
          buildFlags = [
            "--ld-option=-fPIE"
            "--ld-option=-pie"
            "--ghc-option=-fPIC"
            "--ghc-option=-fPIE"
          ] ++ (drv.buildFlags or [ ]);

          configureFlags = [ ] ++ (drv.configureFlags or [ ]);
        });
      }))

    # TODO(Dylan): Add this casing to the compiler patch
    (optionalExtension (super.ghc.stdenv.targetPlatform.isiOS && (super.ghc.stdenv.targetPlatform.isx86_64 || super.ghc.version == "8.6.5")) (self: super: {
      mkDerivation = drv: super.mkDerivation (drv // {
        buildFlags = (drv.buildFlags or []) ++ [
          "--ghc-option=-fwhole-archive-hs-libs"
        ];
      });
    }))

    combined-any
    (optionalExtension (!(super.ghc.isGhcjs or false)) combined-ghc)
    (optionalExtension (super.ghc.isGhcjs or false) combined-ghcjs)

    (optionalExtension (with nixpkgs.stdenv; versionWildcard [ 8 6 ] super.ghc.version && !(super.ghc.isGhcjs or false) && hostPlatform != buildPlatform) loadSplices-8_6)
    (optionalExtension (with nixpkgs.stdenv; versionWildcard [ 8 10 ] super.ghc.version && !(super.ghc.isGhcjs or false) && hostPlatform != buildPlatform) loadSplices-8_10)

    (optionalExtension (nixpkgs.stdenv.hostPlatform.useAndroidPrebuilt or false) android)
    (optionalExtension (nixpkgs.stdenv.hostPlatform.isiOS or false) ios)
    (optionalExtension (nixpkgs.stdenv.hostPlatform.isWasm or false) wasm)

    user-custom-post
  ]
    self
    super;

  combined-any = self: super: foldExtensions [
    any
    (optionalExtension (versionWildcard [ 8 ] (getGhcVersion super.ghc)) combined-any-8)
  ]
    self
    super;

  combined-any-8 = self: super: foldExtensions [
    any-8
    (optionalExtension (versionWildcard [ 8 6 ] (getGhcVersion super.ghc)) any-8_6)
    (optionalExtension (lib.versionOlder "8.11" (getGhcVersion super.ghc)) any-head)
  ]
    self
    super;

  combined-ghc = self: super: foldExtensions [
    (self: super: {
      hoogle = self.callHackage "hoogle" "5.0.18.3" {};
      hpack = self.callHackage "hpack" "0.34.5" {};
    })
    (optionalExtension (versionWildcard [ 8 6 ] super.ghc.version) ghc-8_6)
    (optionalExtension (lib.versionOlder "8.11" super.ghc.version) ghc-head)
  ]
    self
    super;

  combined-ghcjs = self: super: foldExtensions [
    (optionalExtension (versionWildcard [ 8 6 ] (getGhcVersion super.ghc)) combined-ghcjs-8_6)
    (optionalExtension (versionWildcard [ 8 10 ] (getGhcVersion super.ghc)) combined-ghcjs-8_10)
  ]
    self
    super;

  combined-ghcjs-8_6 = self: super: foldExtensions [
    ghcjs_8_6
    (optionalExtension useTextJSString textJSString)
    (optionalExtension useTextJSString textJSString-8_6)
    (optionalExtension useTextJSString ghcjs-textJSString-8_6)
    (optionalExtension useFastWeak ghcjs-fast-weak_8_6)
  ]
    self
    super;

  combined-ghcjs-8_10 = self: super: foldExtensions [
    (optionalExtension useTextJSString textJSString)
    (optionalExtension useTextJSString textJSString-8_10)
    (optionalExtension useTextJSString ghcjs-textJSString-8_10)
    (optionalExtension useFastWeak ghcjs-fast-weak_8_10)
    (self: super: rec {
      mkDerivation = drv: super.mkDerivation (drv // {
        setupHaskellDepends = (drv.setupHaskellDepends or []) ++ [
          nixpkgs.buildPackages.stdenv.cc
        ];
        # This is ugly
        preConfigure = (drv.preConfigure or "") + ''
          export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${nixpkgs.buildPackages.gmp}/lib:${nixpkgs.buildPackages.libffi}/lib
        '';
      });
    })
  ]
    self
    super;

  ##
  ## Constituent
  ##

  reflexPackages = import ./reflex-packages {
    inherit
      haskellLib lib nixpkgs thunkSet fetchFromGitHub fetchFromBitbucket hackGet
      useFastWeak useReflexOptimizer enableTraceReflexEvents enableLibraryProfiling __useTemplateHaskell
      useWebkit2Gtk
      ;
  };
  exposeAllUnfoldings = import ./expose-all-unfoldings.nix { };

  # For GHC and GHCJS
  any = _: _: { };
  any-8 = import ./any-8.nix { inherit haskellLib lib getGhcVersion; };
  any-8_6 = import ./any-8.6.nix { inherit haskellLib fetchFromGitHub; inherit (nixpkgs) pkgs; };
  any-head = import ./any-head.nix { inherit haskellLib fetchFromGitHub; };

  # Just for GHC, usually to sync with GHCJS
  ghc-8_6 = _: _: { };
  ghc-head = _: _: { };

  profiling = import ./profiling.nix {
    inherit haskellLib;
    inherit enableLibraryProfiling;
  };

  saveSplices = ghcVersion: import ./splices-load-save/save-splices.nix {
    inherit lib haskellLib fetchFromGitHub ghcVersion;
  };

  loadSplices-8_6 = import ./splices-load-save/load-splices.nix {
    inherit lib haskellLib fetchFromGitHub;
    isExternalPlugin = false;
    splicedHaskellPackages = ghcSavedSplices-8_6;
  };

  loadSplices-8_10 = import ./splices-load-save/load-splices.nix {
    inherit lib haskellLib fetchFromGitHub;
    isExternalPlugin = true;
    splicedHaskellPackages = ghcSavedSplices-8_10;
  };

  # Just for GHCJS
  ghcjs_8_6 = import ./ghcjs-8.6 {
    inherit
      lib haskellLib nixpkgs fetchgit fetchFromGitHub
      useReflexOptimizer
      useTextJSString
      enableLibraryProfiling
      ;
  };

  ghcjs-textJSString-8_6 = import ./ghcjs-text-jsstring-8.6 {
    inherit lib fetchgit;
  };

  ghcjs-textJSString-8_10 = import ./ghcjs-text-jsstring-8.10 {
    inherit lib fetchgit;
  };

  textJSString = import ./text-jsstring {
    inherit lib haskellLib fetchFromGitHub versionWildcard;
    inherit (nixpkgs) fetchpatch thunkSet;
  };

  textJSString-8_6 = import ./text-jsstring-8.6 {
    inherit lib haskellLib fetchFromGitHub versionWildcard;
    inherit (nixpkgs) fetchpatch thunkSet;
  };

  textJSString-8_10 = import ./text-jsstring-8.10 {
    inherit lib haskellLib fetchFromGitHub versionWildcard;
    inherit (nixpkgs) fetchpatch thunkSet;
  };

  ghcjs-fast-weak_8_6 = import ./ghcjs-8.6-fast-weak {
    inherit lib;
  };

  ghcjs-fast-weak_8_10 = import ./ghcjs-8.10-fast-weak {
    inherit lib;
  };

  android = import ./android {
    inherit haskellLib;
    inherit nixpkgs;
    inherit thunkSet;
  };
  ios = import ./ios.nix {
    inherit haskellLib;
    inherit (nixpkgs) lib;
  };

  untriaged = import ./untriaged.nix {
    inherit haskellLib;
    inherit fetchFromGitHub;
    inherit nixpkgs;
  };

  haskell-language-server = import ./haskell-language-server {
    inherit haskellLib;
    inherit fetchFromGitHub;
    inherit nixpkgs;
    inherit thunkSet;
  };

  wasm = import ./wasm;

  user-custom-pre = foldExtensions haskellOverlaysPre;
  user-custom-post = foldExtensions haskellOverlaysPost;
}
