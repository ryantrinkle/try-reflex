{ nixpkgsFunc ? import ./nixpkgs
, system ? builtins.currentSystem
, config ? { }
, enableLibraryProfiling ? false
, enableExposeAllUnfoldings ? true
, enableTraceReflexEvents ? false
, useFastWeak ? true
, useReflexOptimizer ? false
, useTextJSString ? true # Use an implementation of "Data.Text" that uses the more performant "Data.JSString" from ghcjs-base under the hood.
, useWebkit2Gtk ? false # Enable webkit2gtk to build reflex-dom desktop apps
, __useTemplateHaskell ? true # Deprecated, just here until we remove feature from reflex and stop CIing it
, __useNewerCompiler ? true
, iosSdkVersion ? "16.1"
, nixpkgsOverlays ? []
, haskellOverlays ? [] # TODO deprecate
, haskellOverlaysPre ? []
, haskellOverlaysPost ? haskellOverlays
, hideDeprecated ? false # The moral equivalent of "-Wcompat -Werror" for using reflex-platform.
, hlsSupport ? false
}:

let iosSupport = system == "x86_64-darwin";
    androidSupport = lib.elem system [ "x86_64-linux" ];
    ghc86Support = lib.elem system ["x86_64-linux" "x86_64-darwin"];

    xcodeVer = {
      "16.1" = "14.1";
    }.${iosSdkVersion} or (throw "Unknown iosSdkVersion: ${iosSdkVersion}");

    # Overlay for GHC which supports the external splices plugin
    splicesEval = self: super: {
      haskell = super.haskell // {
        compiler = super.haskell.compiler // {
          ghcSplices-8_6 = (super.haskell.compiler.ghc865.overrideAttrs (drv: {
            enableParallelBuilding = false;
            src = nixpkgs.hackGet ./haskell-overlays/splices-load-save/dep/ghc-8.6;
            # When building from the ghc git repo, ./boot must be run before configuring, whereas
            # in the distribution tarball on the haskell.org downloads page, ./boot has already been
            # run.
            preConfigure = ''
              echo ${drv.version} >VERSION
              ./boot
            '' + drv.preConfigure or "";
            patches = [
              # nixpkgs-21.05 ships with a version of autoreconf that is incompatible with ghc 8.6.5,
              # Cf. https://gitlab.haskell.org/ghc/ghc/-/commit/ad2ef3a13f1eb000eab8e3d64592373b91a52806
              ./haskell-overlays/splices-load-save/ghc-8.6-autoreconf.patch
            ] ++ super.lib.optionals (super.stdenv.targetPlatform.isDarwin) [
              ./haskell-overlays/patches/ghc865/fix-big-sur.patch
            ];
          })).override {
            bootPkgs = super.haskell.packages.ghc865Binary // {
              happy = super.haskell.packages.ghc865Binary.happy_1_19_12;
            };
            useLdGold = !(self.stdenv.targetPlatform.isAarch32) && self.stdenv.hostPlatform.useAndroidPrebuilt;
            enableDocs = false;
            enableHaddockProgram = false;
          };
          ghcSplices-8_10 = (super.haskell.compiler.ghc8107.override {
            # New option for GHC 8.10. Explicitly enable profiling builds
            enableProfiledLibs = true;
            #enableShared = self.stdenv.hostPlatform == self.stdenv.targetPlatform;
            #enableShared = false;
            bootPkgs = if (super.stdenv.hostPlatform.isAarch64) then (super.haskell.packages.ghc8107Binary // {
              happy = super.haskell.packages.ghc8107Binary.happy_1_19_12;
            }) else
            (super.haskell.packages.ghc865Binary // { happy = super.haskell.packages.ghc865Binary.happy_1_19_12; });
          }).overrideAttrs (drv: {
            src = nixpkgs.hackGet ./haskell-overlays/splices-load-save/dep/ghc-8.10;
            # When building from the ghc git repo, ./boot must be run before configuring, whereas
            # in the distribution tarball on the haskell.org downloads page, ./boot has already been
            # run.
            prePatch = ''
              echo ${drv.version} >VERSION
              patchShebangs boot
              ./boot
            '' + drv.preConfigure or "";
          });
        };
        packages = super.haskell.packages // {
          ghcSplices-8_6 = super.haskell.packages.ghc865.override {
            buildHaskellPackages = self.buildPackages.haskell.packages.ghcSplices-8_6;
            ghc = self.buildPackages.haskell.compiler.ghcSplices-8_6;
          };
          ghcSplices-8_10 = super.haskell.packages.ghc8107.override {
            buildHaskellPackages = self.buildPackages.haskell.packages.ghcSplices-8_10;
            ghc = self.buildPackages.haskell.compiler.ghcSplices-8_10;
          };
        };
      };
    };

    hackGetOverlay = self: super:
      import ./nixpkgs-overlays/hack-get { inherit lib; } self;

    bindHaskellOverlays = self: super: {
      haskell = super.haskell // {
        overlays = super.haskell.overlays or {} // import ./haskell-overlays {
          nixpkgs = self;
          inherit (self) lib;
          haskellLib = self.haskell.lib;
          inherit
            useFastWeak useReflexOptimizer enableLibraryProfiling enableTraceReflexEvents
            useTextJSString enableExposeAllUnfoldings __useTemplateHaskell
            haskellOverlaysPre
            haskellOverlaysPost
            useWebkit2Gtk;
          inherit ghcSavedSplices-8_6 ghcSavedSplices-8_10;
        };
      };
    };

    forceStaticLibs = self: super: {
      darwin = super.darwin // {
        libiconv = super.darwin.libiconv.overrideAttrs (_:
          lib.optionalAttrs (self.stdenv.hostPlatform != self.stdenv.buildPlatform) {
            postInstall = "rm $out/include/libcharset.h $out/include/localcharset.h";
            configureFlags = ["--enable-shared" "--enable-static"];
          });
        };
      zlib = super.zlib.override (lib.optionalAttrs
        (self.stdenv.hostPlatform != self.stdenv.buildPlatform)
        { static = true; shared = true; });
      };

    mobileGhcOverlay = import ./nixpkgs-overlays/mobile-ghc { inherit lib; };

    allCabalHashesOverlay = import ./nixpkgs-overlays/all-cabal-hashes;

    nixpkgsArgs = {
      inherit system;
      overlays = [
        (import ./nixpkgs-overlays/ghc.nix { inherit lib; })
        hackGetOverlay
        bindHaskellOverlays
        forceStaticLibs
        splicesEval
        mobileGhcOverlay
        allCabalHashesOverlay
        (self: super: {

          runtimeShellPackage = if (self.stdenv.hostPlatform.isGhcjs || self.stdenv.targetPlatform.isiOS)
            then super.buildPackages.runtimeShellPackage
            else super.runtimeShellPackage;

          polkit = super.polkit.override {
            gobject-introspection = super.gobject-introspection-unwrapped;
          };

          darwin = super.darwin.overrideScope (dself: dsuper: {
            ios-deploy = dsuper.ios-deploy.overrideAttrs (_: {
              version = "1.12.2";
              src = self.fetchFromGitHub {
                owner = "ios-control";
                repo = "ios-deploy";
                rev = "ed7de7792d28a5110242748649047a95c95ea917";
                sha256 = "082w7j490khfpbv1diwrjixjbg9g93wdr2khyzdhv8xmzzwq4lad";
              };
            });
          });
          openjdk16-bootstrap = super.openjdk16-bootstrap.override {
            gtkSupport = false;
          };
          adoptopenjdk-hotspot-bin-16 = super.adoptopenjdk-hotspot-bin-16.override {
            gtkSupport = false;
          };

          sqlite = super.sqlite.overrideAttrs (old: lib.optionalAttrs (self.stdenv.hostPlatform.useAndroidPrebuilt or false) {
            postBuild = ''
              mkdir -p $debug
            '';
          });

          libiconv = super.libiconv.overrideAttrs (old: lib.optionalAttrs (self.stdenv.hostPlatform.useAndroidPrebuilt or false) {
            configureFlags = [ "--disable-shared" "--enable-static" ];
          });

          libffi = if (self.stdenv.hostPlatform.useAndroidPrebuilt or false) then super.libffi_3_3 else super.libffi;
        })
      ] ++ nixpkgsOverlays;
      config = config // {
        permittedInsecurePackages = (config.permittedInsecurePackages or []) ++ [
          "webkitgtk-2.4.11"
        ];

        # XCode needed for native macOS app
        # Obelisk needs it to for some reason
        allowUnfree = true;
      };
    };

    nixpkgs = nixpkgsFunc nixpkgsArgs;

    inherit (nixpkgs) lib fetchurl fetchgit fetchgitPrivate fetchFromGitHub fetchFromBitbucket;

    wasmCross = nixpkgs.hackGet ./wasm-cross;
    webGhcSrc = (import (wasmCross + /webghc.nix) { inherit fetchgit; }).ghc8107SplicesSrc;
    nixpkgsCross = {
      # NOTE(Dylan Green):
      # sdkVer 30 is the minimum for android, else we have to use libffi 3.3
      # bionic doesn't support/expose memfd_create before sdk30
      # https://android.googlesource.com/platform/bionic/+/refs/heads/master/docs/status.md
      # Look for "new libc functions in R (API Level 30):", memfd_create will be one of the functions /
      # symbols we need to build newer libffi
      # This means we'll drop all SDKs pre-30

      # NOTE(Dylan Green):
      # We don't want to use "isStatic" here as we still rely on shared-objects
      # adding "isStatic" completely disables generating most SOs, and we still need them
      # for libffi (at the very least). Currently the big issues are caused by the linker attempting (and failing)
      # to link against a dynamic crtbegin.o (crtbegin.c) bionic does provide a static crtbegin, although the linker
      # defaults to a dynamic version

      # TODO(Dylan Green):
      # Look into making this a proper static build up into "reflex-todomvc"
      android = lib.mapAttrs (_: args: nixpkgsFunc (nixpkgsArgs // args)) rec {
        aarch64 = {
          crossSystem = lib.systems.examples.aarch64-android-prebuilt // {
            #isStatic = true;
            sdkVer = "30";
          };
        };
        aarch32 = {
          crossSystem = lib.systems.examples.armv7a-android-prebuilt // {
            #isStatic = true;
            sdkVer = "30";
          };
        };
      };
      ios = lib.mapAttrs (_: args: nixpkgsFunc (nixpkgsArgs // args)) rec {
        simulator64 = {
          crossSystem = lib.systems.examples.iphone64-simulator // {
            isStatic = true;
            sdkVer = iosSdkVersion;
            inherit xcodeVer;
          };
        };
        aarch64 = {
          crossSystem = lib.systems.examples.iphone64 // {
            isStatic = true;
            sdkVer = iosSdkVersion;
            inherit xcodeVer;
          };
        };
        aarch32 = {
          crossSystem = lib.systems.examples.iphone32 // {
            isStatic = true;
            sdkVer = iosSdkVersion;
            inherit xcodeVer;
          };
        };
        # Back compat
        arm64 = lib.warn "nixpkgsCross.ios.arm64 has been deprecated, using nixpkgsCross.ios.aarch64 instead." aarch64;
      };
      ghcjs = nixpkgsFunc (nixpkgsArgs // {
        crossSystem = lib.systems.examples.ghcjs;
      });
      wasm = nixpkgsFunc (nixpkgsArgs //
        (import wasmCross { inherit nixpkgsFunc; }).nixpkgsCrossArgs webGhcSrc "8.6.5"
      );
    };

    haskellLib = nixpkgs.haskell.lib;

    overrideCabal = pkg: f: if pkg == null then null else haskellLib.overrideCabal pkg f;

    combineOverrides = old: new: old // new // lib.optionalAttrs (old ? overrides && new ? overrides) {
      overrides = lib.composeExtensions old.overrides new.overrides;
    };

    # Makes sure that old `overrides` from a previous call to `override` are not
    # forgotten, but composed. Do this by overriding `override` and passing a
    # function which takes the old argument set and combining it. What a tongue
    # twister!
    makeRecursivelyOverridable = x: x // {
      override = new: makeRecursivelyOverridable (x.override (old: (combineOverrides old new)));
    };

  ghcSavedSplices = if __useNewerCompiler then ghcSavedSplices-8_10 else ghcSavedSplices-8_6;
  ghcSavedSplices-8_6 = (makeRecursivelyOverridable nixpkgs.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = lib.foldr lib.composeExtensions (_: _: {}) (let
      haskellOverlays = nixpkgs.haskell.overlays;
    in [
      haskellOverlays.combined
      (haskellOverlays.saveSplices "8.6")
      (self: super: with haskellLib; {
        blaze-textual = enableCabalFlag super.blaze-textual "integer-simple";
        cryptonite = disableCabalFlag super.cryptonite "integer-gmp";
        integer-logarithms = disableCabalFlag super.integer-logarithms "integer-gmp";
        scientific = enableCabalFlag super.scientific "integer-simple";
        dependent-sum-template = dontCheck super.dependent-sum-template;
        generic-deriving = dontCheck super.generic-deriving;
      })
    ]);
  };
  ghcSavedSplices-8_10 = (makeRecursivelyOverridable nixpkgs.haskell.packages.integer-simple.ghcSplices-8_10).override {
    overrides = lib.foldr lib.composeExtensions (_: _: {}) (let
      haskellOverlays = nixpkgs.haskell.overlays;
    in [
      haskellOverlays.combined
      (haskellOverlays.saveSplices "8.10")
      (self: super: with haskellLib; {
        blaze-textual = enableCabalFlag super.blaze-textual "integer-simple";
        cryptonite = disableCabalFlag super.cryptonite "integer-gmp";
        integer-logarithms = disableCabalFlag super.integer-logarithms "integer-gmp";
        scientific = enableCabalFlag super.scientific "integer-simple";
      })
    ]);
  };
  ghcjs = if __useNewerCompiler then ghcjs8_10 else ghcjs8_6;
  ghcjs8_6 = (makeRecursivelyOverridable (nixpkgsCross.ghcjs.haskell.packages.ghcjs86.override (old: {
    ghc = old.ghc.override {
      bootPkgs = old.ghc.bootPkgs // { happy = old.ghc.bootPkgs.happy_1_19_12; };
      cabal-install = import ./haskell-overlays/ghcjs-8.6/cabal-install.nix { inherit nixpkgs; };
      ghcjsSrc = import ./haskell-overlays/ghcjs-8.6/src.nix {
        inherit (nixpkgs.stdenvNoCC) mkDerivation;
        inherit (nixpkgs) fetchgit;
      };
    };
  }))).override {
    overrides = nixpkgsCross.ghcjs.haskell.overlays.combined;
  };

  ghcjs8_10 = (makeRecursivelyOverridable nixpkgsCross.ghcjs.haskell.packages.ghcjs810).override {
    overrides = nixpkgsCross.ghcjs.haskell.overlays.combined;
  };

  wasm = ghcWasm32-8_10;
  ghcWasm32-8_10 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable (nixpkgsCross.wasm.haskell.packages.ghcWasm.override (old: {
    # Due to the splices changes the parallel build fails while building the libraries
    ghc = old.ghc.overrideAttrs (drv: { enableParallelBuilding = false; });
  }))).override {
    overrides = nixpkgsCross.wasm.haskell.overlays.combined;
  });

  ghc = if __useNewerCompiler then ghc8_10 else ghc8_6;
  ghcHEAD = (makeRecursivelyOverridable nixpkgs.haskell.packages.ghcHEAD).override {
    overrides = nixpkgs.haskell.overlays.combined;
  };
  ghc8_10 = (makeRecursivelyOverridable nixpkgs.haskell.packages.ghc8107).override {
    overrides = nixpkgs.haskell.overlays.combined;
  };
  ghc8_6 = (makeRecursivelyOverridable nixpkgs.haskell.packages.ghc865).override {
    overrides = nixpkgs.haskell.overlays.combined;
  };

  # Takes a package set with `makeRecursivelyOverridable` and ensures that any
  # future overrides will be applied to both the package set itself and it's
  # build-time package set (`buildHaskellPackages`).
  makeRecursivelyOverridableBHPToo = x: x // {
    override = new: makeRecursivelyOverridableBHPToo (x.override
      (combineOverrides
        {
          overrides = self: super: {
            buildHaskellPackages = super.buildHaskellPackages.override new;
          };
        }
        new));
  };

  ghcAndroidAarch64 = if __useNewerCompiler then ghcAndroidAarch64-8_10 else ghcAndroidAarch64-8_6;
  ghcAndroidAarch64-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.android.aarch64.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.android.aarch64.haskell.overlays.combined;
  });
  ghcAndroidAarch64-8_10 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.android.aarch64.haskell.packages.integer-simple.ghcSplices-8_10).override {
    overrides = nixpkgsCross.android.aarch64.haskell.overlays.combined;
  });
  ghcAndroidAarch32 = if __useNewerCompiler then ghcAndroidAarch32-8_10 else ghcAndroidAarch32-8_6;
  ghcAndroidAarch32-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.android.aarch32.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.android.aarch32.haskell.overlays.combined;
  });
  ghcAndroidAarch32-8_10 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.android.aarch32.haskell.packages.integer-simple.ghcSplices-8_10).override {
    overrides = nixpkgsCross.android.aarch32.haskell.overlays.combined;
  });
  ghcIosSimulator64-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.simulator64.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.ios.simulator64.haskell.overlays.combined;
  });
  ghcIosSimulator64-8_10 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.simulator64.haskell.packages.integer-simple.ghcSplices-8_10).override {
    overrides = nixpkgsCross.ios.simulator64.haskell.overlays.combined;
  });
  ghcIosSimulator64 = if __useNewerCompiler then ghcIosSimulator64-8_10 else ghcIosSimulator64-8_6;
  ghcIosAarch64 = if __useNewerCompiler then ghcIosAarch64-8_10 else ghcIosAarch64-8_6;
  ghcIosAarch64-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.aarch64.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.ios.aarch64.haskell.overlays.combined;
  });
  ghcIosAarch64-8_10 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.aarch64.haskell.packages.integer-simple.ghcSplices-8_10).override {
    overrides = nixpkgsCross.ios.aarch64.haskell.overlays.combined;
  });
  ghcIosAarch32 = if __useNewerCompiler then ghcIosAarch32-8_10 else ghcIosAarch32-8_6;
  ghcIosAarch32-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.aarch32.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.ios.aarch32.haskell.overlays.combined;
  });
  ghcIosAarch32-8_10 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.aarch32.haskell.packages.integer-simple.ghcSplices-8_10).override {
    overrides = nixpkgsCross.ios.aarch32.haskell.overlays.combined;
  });

  #TODO: Separate debug and release APKs
  #TODO: Warn the user that the android app name can't include dashes
  android = androidWithHaskellPackages {
    inherit ghcAndroidAarch64 ghcAndroidAarch32;
  };
  android-8_6 = androidWithHaskellPackages {
    ghcAndroidAarch64 = ghcAndroidAarch64-8_6;
    ghcAndroidAarch32 = ghcAndroidAarch32-8_6;
  };
  android-8_10 = androidWithHaskellPackages {
    ghcAndroidAarch64 = ghcAndroidAarch64-8_10;
    ghcAndroidAarch32 = ghcAndroidAarch32-8_10;
  };
  androidWithHaskellPackages = { ghcAndroidAarch64, ghcAndroidAarch32 }: import ./android {
    inherit nixpkgs nixpkgsCross ghcAndroidAarch64 ghcAndroidAarch32 overrideCabal;
    acceptAndroidSdkLicenses = config.android_sdk.accept_license or false;
  };
  iosAarch64 = iosWithHaskellPackages ghcIosAarch64;
  iosAarch64-8_6 = iosWithHaskellPackages ghcIosAarch64-8_6;
  iosAarch64-8_10 = iosWithHaskellPackages ghcIosAarch64-8_10;
  iosAarch32 = iosWithHaskellPackages ghcIosAarch32;
  iosAarch32-8_6 = iosWithHaskellPackages ghcIosAarch32-8_6;
  iosAarch32-8_10 = iosWithHaskellPackages ghcIosAarch32-8_10;
  iosSimulator = {
    buildApp = nixpkgs.lib.makeOverridable (import ./ios { inherit nixpkgs; ghc = ghcIosSimulator64; withSimulator = true; });
  };
  iosWithHaskellPackages = ghc: {
    buildApp = nixpkgs.lib.makeOverridable (import ./ios { inherit nixpkgs ghc; });
  };

