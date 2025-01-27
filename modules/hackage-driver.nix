# NOTE(dgreen):
# Haskell.nix doesn't currently have a way to overlay packages on the hackage index
# so this is what this does
# We generate a dummy hackage for the cabal solver to use, which if our constraints match up they will
# pull from our local "overlay" hackage

# Based off of
# https://github.com/ilyakooo0/haskell-nix-extra-hackage/blob/master/default.nix
# https://github.com/mlabs-haskell/mlabs-tooling.nix/blob/main/mk-hackage.nix
# Makes it a bit more basic
{ pkgs, compiler-nix-name ? "ghc925",  modules ? [ ]  }: let
  packageDef = { name, version, src, signatures ? [ ], type ? "Targets", expires ? null }: {
    inherit signatures;
    signed = {
      "_type" = type;
      inherit expires;
      targets = {
        "<repo>/package/${name}-${version}.tar.gz" = {
          hashes = {
            sha256 = builtins.hashFile "sha256" "${src}/${name}.cabal";
          };
          length = 1;
        };
      };
      version = 0;
    };
  };

  genBuildCommands = defs: map (a: let
    name = a.name;
    version = a.version;
    json = builtins.toFile "${a.name}.json" (builtins.toJSON (packageDef { inherit (a) name version src; }));
  in ''
    mkdir -p $packagedef/${name}/${version}
    cp ${json} $packagedef/${name}/${version}/package.json
    cp ${a.src}/*.cabal $packagedef/${name}/${version}
  '') defs;

  writePackageDefs = defs: pkgs.runCommand "index.tar.gz" {
    outputs = [ "packagedef" "out" ];
  } ''
    set -eux
    ${builtins.concatStringsSep "\n" defs}
    mkdir -p $packagedef
    cd $packagedef
    tar --sort=name --owner=root:0 --group=root:0 --mtime='UTC 2009-01-01' -hczvf $out */*/*
  '';

  genHackageForNix = hackagetar: pkgs.runCommand "hackage-for-nix" { } ''
    cp ${hackagetar} 01-index.tar.gz
    ${pkgs.gzip}/bin/gunzip 01-index.tar.gz
    ${pkgs.haskell-nix.nix-tools.${compiler-nix-name}}/bin/hackage-to-nix $out 01-index.tar "https://hackagefornix/"
  '';

  hackageOverlay = defs: rec {
    inherit modules;
    buildCommands = genBuildCommands defs;
    generatedHackage = genHackageForNix extra-hackage-tarballs.overlay;
    package-overlays = map (a: {config, lib, ... }: {
       packages = lib.optionalAttrs (config.packages ? ${a.name}) {
         ${a.name}.src = a.src;
       };
     }) (defs);
    extra-hackage-tarballs = {
      overlay = (writePackageDefs buildCommands).out;
    };
    extra-hackages = [
      (import generatedHackage)
    ];
  };

in (hackageOverlay modules)
