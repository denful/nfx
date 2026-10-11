{ lib, config, ... }@top:
let
  nfx = config.nfx.lib;
  ctx = top // {
    inherit nfx api;
  };
  api = import ./api.nix ctx;

  topLevelFiles = [
    ./kernel.nix
    ./basic.nix
    ./functor.nix
    ./monad.nix
    ./provide.nix
    ./sequence.nix
    ./trampoline.nix
  ];

  namespacedFiles = [
    {
      name = "state";
      path = ./state.nix;
    }
    {
      name = "context";
      path = ./context.nix;
    }
    {
      name = "handlers";
      path = ./handlers.nix;
    }
    {
      name = "lens";
      path = ./lens.nix;
    }
    {
      name = "pair";
      path = ./pair.nix;
    }
    {
      name = "request";
      path = ./request.nix;
    }
    {
      name = "zip";
      path = ./zip.nix;
    }
    {
      name = "arrow";
      path = ./arrow.nix;
    }
    {
      name = "and";
      path = ./and.nix;
    }
    {
      name = "acc";
      path = ./acc.nix;
    }
    {
      name = "stream";
      paths = [
        ./stream-core.nix
        ./stream-transform.nix
        ./stream-limit.nix
        ./stream-reduce.nix
        ./stream-combine.nix
      ];
    }
    {
      name = "conditions";
      path = ./conditions.nix;
    }
    {
      name = "result";
      path = ./result.nix;
    }
    {
      name = "rw";
      path = ./rw.nix;
    }
    {
      name = "choice";
      path = ./choice.nix;
    }
    {
      name = "bracket";
      path = ./bracket.nix;
    }
    {
      name = "trampoline";
      path = ./trampoline.nix;
    }
  ];
in
{
  options.nfx.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    description = "NFX algebraic effects library API";
  };

  config.nfx.lib =
    let
      topLevel = lib.mergeAttrsList (map (f: api.extractValue (import f ctx).value) topLevelFiles);
      namespaced = lib.listToAttrs (
        map (file: {
          name = file.name;
          value =
            if file ? paths then
              lib.mergeAttrsList (map (p: api.extractValue (import p ctx).value) file.paths)
            else
              api.extractValue (import file.path ctx).value;
        }) namespacedFiles
      );
    in
    topLevel
    // namespaced
    // {
      inherit (api) types;
    };
}
