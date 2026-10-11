{ api, ... }:
let
  inherit (api) mk;

  leaf = f: { _ftcq = true; _tag = "leaf"; f = f; };
  node = l: r: { _ftcq = true; _tag = "node"; left = l; right = r; };

  # O(1) snoc
  snoc = q: f: node q (leaf f);

  # O(1) amortized viewl — rotates left-spine into a right-associated rest chain
  # Returns { head : (S → V → Fx), tail : FTCQueue | null }
  viewl = q: viewl' q null;
  viewl' = q: rest:
    if q._tag == "leaf" then
      { head = q.f; tail = rest; }
    else
      viewl' q.left (if rest == null then q.right else node q.right rest);
in
mk {
  doc = "FTCQueue: binary tree continuation queue — O(1) snoc, O(1) amortized viewl.";
  value = { inherit leaf node snoc viewl; };
  tests = {
    "ftcq-leaf-viewl" = {
      expr = (viewl (leaf (_: _: 42))).head null null;
      expected = 42;
    };
    "ftcq-snoc-tail" = {
      expr =
        let
          q = snoc (leaf (_: _: 1)) (_: _: 2);
          s2 = viewl (viewl q).tail;
        in
        s2.head null null;
      expected = 2;
    };
    "ftcq-order" = {
      expr =
        let
          q = snoc (snoc (leaf (_: _: 10)) (_: _: 20)) (_: _: 30);
          s1 = viewl q;
          s2 = viewl s1.tail;
          s3 = viewl s2.tail;
        in
        [ (s1.head null null) (s2.head null null) (s3.head null null) ];
      expected = [ 10 20 30 ];
    };
    "ftcq-tail-null-after-last" = {
      expr = (viewl (leaf (_: _: 1))).tail == null;
      expected = true;
    };
  };
}
