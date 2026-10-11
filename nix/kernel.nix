{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types)
    fn
    fx
    fxImmediate
    fxPending
    ;
in
mk {
  doc = "Core kernel primitives for the NFX effect system";
  value = {
    immediate = mk {
      doc = ''
        Creates an immediate (already resolved) effect.

        An immediate effect is the terminal case of the Fx type - it carries
        both a state and a value, meaning it needs no further context to
        produce its result. This is one of two fundamental constructors for
        the Fx algebraic data type.

        ## Type Signature
        `state -> value -> Fx<state, value>`

        ## Parameters
        - `state`: The current state/context that was used to produce the value
        - `value`: The computed result

        ## Example
        ```nix
        immediate {} 42  # Effect holding value 42 with empty state
        immediate { count = 1; } "done"  # Effect with state and string value
        ```

        ## See Also
        - `pending` - The other Fx constructor for suspended computations
        - `runFx` - Evaluates an effect to extract its value
      '';
      type = fxImmediate;
      value = state: value: {
        _type = "nfx";
        _tag = "immediate";
        inherit state value;
      };
      tests = {
        "creates immediate fx" = {
          expr = api.types.fxImmediate.check (nfx.immediate { } 42);
          expected = true;
        };
        "stores value" = {
          expr = (nfx.immediate { } 42).value;
          expected = 42;
        };
        "stores state" = {
          expr = (nfx.immediate { x = 1; } 42).state;
          expected = {
            x = 1;
          };
        };
      };
    };

    pending = mk {
      doc = ''
        Creates a pending (suspended) effect awaiting context.

        A pending effect wraps an "ability" - a function that will be called
        given context to produce the next step of computation. This is the
        mechanism by which effects express their requirements: the ability
        requests something from the context.

        ## Type Signature
        `(context -> Fx<S, V>) -> Fx<S, V>`

        ## Parameters
        - `ability`: A function `context -> Fx<S, V>` that consumes context
          and produces the next computation step

        ## Example
        ```nix
        # Effect that reads a number from context and doubles it
        pending (n: immediate n (n * 2))

        # Effect requesting an attribute from context
        pending (ctx: immediate ctx ctx.username)
        ```

        ## See Also
        - `immediate` - The terminal case, already has its value
        - `adapt` - The fundamental combinator for transforming effects
      '';
      type = fxPending;
      value = ability: {
        _type = "nfx";
        _tag = "pending";
        inherit ability;
      };
      tests = {
        "creates pending fx" = {
          expr = api.types.fxPending.check (nfx.pending (_: nfx.immediate { } 1));
          expected = true;
        };
        "stores ability" = {
          expr = builtins.isFunction (nfx.pending (s: nfx.immediate s 1)).ability;
          expected = true;
        };
      };
    };

    adapt = mk {
      doc = ''
        The fundamental combinator - everything else builds on this.

        `adapt` is the core primitive that enables all effect transformations.
        It simultaneously handles:
        1. **Contravariant mapping** of context requirements (what the effect needs)
        2. **Covariant mapping** of continuations (what happens given the result)

        ## Type Signature
        `Fx<S,V> -> (T -> S) -> (T -> S -> V -> Fx<T,U>) -> Fx<T,U>`

        ## Parameters
        - `e`: The effect to transform
        - `cmap`: Context mapper `T -> S` - extracts inner requirement from outer context
        - `fmap`: Continuation `(T, S, V) -> Fx<T,U>` - transforms the result

        ## How It Works
        Creates an adapt node `{ _tag="adapt", e, cmap, fmap }` — a pure data
        structure. The interpreter (`runFx`) peels adapt nodes iteratively,
        eliminating the O(N) stack growth that a recursive closure would cause.

        ## Example
        ```nix
        # Double the result of an effect
        adapt (pure 21) (s: s) (_t: _s: v: immediate {} (v * 2))
        ```

        ## See Also
        - `map` - Simpler value transformation (built on adapt)
        - `contraMap` - Simpler context transformation (built on adapt)
      '';
      type = fn (fn (fn fx));
      value = e: cmap: fmap: {
        _type = "nfx";
        _tag = "adapt";
        inherit e cmap fmap;
      };
      tests = {
        "type check" = {
          expr = api.types.fn.check nfx.adapt;
          expected = true;
        };
        "adapt immediate applies fmap" = {
          expr = nfx.runFx (
            nfx.adapt (nfx.immediate { } 10) (x: x) (
              _t: _s: v:
              nfx.immediate { } (v * 2)
            )
          );
          expected = 20;
        };
        "adapt transforms context via cmap" = {
          expr = nfx.runFx (
            nfx.adapt (nfx.pending (n: nfx.immediate n (n * 10))) (_: 5) (
              _t: _s: v:
              nfx.immediate { } v
            )
          );
          expected = 50;
        };
      };
    };
  };
}
