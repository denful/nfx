{ lib, ... }:
let
  fn = lib.types.functionTo;
  any = lib.types.anything;

  fxImmediate = lib.types.mkOptionType {
    name = "fxImmediate";
    description = "NFX immediate effect";
    check =
      v:
      builtins.isAttrs v
      && v._type or null == "nfx"
      && v._tag or null == "immediate"
      && v ? state
      && v ? value;
  };

  fxPending = lib.types.mkOptionType {
    name = "fxPending";
    description = "NFX pending effect";
    check =
      v:
      builtins.isAttrs v
      && v._type or null == "nfx"
      && v._tag or null == "pending"
      && v ? ability
      && builtins.isFunction v.ability;
  };

  fxAdapt = lib.types.mkOptionType {
    name = "fxAdapt";
    description = "NFX adapt effect node";
    check =
      v:
      builtins.isAttrs v
      && v._type or null == "nfx"
      && v._tag or null == "adapt"
      && v ? e
      && v ? cmap
      && v ? fmap;
  };

  fxBind = lib.types.mkOptionType {
    name = "fxBind";
    description = "NFX bind effect node (FTCQueue continuation chain)";
    check =
      v:
      builtins.isAttrs v
      && v._type or null == "nfx"
      && v._tag or null == "bind"
      && v ? e
      && v ? queue;
  };

  fx = lib.types.mkOptionType {
    name = "fx";
    description = "NFX effect (immediate, pending, adapt, or bind)";
    check = v: fxImmediate.check v || fxPending.check v || fxAdapt.check v || fxBind.check v;
  };

  extractValue =
    v:
    if builtins.isAttrs v && v ? value && v ? doc && v ? type then
      # This is an mk result, extract its value recursively
      extractValue v.value
    else if builtins.isAttrs v then
      # This is a plain attr set, recurse into it
      lib.mapAttrs (_: extractValue) v
    else
      # Base case: return as-is
      v;

  extractTests =
    v:
    if builtins.isAttrs v && v ? tests then
      v.tests
    else if builtins.isAttrs v && v ? value then
      extractTests v.value
    else if builtins.isAttrs v then
      lib.foldl' (acc: child: acc // extractTests child) { } (builtins.attrValues v)
    else
      { };
in
{
  types = {
    inherit
      fn
      any
      fxImmediate
      fxPending
      fxAdapt
      fxBind
      fx
      ;
  };

  inherit extractValue extractTests;

  mk =
    {
      doc,
      type ? any,
      value,
      tests ? { },
    }:
    {
      inherit
        doc
        type
        value
        tests
        ;
    };
}
