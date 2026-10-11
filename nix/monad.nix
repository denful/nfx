{ nfx, api, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fx;
in
mk {
  doc = "Monadic operations for sequencing and binding effects";
  value = {
    mapM = mk {
      doc = ''
        Monadic bind within the same context type.

        Sequences effects where the second depends on the first's value.
        Both effects must have the same context type.

        ## Type Signature
        `(V -> Fx<S, U>) -> Fx<S, V> -> Fx<S, U>`

        ## Parameters
        - `f`: A function producing an effect `V -> Fx<S, U>`
        - `e`: The first effect

        ## Example
        ```nix
        # Chain computations
        mapM (x: pure (x * 2)) (pure 21)  # => Fx producing 42

        # State threading
        provide { n = 10; }
          (mapM
            (x: pending (ctx: immediate ctx (x + ctx.n)))
            (value 5))  # => 15
        ```

        ## Laws
        - Left identity: `mapM f (pure x) == f x`
        - Right identity: `mapM pure e == e`
        - Associativity: `mapM g (mapM f e) == mapM (x: mapM g (f x)) e`

        ## See Also
        - `flatMap` - When continuation has different context
        - `then'` - When first value is ignored
      '';
      type = fn (fn fx);
      value =
        f: e:
        let
          # Continuation: run (f value) with current state as context, keep output state.
          # Equivalent to: contraMap (_: s) (_: s2: s2) (f v)
          cont = s: v: nfx.adapt (f v) (_: s) (_o: i: u: nfx.immediate i u);
        in
        if e ? _tag && e._tag == "bind" then
          # Snoc onto existing FTCQueue — O(1) vs building deeper adapt nesting
          { _type = "nfx"; _tag = "bind"; e = e.e; queue = nfx.ftcq.snoc e.queue cont; }
        else
          { _type = "nfx"; _tag = "bind"; e = e; queue = nfx.ftcq.leaf cont; };
      tests = {
        "mapM sequences effects" = {
          expr = nfx.runFx (nfx.mapM (x: nfx.pure (x * 2)) (nfx.pure 21));
          expected = 42;
        };
        "mapM threads state" = {
          expr = nfx.runFx (
            nfx.provide { n = 10; } (
              nfx.mapM (x: nfx.pending (ctx: nfx.immediate ctx (x + ctx.n))) (nfx.value 5)
            )
          );
          expected = 15;
        };
      };
    };

    then' = mk {
      doc = ''
        Sequences two effects, discarding the first value.

        Runs the first effect for its side effects (state changes), then
        runs the second effect and returns its value. Named with quote
        to avoid conflict with reserved words.

        ## Type Signature
        `Fx<S, U> -> Fx<S, V> -> Fx<S, U>`

        ## Parameters
        - `next`: Effect to run second (its value is returned)
        - `e`: Effect to run first (its value is discarded)

        ## Example
        ```nix
        then' (pure 42) (pure 1)  # => Fx producing 42
        ```

        ## See Also
        - `mapM` - When second effect depends on first value
        - `andThen` - When effects have different contexts
      '';
      type = fn (fn fx);
      value = next: e: nfx.mapM (_: next) e;
      tests = {
        "then sequences and discards first" = {
          expr = nfx.runFx (nfx.then' (nfx.pure 42) (nfx.pure 1));
          expected = 42;
        };
      };
    };

    flatMap = mk {
      doc = ''
        Monadic bind that combines different context requirements.

        Unlike `mapM` where both effects share context, `flatMap` handles
        the case where the first effect needs context `S` and the continuation
        produces effects needing context `R`. The result requires both.

        ## Type Signature
        `(V -> Fx<R, U>) -> Fx<S, V> -> Fx<{fst: S, snd: R}, U>`

        ## Parameters
        - `f`: Continuation producing effect using different context
        - `e`: First effect

        ## Example
        ```nix
        provide { fst = 10; snd = 5; } (
          flatMap
            (x: pending (r: immediate r (x + r)))
            (pending (s: immediate s s))
        )  # => 15
        ```

        ## Notes
        Use `mapM` when both effects have the same context type.
        Use `flatMap` when combining effects using different requirements.

        ## See Also
        - `mapM` - Same-context sequencing
        - `andThen` - Like flatMap but discards first value
      '';
      type = fn (fn fx);
      value =
        f: e:
        nfx.adapt e (ctx: ctx.fst) (
          _: s: v:
          nfx.adapt (f v) (ctx: ctx.snd) (
            _: r: u:
            nfx.contraMap (_: {
              fst = s;
              snd = r;
            }) (_: ctx: ctx) (nfx.value u)
          )
        );
      tests = {
        "flatMap combines requirements" = {
          expr = nfx.runFx (
            nfx.provide {
              fst = 10;
              snd = 5;
            } (nfx.flatMap (x: nfx.pending (r: nfx.immediate r (x + r))) (nfx.pending (s: nfx.immediate s s)))
          );
          expected = 15;
        };
      };
    };

    andThen = mk {
      doc = ''
        Chains two effects using different contexts, discarding the first value.

        Like `flatMap` but the second effect is constant (doesn't depend on
        first value). Useful for sequencing heterogeneous effects.

        ## Type Signature
        `Fx<T, U> -> Fx<S, V> -> Fx<{fst: S, snd: T}, U>`

        ## Parameters
        - `next`: Effect to run second (its value is returned)
        - `e`: Effect to run first (its value is discarded)

        ## Example
        ```nix
        provide { fst = 10; snd = "hello"; } (
          andThen
            (pending (s: immediate s s))  # Returns "hello"
            (pending (n: immediate n (n * 2)))
        )  # => "hello"
        ```

        ## See Also
        - `then'` - Same-context version
        - `flatMap` - When second depends on first value
      '';
      type = fn (fn fx);
      value = next: e: nfx.flatMap (_: next) e;
      tests = {
        "andThen chains different contexts" = {
          expr = nfx.runFx (
            nfx.provide {
              fst = 10;
              snd = "hello";
            } (nfx.andThen (nfx.pending (s: nfx.immediate s s)) (nfx.pending (n: nfx.immediate n (n * 2))))
          );
          expected = "hello";
        };
      };
    };
  };
}
