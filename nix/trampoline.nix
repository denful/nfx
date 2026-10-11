{ nfx, api, lib, ... }:
let
  inherit (api) mk;
  inherit (api.types) fn any fxImmediate;

  isAdapt = e: e._tag or null == "adapt";
  isBind = e: e._tag or null == "bind";

  # One iteration for an adapt node — returns next Fx without recursing into adapt chain.
  # Three sub-cases:
  #   inner is immediate → apply fmap
  #   inner is adapt     → peel one layer: compose fmaps so inner resolves first
  #   inner is pending   → extract context via cmap, run ability
  stepAdapt =
    e:
    let
      inner = e.e;
      cmap = e.cmap;
      fmap = e.fmap;
    in
    if fxImmediate.check inner then
      fmap { } inner.state inner.value
    else if isAdapt inner then
      # Compose cmaps: inner context = inner.cmap(cmap(T))
      # Pass cmap(T) (not T) as first arg to inner.fmap, matching what
      # the old pending-based adapt would have passed as the T argument.
      let
        newCmap = t: inner.cmap (cmap t);
        newFmap = t: s: v: {
          _type = "nfx";
          _tag = "adapt";
          e = inner.fmap (cmap t) s v;
          cmap = cmap;
          fmap = fmap;
        };
      in
      {
        _type = "nfx";
        _tag = "adapt";
        e = inner.e;
        cmap = newCmap;
        fmap = newFmap;
      }
    else if isBind inner then
      # Outer adapt wraps a bind node: inject cmap into bind.e, append fmap as final queue step.
      # bind.e runs with cmap-transformed context; queue continuations thread state; fmap closes.
      let
        newE = { _type = "nfx"; _tag = "adapt"; e = inner.e; cmap = cmap; fmap = _t: s: v: nfx.immediate s v; };
        tailCont = s: v: { _type = "nfx"; _tag = "adapt"; e = nfx.immediate s v; cmap = cmap; fmap = fmap; };
      in
      { _type = "nfx"; _tag = "bind"; e = newE; queue = nfx.ftcq.snoc inner.queue tailCont; }
    else
      {
        _type = "nfx";
        _tag = "adapt";
        e = inner.ability (cmap { });
        cmap = cmap;
        fmap = fmap;
      };

  # One iteration for a bind node — O(1) amortized via FTCQueue viewl.
  # When e is immediate: pop head continuation, apply (state, value), continue with tail.
  # When e is bind: flatten nested bind by concatenating queues (O(1) node).
  # Otherwise: advance e one step, keep queue.
  stepBind =
    eb:
    let
      e = eb.e;
      queue = eb.queue;
    in
    if fxImmediate.check e then
      let
        step = nfx.ftcq.viewl queue;
        next = step.head e.state e.value;
      in
      if step.tail == null then next
      else { _type = "nfx"; _tag = "bind"; e = next; queue = step.tail; }
    else if isBind e then
      # Flatten: bind(bind(e0, q0), q1) → bind(e0, node(q0, q1)) — O(1)
      { _type = "nfx"; _tag = "bind"; e = e.e; queue = nfx.ftcq.node e.queue queue; }
    else if isAdapt e then
      { _type = "nfx"; _tag = "bind"; e = stepAdapt e; queue = queue; }
    else
      { _type = "nfx"; _tag = "bind"; e = e.ability { }; queue = queue; };

  # Fast path: direct recursion bounded at 500. Falls to runFxSlow beyond.
  runFxFast =
    e: depth:
    if fxImmediate.check e then
      e.value
    else if depth >= 500 then
      runFxSlow e
    else if isAdapt e then
      runFxFast (stepAdapt e) (depth + 1)
    else if isBind e then
      runFxFast (stepBind e) (depth + 1)
    else
      runFxFast (e.ability { }) (depth + 1);

  # Slow path: builtins.genericClosure — O(1) Nix call stack per step.
  # builtins.seq forces each next to WHNF before key computation, preventing thunk chains.
  runFxSlow =
    e:
    let
      steps = builtins.genericClosure {
        startSet = [ { key = 0; _e = e; } ];
        operator =
          step:
          let
            curr = step._e;
            k = step.key;
          in
          if fxImmediate.check curr then
            [ ]
          else
            let
              next =
                if isAdapt curr then stepAdapt curr
                else if isBind curr then stepBind curr
                else curr.ability { };
            in
            [ { key = builtins.seq next (k + 1); _e = next; } ];
      };
    in
    (lib.last steps)._e.value;

  runFx = e: runFxFast e 0;
in
mk {
  doc = "runFx: trampolined interpreter — fast (≤500) + genericClosure slow paths. Handles immediate/pending/adapt/bind.";
  value = {
    runFx = mk {
      doc = ''
        Trampolined `runFx`. Fast path recurses ≤500 steps; genericClosure beyond.
        Handles all Fx variants: immediate, pending, adapt (iterative peel), bind (FTCQueue).
        O(1) Nix stack depth. `do`/`mapM` chains run in O(N) with O(1) per step.
        `Fx<{}, V> -> V`
      '';
      type = fn any;
      value = runFx;
    };
  };
  tests = {
    "runFx-immediate" = {
      expr = runFx (nfx.immediate { } 42);
      expected = 42;
    };
    "runFx-pending" = {
      expr = runFx (nfx.pending (_: nfx.immediate { } 99));
      expected = 99;
    };
    "runFx-map" = {
      expr = runFx (nfx.map (x: x * 2) (nfx.pure 21));
      expected = 42;
    };
    "runFx-provide" = {
      expr = runFx (nfx.provide { n = 5; } (nfx.pending (ctx: nfx.immediate ctx (ctx.n * 2))));
      expected = 10;
    };
    # 1000 sequential pending steps — O(1) stack via genericClosure.
    "runFx-deep-pending" = {
      expr =
        let
          chain = builtins.foldl'
            (e: _: nfx.pending (_: e))
            (nfx.immediate { } 42)
            (builtins.genList (x: x) 1000);
        in
        runFx chain;
      expected = 42;
    };
    # 600 sequential mapM steps — FTCQueue O(1) bind; each step O(1) via stepBind.
    "runFx-deep-do" = {
      expr =
        let
          chain = builtins.foldl'
            (e: _: nfx.mapM (x: nfx.pure (x + 1)) e)
            (nfx.pure 0)
            (builtins.genList (x: x) 600);
        in
        runFx chain;
      expected = 600;
    };
  };
}
