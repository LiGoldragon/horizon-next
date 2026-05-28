{
  description = "horizon-next — Horizon as a schema-driven component (collections + cross-crate import concept)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
    nota-next-source = {
      url = "github:LiGoldragon/nota-next";
      flake = false;
    };
    schema-next-source = {
      url = "github:LiGoldragon/schema-next/collections-horizon-2026-05-28";
      flake = false;
    };
    schema-rust-next-source = {
      url = "github:LiGoldragon/schema-rust-next/collections-horizon-2026-05-28";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, fenix, crane
    , nota-next-source
    , schema-next-source
    , schema-rust-next-source
  }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        toolchain = fenix.packages.${system}.stable.withComponents [
          "cargo"
          "rustc"
          "rustfmt"
          "clippy"
          "rust-src"
        ];
        craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
        # The .schema files are build-script inputs (lowered to Rust by
        # build.rs). crane's default source filter strips non-cargo
        # files, so the schema directories must be re-admitted — for
        # both crates, since the horizon crate's build.rs reads
        # horizon-core's schema dir through DEP_HORIZON_CORE_SCHEMA_DIR.
        schemaFilter = path: type:
          type == "regular" && pkgs.lib.hasSuffix ".schema" path;
        sourceFilter = path: type:
          (craneLib.filterCargoSources path type) || (schemaFilter path type);
        cleanSource = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = sourceFilter;
          name = "source";
        };
        src = pkgs.runCommand "horizon-next-source-with-local-schema-patches" {
          notaNextSource = nota-next-source;
          schemaNextSource = schema-next-source;
          schemaRustNextSource = schema-rust-next-source;
        } ''
          cp -R ${cleanSource} $out
          chmod -R u+w $out
          mkdir -p $out/vendor-sources
          cp -R "$notaNextSource" $out/vendor-sources/nota-next
          cp -R "$schemaNextSource" $out/vendor-sources/schema-next
          cp -R "$schemaRustNextSource" $out/vendor-sources/schema-rust-next

          cat >> $out/Cargo.toml <<'EOF'
          [patch."https://github.com/LiGoldragon/nota-next.git"]
          nota-next = { path = "vendor-sources/nota-next" }

          [patch."https://github.com/LiGoldragon/schema-next.git"]
          schema-next = { path = "vendor-sources/schema-next" }

          [patch."https://github.com/LiGoldragon/schema-rust-next.git"]
          schema-rust-next = { path = "vendor-sources/schema-rust-next" }
          EOF

          sed -i '\|^source = "git+https://github.com/LiGoldragon/nota-next.git?branch=main#|d' $out/Cargo.lock
          sed -i '\|^source = "git+https://github.com/LiGoldragon/schema-next.git?branch=collections-horizon-2026-05-28#|d' $out/Cargo.lock
          sed -i '\|^source = "git+https://github.com/LiGoldragon/schema-rust-next.git?branch=collections-horizon-2026-05-28#|d' $out/Cargo.lock
        '';
        cargoVendorDirectory = craneLib.vendorCargoDeps { inherit src; };
        commonArguments = {
          inherit src cargoVendorDirectory;
          strictDeps = true;
        };
        cargoArtifacts = craneLib.buildDepsOnly commonArguments;
      in
      {
        packages.default = craneLib.buildPackage (commonArguments // { inherit cargoArtifacts; });
        checks = {
          build = craneLib.cargoBuild (commonArguments // { inherit cargoArtifacts; });
          test = craneLib.cargoTest (commonArguments // { inherit cargoArtifacts; });
          fmt = craneLib.cargoFmt { inherit src; };
          clippy = craneLib.cargoClippy (commonArguments // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- -D warnings";
          });
          # The collection gate witness (record 1034): the emitted
          # Horizon Rust must carry the BTreeMap / Vec / Option fields
          # and the projection-output map variant. If a regression
          # silently drops collection emission, this fails.
          collections-emitted = pkgs.runCommand "horizon-next-collections-emitted" { } ''
            grep -R "pub nodes: std::collections::BTreeMap<NodeName, NodeProposal>" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "pub cluster_services: Vec<ServiceName>" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "pub cache: Option<BinaryCache>" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "Projected(std::collections::BTreeMap<NodeName, NodeConfig>)" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "pub struct NotaCollection" ${src}/horizon/src/schema/horizon.rs >/dev/null
            touch $out
          '';
          # The cross-crate import witness (record /39): Magnitude is
          # REFERENCED from horizon-core via a use alias, never
          # re-declared in the horizon module.
          cross-crate-import-emitted = pkgs.runCommand "horizon-next-cross-crate-import-emitted" { } ''
            grep -R "pub use horizon_core::schema::magnitude::Magnitude as Magnitude;" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "impl From<horizon_core::schema::magnitude::NotaDecodeError> for NotaDecodeError" ${src}/horizon/src/schema/horizon.rs >/dev/null
            ! grep -R "pub enum Magnitude" ${src}/horizon/src/schema/horizon.rs
            grep -R "pub enum Magnitude" ${src}/core/src/schema/magnitude.rs >/dev/null
            touch $out
          '';
          # The projection-as-method-on-schema-noun witness: project is
          # an inherent method on the emitted ClusterProposal, not a
          # free function.
          projection-on-schema-noun = pkgs.runCommand "horizon-next-projection-on-schema-noun" { } ''
            grep -R "impl ClusterProposal" ${src}/horizon/src/lib.rs >/dev/null
            grep -R "pub fn project(&self) -> Output" ${src}/horizon/src/lib.rs >/dev/null
            grep -R "projection_drops_distrusted_nodes_and_keeps_trusted_ones" ${src}/horizon/tests/projection.rs >/dev/null
            grep -R "cluster_proposal_round_trips_through_nota" ${src}/horizon/tests/projection.rs >/dev/null
            touch $out
          '';
          # Build scripts and library code carry no module-level free
          # functions except main (workspace Rust discipline).
          no-production-free-functions = pkgs.runCommand "horizon-next-no-production-free-functions" { } ''
            if grep -R -n -E '^(pub(\([^)]*\))? )?fn ' \
              ${src}/core/build.rs ${src}/core/src/lib.rs \
              ${src}/horizon/build.rs ${src}/horizon/src/lib.rs \
              | grep -v -E ':(fn main\()'; then
              echo "production Rust must not use module-level free functions except main" >&2
              exit 1
            fi
            touch $out
          '';
          local-schema-source-patches = pkgs.runCommand "horizon-next-local-schema-source-patches" { } ''
            grep -R 'patch."https://github.com/LiGoldragon/schema-next.git"' ${src}/Cargo.toml >/dev/null
            grep -R 'patch."https://github.com/LiGoldragon/schema-rust-next.git"' ${src}/Cargo.toml >/dev/null
            test -d ${src}/vendor-sources/schema-next
            test -d ${src}/vendor-sources/schema-rust-next
            touch $out
          '';
        };
        devShells.default = pkgs.mkShell {
          name = "horizon-next";
          packages = [ pkgs.jujutsu pkgs.pkg-config toolchain ];
        };
      });
}
