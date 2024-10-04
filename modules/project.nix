{ pkgs, deps, obsidian, thunkSource, internal ? { } }:

{ name # Name of the current project
, compiler-nix-name ? "ghc8107Splices" # What compiler we should be using
, ghcjs-compiler-nix-name ? "ghcjs8107JSString"
, src # Source of the current project
, packages ? pkgs: { }
, overrides ? [ ] # Overrides to packages
, extraSrcFiles ? { } # ExtraSrcFiles to include in the project builds
, setupCross ? true # Setup cross-compiling
, hackageOverlays ? [ ] # Overlays for hackage, to pass to the cabal solver
, hackage-extra-tarballs ? { }
, extra-hackages ? [ ]
, dontSplice ? [ ] # Packages to not splice
, dontHarden ? [ ] # Packages to not harden
, hardeningOpts ? [ "-fPIC" "-pie" ]
, inputThunks ? [ ]
, inputMap ? {}
# Plugins to extend functionality
, plugins ? [ (_: _: { }) ]
# Packages to be made available to the ghc shell
, shells ? [ ]
, android ? { }
, ios ? { }
, extraCabalProject ? [ ]
, withHoogle ? false
# Alternative for adding --sha256 to cabal
# for source-repository-package use location.tag as the key for the hash
# for repository use the url as the key for the hash
# This is NECESSARY for all source-repository-package/repository entries in the cabal.project file
# The error you would get is "null found expected string"
, sha256map ? null
, pkg-def-extras ? []
, extraArgs ? { }
, workon ? ""
, shellTools ? {
    cabal = "3.2.0.0";
    #hlint = "latest";
    #haskell-language-server = "latest";
  }
, index-state ? null
, ...
}@bot_args:

pkgs.lib.makeExtensible (self: let
  foldExtensions = a: builtins.foldl' pkgs.lib.composeExtensions (_: _: { }) a;

  unsafeGetPositionMsg = {
    attr ? "",
    set ? {},
    msg ? pos: ""
  }: let
    # We could use __unsafeGetAttrPos instead of builtins.unsafeGetAttrPos but it freaks out IDEs
    _pos = builtins.unsafeGetAttrPos attr set;
  in x: __trace ("${_pos.file}:${toString _pos.line} -- " + (msg _pos)) x;

  pkgdef-extras = (bot_args.pkg-def-extras or [])
    ++ pkgs.lib.optionals (builtins.hasAttr "extraPkgDef" self) self.extraPkgDef;

  combinedOverlays = pkgs.lib.optionals (hackageOverlays != []) hackageOverlays
    ++ pkgs.lib.optionals (builtins.hasAttr "extraOverlays" self) self.extraOverlays;

  hackage-driver = import ./hackage-driver.nix {
    pkgs = pkgs;
    modules = combinedOverlays;
  };

  inputMapDriver = import ./thunk-driver.nix {
    inherit thunkSource pkgs;
    inputMap = inputThunks ++ [
      pkgs._dep.source.attoparsec
      #pkgs._dep.source.aeson
    ];
  };

  parsePackages = p: [ ("packages: " + builtins.concatStringsSep ", " (pkgs.lib.mapAttrsToList (k: v: "${v}") (packages p))) ];

  inherit (import ../dep/gitignore.nix { inherit (pkgs) lib; }) gitignoreSource;

  # Driver to generate a fake hackage
  src-driver = { pkgs }: import ./src-driver.nix {
    inherit pkgs;
    src = gitignoreSource src;
    extraCabalProject =
      bot_args.extraCabalProject or []
      ++ inputMapDriver.cabalProject or []
      ++ extraArgs.extraCabalProject or []
      ++ parsePackages pkgs;
  };

  checkHackageOverlays = c: v: if combinedOverlays == [ ] then c else v;

  # Base project without any extensions added
  baseProject = (pkgs.haskell-nix.project' {
    inherit name compiler-nix-name sha256map index-state;
    inputMap = inputMapDriver.inputMap // inputMap;
    pkg-def-extras = pkgdef-extras;
    src = src-driver { inherit pkgs; };
    cabal-install = bot_args.cabal-install or null;
    extra-hackage-tarballs = (checkHackageOverlays {} hackage-driver.extra-hackage-tarballs) // hackage-extra-tarballs;
    extra-hackages = (checkHackageOverlays [] hackage-driver.extra-hackages) ++ extra-hackages;

    modules = [
      { packages."${name}".components = extraSrcFiles; }
      # Setup the saving part of splices unconditionally
      ({ config, lib, ... }: {
        config.preBuild = ''
          echo "!!! Save Splices $out/lib/haskell.nix/$pname"
          export EXTERNAL_SPLICES_SAVE="$out/lib/haskell.nix/$pname"
        '';
      })
    ] ++ overrides ++ hackage-driver.package-overlays ++ inputMapDriver.overrides;
  });
