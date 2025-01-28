final: prev: {
  mkFinalGHCJS = { booted-ghcjs, buildGHC/*, installDeps*/ }: let
    targetPrefix = "js-unknown-ghcjs-";
  in final.runCommand "${targetPrefix}ghc-8.10.7" {
        nativeBuildInputs = [ final.xorg.lndir ];
        passthru = {
          inherit targetPrefix;
          version = "8.10.7";
          isHaskellNixCompiler = true;
          enableShared = false;
          inherit (booted-ghcjs) configured-src bundled-ghcjs project;
          inherit booted-ghcjs buildGHC;
          extraConfigureFlags = [
            "--ghcjs"
            "--with-ghcjs=${targetPrefix}ghc"
            "--with-ghcjs-pkg=${targetPrefix}ghc-pkg"
            "--with-gcc=${final.buildPackages.emscripten}/bin/emcc"
          ];
        };
      } (''
            mkdir -p $out/bin
            cd $out/bin
            ln -s ${booted-ghcjs}/bin/ghcjs ${targetPrefix}ghc
            ln -s ${booted-ghcjs}/bin/ghcjs-pkg ${targetPrefix}ghc-pkg
            ln -s ${buildGHC}/bin/hsc2hs ${targetPrefix}hsc2hs
            cd ..
            mkdir -p lib/${targetPrefix}ghc-8.10.7
            cd lib
            lndir ${booted-ghcjs}/lib ${targetPrefix}ghc-8.10.7
          ''/* + installDeps targetPrefix*/);

    bootGHCJS = {
      configurePatches ? [ ],
      patches ? [ ],
      ghcjsSrcJson,
      ghcjsVersion,
      ghcVersion,
      compiler-nix-name,
      postUnpack ? x: "",
      extra-modules ? [],
      buildGHC
    }: (final.callPackage (final._dep.source."haskell.nix" + "/compiler/ghcjs/ghcjs.nix") {
      inherit ghcjsSrcJson ghcjsVersion ghcVersion compiler-nix-name extra-modules;
      patches = configurePatches;
      ghc = buildGHC;
    }).overrideAttrs (drv: {
      phases = (drv.phases or []) ++ [ "unpackPhase" "patchPhase" "buildPhase" ];
        postUnpack = postUnpack (drv.postUnpack or "");
        inherit patches;
      });

    JSSTringPostUnpack = x: x + ''
      set -x
      (
        echo $sourceRoot
        cd $sourceRoot
        rm -r lib/boot/pkg/text
        # unpackFile ${final._dep.textSrc}
        # chmod +w text-*
        # mv text-* lib/boot/pkg/text
        cp --no-preserve=mode -r "${final._dep.textSrc}" lib/boot/pkg/text
        unpackFile ${final._dep.ghcjsBaseTextJSStringSrc}
        chmod +w ghcjs-base-*
        mv ghcjs-base-* lib/boot/pkg/ghcjs-base
        unpackFile ${final.haskell.packages.ghcjs810.dlist.src}
        chmod +w dlist-*
        mv dlist-* lib/boot/pkg/dlist
        unpackFile ${final.haskell.packages.ghcjs810.vector.src}
        chmod +w vector-*
        mv vector-* lib/boot/pkg/vector
        unpackFile ${final.haskell.packages.ghcjs810.primitive.src}
        chmod +w primitive-*
        mv primitive-* lib/boot/pkg/primitive
        sed -i 's/    - mtl/    - mtl\n    - dlist\n    - primitive\n    - vector\n    - ghcjs-base/' lib/boot/boot.yaml
        cat lib/boot/boot.yaml
      )
    '';


    ghcForBuilding810 = final.buildPackages.buildPackages.haskell-nix.bootstrap.compiler.ghc8107;
                        # if (final.buildPlatform.isAarch64 && final.buildPlatform.isDarwin)
                        # then final.buildPackages.buildPackages.haskell-nix.bootstrap.compiler.ghc8107
                        # else if (final.buildPlatform.isAarch64 || final.targetPlatform.isAarch64)
                        # then final.buildPackages.buildPackages.haskell-nix.compiler.ghc884
                        # else final.buildPackages.buildPackages.haskell-nix.compiler.ghc865;

    bootPkgs = with final.buildPackages; {
      ghc = final.buildPackages.buildPackages.haskell-nix.bootstrap.compiler."${buildBootstrapper.compilerNixName}";
      alex = final.haskell-nix.bootstrap.packages.alex;
      happy = final.haskell-nix.bootstrap.packages.happy;
      hscolour = final.haskell-nix.bootstrap.packages.hscolour;
    };

    sphinx = with final.buildPackages; (python3Packages.sphinx_1_7_9 or python3Packages.sphinx);

    makeCompilerDeps = ghc: ghc // {
      cachedDeps = final.runCommand "${ghc.name}-deps" {}
        # First checks that ghc-pkg runs first with `--version` as failures in the `for` and
        # `if` statements will be masked.
        ''
        mkdir $out
        ${ghc}/bin/${ghc.targetPrefix}ghc-pkg --version
        for P in $(${ghc}/bin/${ghc.targetPrefix}ghc-pkg list --simple-output | sed 's/-[0-9][0-9.]*//g'); do
          mkdir -p $out/exactDeps/$P
          touch $out/exactDeps/$P/configure-flags
          touch $out/exactDeps/$P/cabal.config

          if id=$(${ghc}/bin/${ghc.targetPrefix}ghc-pkg field $P id --simple-output); then
            echo "--dependency=$P=$id" >> $out/exactDeps/$P/configure-flags
          elif id=$(${ghc}/bin/${ghc.targetPrefix}ghc-pkg field "z-$P-z-*" id --simple-output); then
            name=$(${ghc}/bin/${ghc.targetPrefix}ghc-pkg field "z-$P-z-*" name --simple-output)
            # so we are dealing with a sublib. As we build sublibs separately, the above
            # query should be safe.
            echo "--dependency=''${name#z-$P-z-}=$id" >> $out/exactDeps/$P/configure-flags
          fi
          if ver=$(${ghc}/bin/${ghc.targetPrefix}ghc-pkg field $P version --simple-output); then
            echo "constraint: $P == $ver" >> $out/exactDeps/$P/cabal.config
            echo "constraint: $P installed" >> $out/exactDeps/$P/cabal.config
          fi
        done

        mkdir -p $out/envDeps
        for P in $(${ghc}/bin/${ghc.targetPrefix}ghc-pkg list --simple-output | sed 's/-[0-9][0-9.]*//g'); do
          touch $out/envDeps/$P
          if id=$(${ghc}/bin/${ghc.targetPrefix}ghc-pkg field $P id --simple-output); then
            echo "package-id $id" >> $out/envDeps/$P
          fi
        done
        '';
    } // prev.lib.optionalAttrs (ghc ? dwarf) {
      dwarf = final.makeCompilerDeps ghc.dwarf;
    } // prev.lib.optionalAttrs (ghc ? smallAddressSpace) {
      smallAddressSpace = final.makeCompilerDeps ghc.smallAddressSpace;
    };

}
