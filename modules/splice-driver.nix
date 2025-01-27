# NOTE: Splice Driver
# Currently we setup splice loading via "override" modules
# We take a "dummy" packageset to derive names and component names out of
# and nothing else, we generate { packages.${name}.components.${component-name}.${subname} }
# which gets semi-automatically resolved by haskell.nix


{ dontSplice ? [ ] }@top: { attrs, string }:
let
  removeFromList = { toRemove, baseList }: builtins.attrNames (removeAttrs (builtins.listToAttrs (builtins.concatMap (a: [{ name = a; value = a; }]) baseList)) toRemove);
in
builtins.concatMap
  (aname:
  let
    componentnames = removeFromList {
      toRemove = [ "setup" "library" ];
      baseList = let
        eval = builtins.tryEval (builtins.attrNames attrs.${aname}.components);
      in if eval.success then eval.value else [];
    };
    split = builtins.concatMap
      (cname: builtins.concatMap
        (subname:
          if cname == "library" then
            # We check for library here, and pass aname cname cname instead of
            # aname cname subname because library doesn't have any sub-components
            [
              ({ config, lib, ... }: {
                packages = lib.optionalAttrs (config.packages ? ${aname}) {
                  ${aname}.components.${cname}.preBuild = string aname cname cname;
                };
              })
            ]
          else
          [
            ({ config, lib, ... }: {
              packages = lib.optionalAttrs (config.packages ? ${aname}) {
                ${aname}.components.${cname}.${subname}.preBuild = string aname cname subname;
              };
            })
          ]
        )
        (builtins.attrNames attrs.${aname}.components.${cname}))
      componentnames;
  in
  [
    ({ config, lib, ... }: {
      packages = lib.optionalAttrs (config.packages ? ${aname}) {
        ${aname}.components = {
          library.preBuild = string aname "library" "library";
        };
      };
    })
  ] ++ split)
  (removeFromList {
    toRemove = top.dontSplice or [ ];
    baseList = builtins.trace (builtins.attrNames attrs) (builtins.attrNames attrs);
  })
