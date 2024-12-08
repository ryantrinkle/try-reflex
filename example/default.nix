# Example usage of this project
{
  system ? builtins.currentSystem,
  reflex-platform ? import ../default.nix {
    android_sdk_accept_license = true;
    inherit system;
    allowUnfree = true;
    doPatch = true;
    patches = [
      {
        url = "https://github.com/obsidiansystems/nixpkgs/commit/d39ee6b7c45deb224d95f717bd1e6e2144e09dd9.diff";
        sha256 = "sha256-stn4C43O5M0Qk80gj7YK/87qCDflnm/AwYcOXv5fErI=";
      }
      {
        url = "https://github.com/obsidiansystems/nixpkgs/commit/4516c1a5bb5d11209324bd00239448528bd5fb6d.diff";
        sha256 = "sha256-6GyCvZbuquVS++xR68e+jb4IiFPlIbbJb/kmc9uTers=";
      }
    ];
  },

  nix-thunk ? import ../dep/nix-thunk { },
  thunkInputs ? [
    ../dep/android-activity
    {
      thunk = ../dep/jsaddle;
      subdirs = [
        "jsaddle"
      ];
    }
  ]
}:
reflex-platform.project ({ pkgs, thunkSource, ... }: {
  name = "reflex-todomvc";
  src = thunkSource ../dep/reflex-todomvc;
  compiler-nix-name = "ghc8107Splices";
  ghcjs-compiler-nix-name = "ghcjs8107JSString";
  android = {
    executableName = "reflex-todomvc";
    applicationId = "org.reflexfrp.todomvc";
    displayName = "Reflex TodoMVC";
  };
  ios = {
    executableName = "reflex-todomvc";
    bundleIdentifier = "org.reflexfrp.todomvc";
    bundleName = "Reflex TodoMVC";
  };
  inputThunks = thunkInputs ++ pkgs.obsidianCompilers.thunkSets.aeson-1541;
  shells = [
    "reflex-todomvc"
  ];
  extraSrcFiles = {
    library.extraSrcFiles = [ "style.css" "reflex-todomvc.app" ];
    exes.reflex-todomvc.extraSrcFiles = [
      "style.css"
      "reflex-todomvc.app"
      "reflex-todomvc.app/Info.plist"
    ];
  };
  overrides = [
    ({ config, pkgs, lib, ... }: {
      config.enableShared = if pkgs.stdenv.targetPlatform.isiOS then lib.mkForce false else true;
      config.enableStatic = lib.mkForce true;
    })
    ({ config, pkgs, lib, ... }: {
      packages.reflex-dom = {
	    flags = {
	      webkit2gtk = if (pkgs.stdenv.targetPlatform.isAndroid) then lib.mkForce false else true;
	    };
      };
      packages.reflex-todomvc.components.exes.reflex-todomvc = {
        frameworks = if (!pkgs.stdenv.targetPlatform.isiOS && pkgs.stdenv.targetPlatform.isDarwin) then [ pkgs.darwin.apple_sdk.frameworks.CoreFoundation ] else [ ];
        postInstall = lib.optionalString (pkgs.stdenv.hostPlatform.isDarwin) ''
          mkdir -p $out/reflex-todomvc.app
          cp -r reflex-todomvc.app $out
          cp $out/bin/reflex-todomvc $out/reflex-todomvc.app
        '';
      };
      packages.jsaddle-wkwebview.src = (thunkSource ../dep/jsaddle) + "/jsaddle-wkwebview";
      packages.jsaddle-wkwebview.components.library = {
        frameworks =
          if (pkgs.stdenv.targetPlatform.isiOS) then lib.mkForce [ pkgs.darwin.iosSdkPkgs.sdk pkgs.darwin.apple_sdk.frameworks.CoreFoundation ]
          else [ pkgs.darwin.apple_sdk.frameworks.CoreFoundation ];
      };
    })
    ({ config, lib, ... }: { packages.bitvec.patches = lib.mkForce [ ]; })
  ];
})