in baseProject.extend (foldExtensions ([
  (final: prev: rec {
    inherit self;
    #inherit self;
    inherit hackage-driver;
    #inherit (self) hackageOverlays;
    # Self includes everything used in the baseProject
    helpers = {
      inputMap = inputMapDriver;
      inherit bot_args;
      inherit plugins;
      inherit obsidian pkgs hackage-driver;
      inherit deps baseProject;
      inherit src;
      finalSrc = src-driver { inherit (self) pkgs; };
    };

    __unsafe = {
      shells = bot_args.shells;
      bot_args = bot_args;
    };
    # Null out haskell.nix's default cross setup, since it doesn't work
    # properly
    projectCross = builtins.abort "Haskell.nix projectCross isn't supported!";

    # This constructs a "fake" hackage to pull different packages from
    # this is used in case that something on proper hackage doesn't have
    # the version bounds for packages that we need to properly solve
    # the current project

    # Outputs:
    #  buildCommands - commands to build the generatedHackage jsons
    #  generatedHackage - generated hackage setup
    #  package-overlays - overlays to setup src properly after the solver has succeeded
    #  extra-hackage-tarballs - generated tarballs to be passed to the cabal solver
    #  extra-hackages - alias to (import generatedHackage) - use this in the project'
   # inherit hackage-driver;

    # Package overlays generated via the hackage driver
    packageOverlays = {
      packages = builtins.listToAttrs (builtins.concatMap (a: [{
        name = toString (builtins.attrNames a.packages);
        value = a.packages.${toString (builtins.attrNames a.packages)};
      }]) hackage-driver.package-overlays);
    };
    # hackage-driver = import ./modules/hackage-driver.nix { pkgs = pkgs; modules = hackageOverlays; };

    shell-driver = import ./shell-driver.nix {
      inherit crossSystems withHoogle shellTools;
      inherit (bot_args) shells;
      exactDeps = true;
      project = final;
      unsafeMsg = unsafeGetPositionMsg;
    };
    shells = rec {
      default = shell-driver {
        crossBuilds = [ "ghcjs" ];
      };

      ghc = shell-driver {
        crossBuilds = [ ];
        packages = packages self.pkgs;
        srcdir = builtins.toPath src;
      };

      ghcjs = shell-driver {
        targetSystem = "ghcjs";
        justCross = true;
      };
    };

    ios = rec {
      impl = {
        iOSaarch64 = (import ./ios/default.nix {
          inherit pkgs;
          packageset = crossSystems.iphone64;
        });
      };

      app = {
        aarch64 = impl.iOSaarch64 {
          package = p: p.${name}.components.exes.${name};
          executableName = bot_args.ios.name or "${name}";
          bundleIdentifier = if !bot_args.ios ? bundleIdentifier
          then builtins.abort "Need iOS bundleIdentifier"
            else bot_args.ios.bundleIdentifier;
          bundleName = if !bot_args.ios ? bundleName
            then builtins.abort "Need iOS bundleName"
            else bot_args.ios.bundleName;
        };
      };
    };
    android = rec {
      impl = {
        android = (import ./android/default.nix {
          inherit (pkgs) pkgs buildPackages;
          acceptAndroidSdkLicenses = true;
          # Pass the crossPkgs android-prebuilt package set
          pkg-set = crossSystems.aarch64-android-prebuilt.pkg-set;
        });

        android-x86 = (import ./android/default.nix {
          inherit (pkgs) pkgs buildPackages;
          acceptAndroidSdkLicenses = true;
          pkg-set = crossSystems.x86_64-linux-android-prebuilt.pkg-set;
        });
      };

      app = {
        aarch64 = impl.android.buildApp {
          # Package is currently just filler
          package = p: p."${name}".components.exes."${name}";
          executableName = bot_args.android.name or "${name}";
          applicationId = if !bot_args.android ? applicationId
            then builtins.abort "Need android appID"
            else bot_args.android.applicationId;
          displayName = if !bot_args.android ? displayName
            then builtins.abort "Need Android displayName"
            else bot_args.android.displayName;
        };
        x86_64 = impl.android-x86.buildApp {
          package = p: p."${name}".components."${name}";
          executableName = bot_args.android.name or "${name}";
          applicationId = if !bot_args.android ? applicationId
            then builtins.abort "Need android appID"
            else bot_args.android.applicationId;
          displayName = if !bot_args.android ? displayName
            then builtins.abort "Need Android displayName"
            else bot_args.android.displayName;
        };
    };
    };
    # The android app builder currently assumes you just pass the base name of the package
    # to the builder, and we convert it to "lib${name}.so" in there

    # Easy way to get to the ghcjs app
    ghcjs-app = crossSystems.ghcjs.pkg-set.config.hsPkgs."${name}".components.exes."${name}";

    workOn = import ./workon.nix {
      inherit pkgs;
      inputMap = inputMapDriver.inputMap;
      cabalProject = inputMapDriver.cabalProject;
      pkg-set = final.pkg-set.config.packages;
    };

    workOnShell = (workOn ({
      package = bot_args.workon.package or builtins.throw "WorkOn needs a package!";
      inherit compiler-nix-name;
    } // workon)).shell;

    workOnTest = workOn {
      package = "jsaddle-warp";
      #pkg-set = final.pkg-set.config.packages;
      allowNewer = [
        "lens"
        "aeson"
        "attoparsec"
      ];
      inherit compiler-nix-name;
    };
    # Usage of cross-driver sets up all of the various splices cruft to
    # make an easy way to setup cross-compiling with splices
    crossSystems = builtins.mapAttrs
      (a: v: import ./cross-driver.nix {
        # Project name and source
        inherit name;
        src = src-driver { pkgs = v; };

        inherit sha256map;
        inherit index-state;
        inputMap = inputMapDriver.inputMap // inputMap;

        # Haskell.nix derives is ghcjs off of the compiler-nix-name
        # so ghc8107Splices won't cut it here
        compiler-nix-name = if a == "ghcjs" then ghcjs-compiler-nix-name else compiler-nix-name;

        # Make sure to inherit the proper overrides from the hackage-driver
        # Reference ./modules/hackage-driver.nix for more details
        extra-hackage-tarballs = checkHackageOverlays { } hackage-driver.extra-hackage-tarballs;
        extra-hackages = checkHackageOverlays [ ] hackage-driver.extra-hackages;
        inherit (final) pkg-set;

        # CrossPkgs is the attrset of the current crossSystem in the mapAttrs
        crossPkgs = v;

        # Driver to automatically setup splices
        # Reference ./modules/splice-driver.nix for more details
        splice-driver = import ./splice-driver.nix {
          dontSplice = [ "fgl" "Cabal" "android-activity" ] ++ dontSplice; # Packages to not load splices for
        };

        # Driver to auto-apply hardening options
        # Reference ./modules/hardening-driver.nix for more details
        hardening-driver = (import ./hardening-driver.nix {
          dontHarden = [ "happy" "binary" "${name}" ] ++ dontHarden; # Packages to not apply hardening to
          hardeningOpts = if v.targetPlatform.isiOS then [] else hardeningOpts;
        });
        overrides = [
          # Easier override for users to set extra files from the package src to be included in build
          { packages.${name}.components = extraSrcFiles; }

          # Move this later, not hacky but should be in android configs specifically, due to some linker args
          # and how we combine this with gradle
          ({ config, lib, pkgs, ... }: {
            packages.${name} = {
              components.exes = lib.optionalAttrs (pkgs.stdenv.targetPlatform.isAndroid) {
                "${name}" = {
                  ghcOptions = [
                    "-shared"
                    "-fPIC"
                    "-threaded"
                    "-no-hs-main"
                    "-lHSrts_thr"
                    "-lffi"
                    "-lm"
                    "-llog"
                  ];
                  configureFlags = [
                    "--ld-options=-shared"
                    "--ld-options=-no-pie"
                    "--ld-options=-Wl,--gc-sections,--version-script=${../exts/android/haskellActivity.version},-u,Java_systems_obsidian_HaskellActivity_haskellStartMain,-u,hs_main"
                  ];
                };
              };
            };
          })
        ] ++ overrides ++ hackage-driver.package-overlays;
      })
      pkgs.pkgsCross;
  })
] ++ plugins)))
