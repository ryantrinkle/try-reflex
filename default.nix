# NOTE: Define the interface
{ nixpkgs ? ./dep/nixpkgs
, patches ? [ ]
, doPatch ? false
, nixpkgsOverlays ? (_: _: { })
, android_sdk_accept_license ? false
, allowUnfree ? false
, haskellNixArgs ? { }
, system ? builtins.currentSystem
}:
let
  composeExtensions =
    f: g: final: prev:
    let
      fApplied = f final prev;
      prev' = prev // fApplied;
    in
    fApplied // g final prev';

  # TODO:
  # - Remove this let box properly
  # Logic to bootstrap packages that isn't our local checkout

  # Auto add deps for everything in ./dep
  deps = rec {
    imported = {
      nix-thunk = import ./dep/nix-thunk { };
      haskell-nix = import ./dep/haskell.nix (haskellNixArgs // { pkgs = bootPkgs; });
    };

    source = imported.nix-thunk.mapSubdirectories imported.nix-thunk.thunkSource ./dep;
  };

  # Setup our special overlays and config
  obsidian = {
    overlays = deps.imported.haskell-nix.nixpkgsArgs.overlays ++ [
      nixpkgsOverlays
      (self: super: {
        binutils-unwrapped = super.binutils-unwrapped.override {
          autoreconfHook = super.lib.optional self.stdenv.buildPlatform.isDarwin super.autoreconfHook269;
        };
        darwin = super.darwin // {
          libiconv = super.darwin.libiconv.overrideAttrs (_:
            super.lib.optionalAttrs (self.stdenv.hostPlatform != self.stdenv.buildPlatform) {
              postInstall = "rm $out/include/libcharset.h $out/include/localcharset.h";
              configureFlags = ["--disable-shared" "--enable-static"];
            });
          };

        zlib = super.zlib.override (super.lib.optionalAttrs
          (self.stdenv.hostPlatform != self.stdenv.buildPlatform)
          { static = true; shared = false; });
      })
      (import ./modules/overlays/default.nix {
        inherit deps;
        inherit composeExtensions;
      }).combined
    ];
    config = deps.imported.haskell-nix.nixpkgsArgs.config // {
      android_sdk.accept_license = android_sdk_accept_license;
      inherit allowUnfree;
    };
  };

  bootPkgs = import nixpkgs {
    inherit system;
  };
  # Setup bootstrap pkgs, or alternatively the main packages
  pkgs-pre = import nixpkgs {
    inherit (obsidian) overlays config;
    inherit system;
  };

  # Patch the packages with some commits external to our specific checkout
  # this is optional, if people feel the need to use their own nixpkgs
  patchedNixpkgs = (pkgs-pre.applyPatches {
    name = "patched-nixpkgs";
    src = (import nixpkgs {}).path;
    patches = map pkgs-pre.fetchpatch patches;
  });

  patched-pkgs = import patchedNixpkgs ({
    inherit (obsidian) overlays config;
    inherit system;
  });

  # Our final packages with the patched commits
  pkgs = if doPatch then patched-pkgs else pkgs-pre;
in
{
 project = def: let
  toplevel = {
    inherit pkgs;
    inherit (deps.imported.nix-thunk) thunkSource mapSubdirectories;
  };
  proj = import ./modules/project.nix { inherit pkgs deps obsidian; inherit (deps.imported.nix-thunk) thunkSource; };
 in proj (def toplevel);

 inherit bootPkgs pkgs;
 inherit (pkgs.haskell-nix) compiler;

 setGhcLibdir = builtins.throw "setGhcLibdir is automatically done by haskell.nix!";
 tryReflexShell = pkgs.lib.warn "tryReflexShell has been replaced by (nix-build ./example -A shells.default)" (import ./example {}).shells.default;
 cabal2nixResult = builtins.throw "cabal2nixResult is no longer supported!";
 androidSupport = builtins.throw "androidSupport is replaced by project.nix";
 iosSupport = builtins.throw "iosSupport is replaced by project.nix";

 ghcjsExternsJs = ./ghcjs.externs.js;
 workOn = builtins.throw "workOn requires you to setup a project";

 build-wasm-app-wrapper = null;
 build-wasm-app = null;

 pinBuildInputs = null;

 reflexEnv = (import ./example {}).shells.default;
 tryReflexPackages = pkgs.lib.warn "tryReflexPackages is an unstable interface, since the package-set may change!" (import ./example {}).hsPkgs;

 cachePackages = null;

 generalDevTools' = {
   inherit (pkgs) nodejs pkg-config closurecompiler nix-prefetch-scripts curl;
   cabal2nix = builtins.throw "Not available in haskell.nix!";
 };

 inherit system;
} // (pkgs.lib.genAttrs [
  "iosAarch64" "ghcIosAarch64" "ghcAndroidAarch64"
  "ghcAndroidAarch32" "ghcSavedSplices" "ghcSavedSplices-8_6" "ghcSavedSplices-8_10"
  "ghcjs" "ghcjs8_6" "ghcjs8_10" "wasm" "ghcWasm32-8_10" "ghc" "ghcHEAD" "ghc8_10"
  "ghc8_6" "ghcAndroidAarch64" "ghcAndroidAarch64-8_6"
  "ghcAndroidAarch64-8_10" "ghcAndroidAarch32"
  "ghcAndroidAarch32-8_6" "ghcAndroidAarch32-8_10"
  "ghcIosSimulator64" "ghcIosSimulator64-8_6"
  "ghcIosSimulator64-8_10" "ghcIosAarch64"
  "ghcIosAarch64-8_6" "ghcIosAarch64-8_10"
  "ghcIosAarch32" "ghcIosAarch32-8_6"
  "ghcIosAarch32-8_10" "android"
  "android-8_6" "android-8_10" "androidWithHaskellPackages"
  "iosAarch64" "iosAarch64-8_6" "iosAarch64-8_10" "iosAarch32"
  "iosAarch32-8_6" "iosAarch32-8_10" "iosSimulator" "iosWithHaskellPackages"
] (x: pkgs.lib.warn "${x} has been replaced with the compilers attr! To use a cross arch please use pkgs.pkgsCross.haskell-nix.compiler" pkgs.haskell-nix.compiler.ghc8107Splices))
// (pkgs.lib.genAttrs [
  "androidReflexTodomvc"
  "androidReflexTodomvc-8_6" "androidReflexTodomvc-8_10"
  "iosReflexTodomvc" "iosReflexTodomvc-8_6"
  "iosReflexTodomvc-8_10" "iosSimulatorReflexTodomvc"
] (x: builtins.throw "${x} is now built using the example directory! Ex: cd ./example && nix-build -A {android,ios}.app.aarch64"))
// (pkgs.lib.genAttrs [
  "mkHackageDocs"
  "hackageDocs"
  "generalDevTools"
  "generalDevToolsAttrs"
  "nativeHaskellPackages"
  "workOnMulti"
  "workOnMulti'"
  "attrsToList"
] (x: builtins.throw "${x} has been removed!"))