in let this = rec {
  inherit (nixpkgs)
    filterGit
    hackGet
    thunkSet
    ;
  inherit nixpkgs
          nixpkgsCross
          overrideCabal
          ghc
          ghcHEAD
          ghc8_6
          ghc8_10
          ghcIosSimulator64
          ghcIosSimulator64-8_6
          ghcIosSimulator64-8_10
          ghcIosAarch64
          ghcIosAarch64-8_6
          ghcIosAarch64-8_10
          ghcIosAarch32
          ghcIosAarch32-8_6
          ghcIosAarch32-8_10
          ghcAndroidAarch64
          ghcAndroidAarch64-8_6
          ghcAndroidAarch64-8_10
          ghcAndroidAarch32
          ghcAndroidAarch32-8_6
          ghcAndroidAarch32-8_10
          ghcjs
          ghcjs8_6
          ghcjs8_10
          ghcSavedSplices
          ghcSavedSplices-8_6
          ghcSavedSplices-8_10
          android
          androidWithHaskellPackages
          iosAarch32
          iosAarch64
          iosSimulator
          iosWithHaskellPackages
          wasm
          wasmCross
          ;

  # Back compat
  ios = iosAarch64;
  ghcAndroidArm64 = lib.warn "ghcAndroidArm64 has been deprecated, using ghcAndroidAarch64 instead." ghcAndroidAarch64;
  ghcAndroidArmv7a = lib.warn "ghcAndroidArmv7a has been deprecated, using ghcAndroidAarch32 instead." ghcAndroidAarch32;
  ghcIosArm64 = lib.warn "ghcIosArm64 has been deprecated, using ghcIosAarch64 instead." ghcIosAarch64;

  androidReflexTodomvc = android.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    applicationId = "org.reflexfrp.todomvc";
    displayName = "Reflex TodoMVC";
  };
  androidReflexTodomvc-8_6 = android-8_6.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    applicationId = "org.reflexfrp.todomvc.via_8_6";
    displayName = "Reflex TodoMVC via GHC 8.6";
  };
  androidReflexTodomvc-8_10 = android-8_10.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    applicationId = "org.reflexfrp.todomvc.via_8_10";
    displayName = "Reflex TodoMVC via GHC 8.10";
  };
  iosReflexTodomvc = ios.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    bundleIdentifier = "org.reflexfrp.todomvc";
    bundleName = "Reflex TodoMVC";
  };
  iosReflexTodomvc-8_6 = iosAarch64-8_6.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    bundleIdentifier = "org.reflexfrp.todomvc.via_8_6";
    bundleName = "Reflex TodoMVC via GHC 8.6";
  };
  iosReflexTodomvc-8_10 = iosAarch64-8_10.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    bundleIdentifier = "org.reflexfrp.todomvc.via_8_10";
    bundleName = "Reflex TodoMVC via GHC 8.10";
  };
  iosSimulatorReflexTodomvc = iosSimulator.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    bundleIdentifier = "org.reflexfrp.todomvc";
    bundleName = "Reflex TodoMVC";
  };
  setGhcLibdir = ghcLibdir: inputGhcjs:
    let libDir = "$out/lib/ghcjs-${inputGhcjs.version}";
        ghcLibdirLink = nixpkgs.stdenv.mkDerivation {
          name = "ghc_libdir";
          inherit ghcLibdir;
          buildCommand = ''
            mkdir -p ${libDir}
            echo "$ghcLibdir" > ${libDir}/ghc_libdir_override
          '';
        };
    in inputGhcjs // {
    outPath = nixpkgs.buildEnv {
      inherit (inputGhcjs) name;
      paths = [ inputGhcjs ghcLibdirLink ];
      postBuild = ''
        mv ${libDir}/ghc_libdir_override ${libDir}/ghc_libdir
      '';
    };
  };

  platforms = [
    "ghcjs"
    "ghc"
  ];

  androidDevTools = [
    ghc.haven
    nixpkgs.maven
    nixpkgs.androidsdk_9_0
  ];

  # Tools that are useful for development under both ghc and ghcjs
  generalDevTools' = { nativeHaskellPackages ? ghc }: {
    inherit (nativeHaskellPackages)
      Cabal
      cabal-install
      ghcid
      hasktags
      stylish-haskell # Recent stylish-haskell only builds with AMP in place
      reflex-ghci
      ;
    inherit (nixpkgs)
      cabal2nix
      curl
      nix-prefetch-scripts
      nodejs
      pkgconfig
      closurecompiler
      ;
  } // lib.optionalAttrs hlsSupport {
    haskell-language-server = nixpkgs.haskell.lib.justStaticExecutables (nativeHaskellPackages.override {
      overrides = nixpkgs.haskell.overlays.haskell-language-server;
    }).haskell-language-server;
  };

  workOn = haskellPackages: package: (overrideCabal package (drv: {
    buildTools = (drv.buildTools or []) ++ builtins.attrValues (generalDevTools' {});
  })).env;

  # A minimal wrapper around the build-wasm-app from wasm-cross
  # Useful in building simple cabal projects like reflex-todomvc
  build-wasm-app-wrapper =
    ename: # Name of the executable, usually same as cabal project name
    pkgPath : # Path of cabal package
    args: # Others options to pass to build-wasm-app
  let
    pkg = wasm.callPackage pkgPath {};
    webabi = nixpkgs.callPackage (wasmCross + /webabi) {};
    build-wasm-app = nixpkgs.callPackage (wasmCross + /build-wasm-app.nix) ({ inherit webabi; } // args);
  in build-wasm-app {
    inherit pkg ename;
  };

  # A simple derivation that just creates a file with the names of all
  # of its inputs. If built, it will have a runtime dependency on all
  # of the given build inputs.
  pinBuildInputs = name: buildInputs: (nixpkgs.releaseTools.aggregate {
    inherit name;
    constituents = buildInputs;
  }).overrideAttrs (old: {
    buildCommand = old.buildCommand + ''
      echo "$propagatedBuildInputs $buildInputs $nativeBuildInputs $propagatedNativeBuildInputs" > "$out/deps"
    '';
    inherit buildInputs;
  });

  reflexEnv = platform:
    let haskellPackages = builtins.getAttr platform this;
        ghcWithStuff = if platform == "ghc"
                       then haskellPackages.ghcWithHoogle
                       else haskellPackages.ghcWithPackages;
    in ghcWithStuff (p: import ./packages.nix {
      haskellPackages = p;
      inherit platform;
    });

  tryReflexPackages = builtins.attrValues (generalDevTools' {})
    ++ builtins.map reflexEnv platforms;

  cachePackages =
    let otherPlatforms = lib.optionals androidSupport [
          (if __useNewerCompiler then "ghcAndroidAarch64-8_10" else "ghcAndroidAarch64")
          (if __useNewerCompiler then "ghcAndroidAarch32-8_10" else "ghcAndroidAarch32")
        ] ++ lib.optionals iosSupport [
          (if __useNewerCompiler then "ghcIosAarch64-8_10" else "ghcIosAarch64")
          (if __useNewerCompiler then "ghcIosSimulator64-8_10" else "ghcIosSimulator64")
        ];
    in tryReflexPackages
      ++ builtins.map reflexEnv otherPlatforms
      ++ lib.optionals androidSupport [
        androidDevTools
        androidReflexTodomvc
      ] ++ lib.optionals iosSupport [
        iosReflexTodomvc iosSimulatorReflexTodomvc
      ];

  inherit system androidSupport iosSupport ghc86Support;
  project = args: import ./project this (args ({ pkgs = nixpkgs; } // this));
  tryReflexShell = pinBuildInputs ("shell-" + system) tryReflexPackages;
  ghcjsExternsJs = ./ghcjs.externs.js;
};

# Deprecated reexports. These were made for `./scripts/*`, but are reexported
# here for backwards compatibility.
legacy = {
  # Added 2019-12, will be removed 2020-06.
  inherit
    (import ./nix-utils/hackage { reflex-platform = this; })
    attrsToList
    mapSet
    mkSdist
    sdists
    mkHackageDocs
    hackageDocs
    mkReleaseCandidate
    releaseCandidates
    ;
  generalDevTools = _: builtins.attrValues (this.generalDevTools' {});
  generalDevToolsAttrs = _: this.generalDevTools' {};
  nativeHaskellPackages = haskellPackages:
    if haskellPackages.isGhcjs or false
    then haskellPackages.ghc
    else haskellPackages;
  workOnMulti' = { env, packageNames }:
    (import ./nix-utils/work-on-multi {}).workOnMulti {
      envFunc = _: env;
      inherit packageNames;
    };
  workOnMulti = env: packageNames: legacy.workOnMulti' { inherit env packageNames; };
};

in this // lib.optionalAttrs
  (!hideDeprecated)
  (lib.mapAttrs (attrName: builtins.trace "The attribute \"${attrName}\" is deprecated. See reflex-platform's root default.nix.") legacy)
