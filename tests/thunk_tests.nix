{ system ? builtins.currentSystem }:
let
  nixpkgs = import ../dep/nixpkgs {};
  nix-thunk = import ../dep/nix-thunk { pkgs = nixpkgs; };
  exampleFunc = attrs: import ../example (attrs // { inherit system; });
  getOutPath = attr: attr.outPath;
  runTests = list: thunkPacked.pkgs.runCommandNoCC "tests" {} (builtins.concatStringsSep "\n" list);

  testCheck = {
    msgSuccess ? "",
    msgFail ? "",
    condition
  }: ''
     if [[ ${condition} ]]; then
        echo -e "\e[1;32mSUCCESS:\e[0m ${msgSuccess}"
     else
        echo -e "\e[1;31mERROR:\e[0m ${msgFail}"
     fi | tee -a $out
  '';

  jsaddle_src = nix-thunk.thunkSource ../dep/jsaddle;

  createGitRepo = thunkPacked.pkgs.runCommandNoCC "source" {} ''
    cp -r ${jsaddle_src} $out
    chmod -R +w $out
    cd $out
    mkdir -p $TMP
    export HOME=$TMP
    ${thunkPacked.pkgs.git}/bin/git init
    ${thunkPacked.pkgs.git}/bin/git add .
    ${thunkPacked.pkgs.git}/bin/git config user.email "null@null.com"
    ${thunkPacked.pkgs.git}/bin/git config user.name "null"
    ${thunkPacked.pkgs.git}/bin/git commit -m "Initial Commit"
    ${thunkPacked.pkgs.git}/bin/git remote add origin git@github.com:obsidiansystems/jsaddle
  '';

  checkPaths = {
    "==" = attr1: attr2: let
      outPath1 = getOutPath attr1;
      outPath2 = getOutPath attr2;
    in testCheck {
      msgSuccess = "OutPath1: ${outPath1} is the same as OutPath2: ${outPath2}";
      msgFail = "OutPath1: ${outPath1} is not the same as OutPath2: ${outPath2}";
      condition = "${outPath1} == ${outPath2}";
    };
    "!=" = attr1: attr2: let
      outPath1 = getOutPath attr1;
      outPath2 = getOutPath attr2;
    in testCheck {
      msgFail = "OutPath1: ${outPath1} is the same as OutPath2: ${outPath2}";
      msgSuccess = "OutPath1: ${outPath1} is not the same as OutPath2: ${outPath2}";
      condition = "${outPath1} != ${outPath2}";
    };
  };

  thunkPacked = exampleFunc {
    thunkInputs = [
      {
        thunk = ../dep/jsaddle;
        subdirs = [
          "jsaddle"
          "jsaddle-warp"
        ];
      }
    ];
  };

  thunkNonDir = exampleFunc {
    thunkInputs = [
      {
        thunk = (nix-thunk.thunkSource ../dep/jsaddle);
        subdirs = [
          "jsaddle"
          "jsaddle-warp"
        ];
      }
    ];
  };

  thunkGitHub = exampleFunc {
    thunkInputs = let
      json = builtins.fromJSON (builtins.readFile ../dep/jsaddle/github.json);
    in [
      {
        thunk = thunkPacked.pkgs.fetchFromGitHub {
          owner = "${json.owner}";
          repo = "${json.repo}";
          rev = "${json.rev}";
          sha256 = "${json.sha256}";
        };
        subdirs = [
          "jsaddle"
          "jsaddle-warp"
        ];
      }
    ];
  };

  /*thunkGit = exampleFunc {
    thunkInputs = [
      {
        thunk = createGitRepo;
        subdirs = [
          "jsaddle"
          "jsaddle-warp"
        ];
      }
    ];
  };
  */
  thunkUnpacked = exampleFunc {
    thunkInputs = [
      {
        thunk = if
          builtins.readDir ../dep/jsaddle ? "github.json"
        then
          builtins.trace ("Thunk ${toString ../dep/jsaddle} not unpacked, this may fail or not produce correct results!") ../dep/jsaddle
        else
          ../dep/jsaddle;
        subdirs = [
          "jsaddle"
          "jsaddle-warp"
        ];
      }
    ];
  };
in {
  testOut = runTests [
    (checkPaths."==" (thunkPacked.hsPkgs.jsaddle.components.library) (thunkPacked.hsPkgs.jsaddle.components.library))
    (checkPaths."==" (thunkPacked.hsPkgs.jsaddle.components.library) (thunkNonDir.hsPkgs.jsaddle.components.library))
    #(checkPaths."==" (thunkPacked.hsPkgs.jsaddle.components.library) (thunkGitHub.hsPkgs.jsaddle.components.library))
    (checkPaths."==" (thunkPacked.hsPkgs.jsaddle.components.library) (thunkUnpacked.hsPkgs.jsaddle.components.library))
    (checkPaths."!=" (thunkPacked.hsPkgs.jsaddle.components.library) ({ outPath = "null"; }))
  ];
  inherit jsaddle_src createGitRepo;
}
