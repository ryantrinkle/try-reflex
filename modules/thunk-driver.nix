{ inputMap, thunkSource, pkgs, ... }: let

  readJSON = x: builtins.fromJSON (builtins.readFile x);

  githubParser = v: json: {
    name = "https://github.com/${json.owner}/${json.repo}/${json.rev}";
    value = {
      srcPath = thunkSource v;
      url = "https://github.com/${json.owner}/${json.repo}";
      rev = json.rev;
    };
  };

  gitlabParser = v: json: {
    name = "https://gitlab.com/${json.owner}/${json.repo}/${json.rev}";
    value = {
      srcPath = thunkSource v;
      url = "https://gitlab.com/${json.owner}/${json.repo}";
      rev = json.rev;
    };
  };
  
  gitParser = v: json: {
    name = "${json.url}/${json.rev}";
    value = {
      srcPath = thunkSource v;
      url = json.url;
      rev = json.rev;
    };
  };

  unpackedParser = v: json: {
    name = "${json.url}/${json.rev}";
    value = {
      srcPath =(thunkSource v).outPath;
      url = json.url;
      rev = json.rev;
    };
  };

  getRev = v: pkgs.runCommandNoCC "getRev" {  } ''
    cd ${v}
    mkdir -p $TMPDIR
    export HOME=$TMPDIR

    mkdir -p $out
    ${pkgs.git}/bin/git config --global --add safe.directory ${v}
    ${pkgs.git}/bin/git rev-parse HEAD | tr -d '\n' > $out/rev
    ${pkgs.git}/bin/git remote get-url origin | tr -d '\n' | sed 's/\.git//g' > $out/url
  '';

  readUnpacked = v: let
    gitThings = getRev v;
    rev = builtins.readFile "${gitThings}/rev";
    url = builtins.readFile "${gitThings}/url";
  in {
    inherit url rev;
  };
  
  checkFor = x: dir: {
    "gitlab" = builtins.readDir dir ? "gitlab.json";
    "github" = builtins.readDir dir ? "github.json";
    "git" = builtins.readDir dir ? "git.json";
  }."${x}";

  parseFor = x: v: {
    "gitlab" = let
      json = readJSON (v + "/gitlab.json");
    in gitlabParser v json;
    "github" = let
      json = readJSON (v + "/github.json");
    in githubParser v json;
    "git" = let
      json = readJSON (v + "/git.json");
    in gitParser v json;
    "unpacked" = let
      json = readUnpacked v;
    in unpackedParser v json;
  }."${x}";

  # jsonReader :: FilePath -> "Text"
  jsonReader = v: if checkFor "github" v then
    "github"
  else if checkFor "gitlab" v then
    "gitlab"
  else if checkFor "git" v then
    "git"
  else "unpacked";
  
  finalParse = v: let
    reader = jsonReader v;
    parsed = parseFor reader v;
  in {
    inherit (parsed) name;
    value = parsed.value.srcPath;
  };

  parser = list: builtins.listToAttrs (builtins.map (a: finalParse a) list);

  cabalProjectGen = list: map (a: let
    reader = jsonReader a;
    parsed = parseFor reader a;
  in ''
    source-repository-package
      type: git
      location: ${parsed.value.url}
      tag: ${parsed.value.rev}
  '') list;
in {
  inputMap = parser inputMap;
  cabalProject = cabalProjectGen inputMap;
}
