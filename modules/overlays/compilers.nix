{ useTextJSString ? false, useFastWeak ? true }: final: prev: let
  lib = import ./lib.nix final prev;
in {
  _dep = (prev._dep or {}) // rec {
    textSrc = final.fetchgit {
      url = "https://github.com/dfordivam/text.git";
      rev = "126174753ea8e5f45df8fcbba609e3f1c453bf27";
      sha256 = "0l7nbln2w77s12fm4ybhi0jsfnxkyiwskfx3b682pfisa6n32rgm";
    };
    ghcjsBaseTextJSStringSrc = (final.fetchgit {
      url = "https://github.com/ghcjs/ghcjs-base.git";
      rev = "85e31beab9beffc3ea91b954b61a5d04e708b8f2";
      sha256 = "sha256-7VYfQS7qFE/itNIv/Nx5B7glL3WkgmmWoIskd8yivd0=";
    }).overrideAttrs (old: {
      outputHash = "sha256-7VYfQS7qFE/itNIv/Nx5B7glL3WkgmmWoIskd8yivd0=";
      postFetch = (old.postFetch or "") + ''
        cd $out
        patch -p1 < ${jsstring-patch}
      '';
    });
    jsstring-patch = (final.fetchurl {
      url = "https://github.com/reflex-frp/reflex-platform/raw/develop/haskell-overlays/ghcjs-text-jsstring-8.10/ghcjs-base-text-jsstring.patch";
      sha256 = "sha256-QmPGCakSWqqg1zXM4MU4pHOk+O+y9ZSt+My+ecl5+nM=";
    });
    ctimePatch = final.fetchpatch {
      name = "ghcjs-base-ctime-64-bit.patch";
      url = "https://github.com/ghcjs/ghcjs/commit/b7711fbca7c3f43a61f1dba526e6f2a2656ef44c.patch";
      hash = "sha256-zZ3l8/5gbIGtvu0s2Xl92fEDhkhJ2c2w+5Ql5qkvr3s=";
    };
    fast-weak-patch = final.fetchurl {
      url = "https://github.com/reflex-frp/reflex-platform/raw/develop/haskell-overlays/ghcjs-8.10-fast-weak/fast-weak.patch";
      sha256 = "sha256-ldHC96D/bJxlXmfar/apPj3QZ4P1tnSVNY5ELFvXH/I=";
    };
  };

  obsidianCompilers = rec {
    unpacker = tarball: name: final.runCommandNoCC "${name}-to-dir" {} ''
      unpackFile ${tarball}
      mv ${name}-* $out
    '';
    thunkSets = rec {
      common = [
        (unpacker final.haskell.packages.ghcjs810.dlist.src "dlist")
        (unpacker final.haskell.packages.ghcjs810.vector.src "vector")
        (unpacker final.haskell.packages.ghcjs810.primitive.src "primitive")
        final._dep.ghcjsBaseTextJSStringSrc
      ];
      aeson-1541 = [
        final._dep.source.aeson-1541
      ] ++ common;
      aeson-2 = [
        final._dep.source.aeson
      ] ++ common;
    };
    jsstring-overrides = [
      ({ pkgs, config, lib, ... }: {
        packages.hashable.patches = [ ../patches/hashable/hashable.patch ];
      })
    ];
    ghcjs = builtins.mapAttrs (_: v: v // { useLLVM = false; }) {
      ghcjs8107JSString = let
        booted-ghcjs = lib.bootGHCJS {
          ghcjsSrcJson = (final._dep.source."haskell.nix" + "/compiler/ghcjs/ghcjs810-src.json");
          ghcjsVersion = "8.10.7";
          ghcVersion = "8.10.7";
          compiler-nix-name = "ghcjs8107JSString";
          buildGHC = final.buildPackages.haskell-nix.compiler.ghcjs8107JSString;
          patches = [
            final._dep.fast-weak-patch
            ../patches/ghcjs/revert.patch
          ];
          postUnpack = lib.JSSTringPostUnpack;
        };
      in lib.mkFinalGHCJS {
        inherit booted-ghcjs;
        buildGHC = final.buildPackages.haskell-nix.compiler.ghcjs8107JSString;
        #installDeps = lib.installDeps;
      };

      ghcjs8107JSStringSplices = let
        booted-ghcjs = lib.bootGHCJS {
          buildGHC = final.buildPackages.haskell-nix.compiler.ghcjs8107JSStringSplices;
          ghcjsSrcJson = ./git.json;
          ghcjsVersion = "8.10.7";
          ghcVersion = "8.10.7";
          compiler-nix-name = "ghcjs8107JSStringSplices";
          configurePatches = [
            "${final._dep.ctimePatch}"
          ];
          patches = [
            final._dep.fast-weak-patch
          ];
          postUnpack = lib.JSSTringPostUnpack;
        };
      in lib.mkFinalGHCJS {
        inherit booted-ghcjs;
        buildGHC = final.buildPackages.haskell-nix.compiler.ghcjs8107JSStringSplices;
        #installDeps = lib.installDeps;
      };
    };
    ghc = rec {
      ghcjs8107JSString = prev.haskell-nix.compiler.ghc8107;
      ghcjs865JSString = prev.haskell-nix.compiler.ghc865;

      ghcjs8107JSStringSplices = final.callPackage (final._dep.source."haskell.nix" + "/compiler/ghc") {
        extra-passthru = {
          buildGHC = final.buildPackages.haskell-nix.compiler.ghc8107;
        };

        bootPkgs = lib.bootPkgs // {
          ghc = lib.ghcForBuilding810;
        };
        inherit (lib) sphinx /*installDeps*/;

        buildLlvmPackages = final.buildPackages.llvmPackages_12;
        llvmPackages = final.llvmPackages_12;

        src-spec = rec {
          version = "8.10.7";
          url = "https://downloads.haskell.org/~ghc/${version}/ghc-${version}-src.tar.xz";
          sha256 = "179ws2q0dinl1a39wm9j37xzwm84zfz3c5543vz8v479khigdvp3";
        };

        ghc-patches = [
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/Cabal-unbreak-GHCJS.patch")
          (final.fetchurl {
            url = "https://raw.githubusercontent.com/obsidiansystems/splices-load-save.nix/master/patches/ghc-8.10.7/splices.patch";
            sha256 = "sha256-pIMPDpBwL3tYPEbIgTfE1oNgL2KMLp7ovcp6E2KOIVY=";
          })
        ];
      };

      ghc8107Splices = final.callPackage (final._dep.source."haskell.nix" + "/compiler/ghc") {
        extra-passthru = {
          buildGHC = final.buildPackages.haskell-nix.compiler.ghc8107;
        };

        bootPkgs = lib.bootPkgs // {
          ghc = lib.ghcForBuilding810;
        };
        inherit (lib) sphinx /*installDeps*/;

        buildLlvmPackages = final.buildPackages.llvmPackages_12;
        llvmPackages = final.llvmPackages_12;

        src-spec = rec {
          version = "8.10.7";
          url = "https://downloads.haskell.org/~ghc/${version}/ghc-${version}-src.tar.xz";
          sha256 = "179ws2q0dinl1a39wm9j37xzwm84zfz3c5543vz8v479khigdvp3";
        };
        ghc-patches = [
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/Cabal-unbreak-GHCJS.patch")
          (final.fetchurl {
            url = "https://raw.githubusercontent.com/obsidiansystems/splices-load-save.nix/master/patches/ghc-8.10.7/splices.patch";
            sha256 = "sha256-pIMPDpBwL3tYPEbIgTfE1oNgL2KMLp7ovcp6E2KOIVY=";
          })
          ../patches/aarch64-darwin/fix_dead_strip.patch
        ] ++ final.lib.optionals (final.stdenv.targetPlatform.isAndroid && final.stdenv.targetPlatform.isAarch32) [
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/ghc-make-stage-1-lib-ghc.patch")
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/ghc-8.10-3434-armv7a.patch")
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/libraries-prim-os-android-armv7a.patch")
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/ghc-8.10.7-linker-weak-and-common-armv7a.patch")
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/ghc-8.10-android.patch")
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/ghc-8.10.7-android-bionic-symbols.patch")
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/ghc-8.10.7-bionic-libc.patch")
          ((final._dep.source."haskell.nix") + "/overlays/patches/ghc/ghc-8.10.7-cross-dont-build-stage2-tools.patch")
        ];
      };
    };
  };
}
