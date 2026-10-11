{
  self,
  nixpkgs,
  nix-unit,
}:
let
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

  systems = nixpkgs.lib.systems.flakeExposed;

  forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

  nfxLib =
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    import ./.. pkgs.lib;

  # Extract tests using a fixed-point to avoid infinite recursion
  extractTests =
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      api = import ./api.nix { lib = pkgs.lib; };

      # Combined file list for documentation
      allFiles =
        (map (f: {
          name = builtins.baseNameOf (toString f);
          path = f;
        }) topLevelFiles)
        ++ namespacedFiles;

      nfx = pkgs.lib.fix (
        self:
        let
          ctx = {
            lib = pkgs.lib;
            config.nfx.lib = self;
            nfx = self;
            inherit api;
          };

          # Merge top-level files (kernel, combinators)
          topLevel = pkgs.lib.mergeAttrsList (map (f: api.extractValue (import f ctx).value) topLevelFiles);

          # Wrap namespaced files
          namespaced = pkgs.lib.listToAttrs (
            map (file: {
              name = file.name;
              value =
                if file ? paths then
                  pkgs.lib.mergeAttrsList (map (p: api.extractValue (import p ctx).value) file.paths)
                else
                  api.extractValue (import file.path ctx).value;
            }) namespacedFiles
          );
        in
        topLevel
        // namespaced
        // {
          types = api.types;
        }
      );

      # Now extract tests with fully working nfx
      # Use api.extractTests which knows how to traverse mk results
      libCtx = {
        lib = pkgs.lib;
        config.nfx.lib = nfx;
        inherit nfx api;
      };

      fileNames = [
        {
          name = "kernel";
          path = ./kernel.nix;
        }
        {
          name = "basic";
          path = ./basic.nix;
        }
        {
          name = "functor";
          path = ./functor.nix;
        }
        {
          name = "monad";
          path = ./monad.nix;
        }
        {
          name = "provide";
          path = ./provide.nix;
        }
        {
          name = "sequence";
          path = ./sequence.nix;
        }
      ]
      ++ namespacedFiles;

      # Extract tests from all files and flatten to test suite
      extractAllTests = pkgs.lib.foldl' (
        acc: file:
        let
          # Handle both single path and multiple paths
          filesToTest = if file ? paths then file.paths else [ file.path ];

          # Extract tests from each file
          fileTests = pkgs.lib.foldl' (
            facc: p:
            let
              mkResult = import p libCtx;
              tests = api.extractTests mkResult;
            in
            facc // tests
          ) { } filesToTest;
        in
        acc
        // pkgs.lib.mapAttrs' (testName: test: {
          name = "${file.name} ${testName}";
          value = { inherit (test) expr expected; };
        }) fileTests
      ) { } fileNames;
    in
    extractAllTests;

in
{
  lib = forAllSystems nfxLib;

  tests = extractTests "x86_64-linux";

  packages = forAllSystems (
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;
      api = import ./api.nix { inherit lib; };

      # Reuse file lists
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

      # Build full nfx for doc extraction
      nfx = lib.fix (
        self:
        let
          ctx = {
            inherit lib api;
            config.nfx.lib = self;
            nfx = self;
          };
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
          types = api.types;
        }
      );

      allFiles =
        (map (f: {
          name = builtins.baseNameOf (toString f);
          path = f;
        }) topLevelFiles)
        ++ namespacedFiles;
    in
    {
      docs = import ./doc-generator.nix {
        inherit
          pkgs
          lib
          nfx
          api
          ;
        fileList = allFiles;
      };

      mdbook = import ./mdbook.nix {
        inherit pkgs;
        docs = import ./doc-generator.nix {
          inherit
            pkgs
            lib
            nfx
            api
            ;
          fileList = allFiles;
        };
      };
    }
  );

  apps = forAllSystems (
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;
      api = import ./api.nix { inherit lib; };

      # Build full nfx for doc extraction
      nfx = lib.fix (
        self:
        let
          ctx = {
            inherit lib api;
            config.nfx.lib = self;
            nfx = self;
          };
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
          types = api.types;
        }
      );

      allFiles =
        (map (f: {
          name = builtins.baseNameOf (toString f);
          path = f;
        }) topLevelFiles)
        ++ namespacedFiles;

      docs = import ./doc-generator.nix {
        inherit
          pkgs
          lib
          nfx
          api
          ;
        fileList = allFiles;
      };

      mdbook = import ./mdbook.nix {
        inherit pkgs docs;
      };
    in
    {
      mdbook = {
        type = "app";
        program = "${pkgs.writeShellScript "mdbook-server" ''
          echo "Building mdbook site..."
          echo "Output available at: ${mdbook}"
          echo ""
          echo "Starting mdbook server..."
          cd ${mdbook}
          exec ${pkgs.mdbook}/bin/mdbook serve --open
        ''}";
      };
    }
  );

  checks = forAllSystems (
    system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      nix-unit-pkg = nix-unit.packages.${system}.default;
    in
    {
      tests = pkgs.runCommand "nfx-tests" { nativeBuildInputs = [ nix-unit-pkg ]; } ''
        export HOME="$(realpath .)"
        nix-unit --eval-store "$HOME" \
          --extra-experimental-features 'flakes pipe-operator' \
          --override-input nixpkgs ${nixpkgs} \
          --flake ${self}#tests
        touch $out
      '';
    }
  );

}
