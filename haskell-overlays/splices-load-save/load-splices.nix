{ haskellLib, fetchFromGitHub, lib, splicedHaskellPackages, isExternalPlugin }:

self: super:

let splicedPkg = drv:
      if builtins.hasAttr (attrName drv) self.buildHaskellPackages
      then builtins.getAttr (attrName drv) self.buildHaskellPackages
      else if builtins.hasAttr drv.pname self.buildHaskellPackages
      then builtins.getAttr drv.pname self.buildHaskellPackages
      else throw "no spliced pkg for: ${drv.name}";

    hasSplicedPkg = drv:
      (builtins.hasAttr drv.pname self.buildHaskellPackages ||
        builtins.hasAttr (attrName drv) self.buildHaskellPackages) &&
      !(builtins.elem drv.pname nonHsPkgs);

    # splicedPkg returns null for those
    nonHsPkgs = [ "android-activity" ];

    attrName = drv:
      "${drv.pname}_${lib.replaceStrings ["."] ["_"] drv.version}";

    spliceDir = drv: let splicedDrv = splicedPkg drv; in
      if splicedDrv == null
      then throw "splicedDrv == null for drv = ${drv.pname}"
      else if splicedDrv.compiler == null
      then throw "spliceDrv.compiler == null"
      else "${splicedDrv}/lib/${splicedDrv.compiler.name}/${splicedDrv.name}";

    # Base steps for every preBuild phase
    preBuildBaseAttrs = drv:
      {
        preBuild = ''
          ${drv.preBuild or ""}
          echo "!!! has splices: ${if hasSplicedPkg drv then "yes" else "no"}"
          echo "!!! splices at: ${if hasSplicedPkg drv then spliceDir drv else "N/A"} !!!"
        '';
      };
    # Additional preBuilds steps if the compiler supports external plugins
    # E.g. GHC version > 8.6
    preBuildExternalPluginAttrs = drv: lib.optionalAttrs (hasSplicedPkg drv && isExternalPlugin)
      {
        preBuild = ''
          export EXTERNAL_SPLICES_LOAD=${spliceDir drv}
        '';
      };
in {
  buildHaskellPackages = splicedHaskellPackages;

  # Add some flags to load splices from nativeHaskellPackages
  mkDerivation = drv: super.mkDerivation (drv //
    {
      buildFlags = lib.optional (hasSplicedPkg drv && !isExternalPlugin) "--ghc-option=-load-splices=${spliceDir drv}"
                ++ (drv.buildFlags or []);
      preBuild = (preBuildBaseAttrs drv).preBuild + ((preBuildExternalPluginAttrs drv).preBuild or "");
    });
}
