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
    # Pinned to the exact nota-next commit schema-next + schema-rust-next
    # build against (record 1057 alignment): 5e063042 exposes the two-
    # level StructureHeader without the later overflow-marking change that
    # diverges schema-next's structure-header test. All three repos pin
    # this commit so cargo's lock unification is consistent in Nix.
    nota-next-source = {
      url = "github:LiGoldragon/nota-next/5e063042fffe5c58e0345ccadbadf863b07859c1";
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
          # The record-1054 plane surface witness: the emitted Plane is a
          # single DATA-CARRYING enum whose variants carry the actual
          # plane messages with the auto-created origin route (records
          # 1038/1039) folded onto the root as the leading tuple element —
          # NOT a thin kind tag beside a separate envelope (record 1052).
          plane-surface-data-carrying = pkgs.runCommand "horizon-next-plane-surface-data-carrying" { } ''
            grep -R "pub enum Plane {" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "Signal(OriginRoute, Input)," ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "Nexus(OriginRoute, Input)," ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "Sema(OriginRoute, Output)," ${src}/horizon/src/schema/horizon.rs >/dev/null
            # The origin route is auto-created runtime substrate (1038/1039).
            grep -R "pub struct OriginRoute(pub Integer);" ${src}/horizon/src/schema/horizon.rs >/dev/null
            touch $out
          '';
          # The running three-engine chain witness (records 1028/1030):
          # the three trait-ordered engines and Plane::drive are emitted,
          # and the consumer wires + drives them with a test that pushes a
          # real Horizon projection request end to end through all three.
          running-three-engine-chain = pkgs.runCommand "horizon-next-running-three-engine-chain" { } ''
            # The three engines are emitted as Plane -> Plane traits.
            grep -R "pub trait SignalEngine" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "pub trait NexusEngine" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "pub trait SemaEngine" ${src}/horizon/src/schema/horizon.rs >/dev/null
            grep -R "pub fn drive<Signal, Nexus, Sema>(" ${src}/horizon/src/schema/horizon.rs >/dev/null
            # The consumer implements the three engines on real nouns.
            grep -R "impl SignalEngine for SignalGate" ${src}/horizon/src/lib.rs >/dev/null
            grep -R "impl NexusEngine for ProjectionNexus" ${src}/horizon/src/lib.rs >/dev/null
            grep -R "impl SemaEngine for ProjectionSema" ${src}/horizon/src/lib.rs >/dev/null
            # The chain-driving test pushes a request through all three.
            grep -R "request_drives_signal_then_nexus_then_sema_and_echoes_origin_route" ${src}/horizon/tests/three_engine_chain.rs >/dev/null
            grep -R "each_plane_crossing_is_visible_and_typed" ${src}/horizon/tests/three_engine_chain.rs >/dev/null
            touch $out
          '';
          # The types-only-module witness (report /42 D3): horizon-core is
          # a pure types-only module — its schema is Imports + Namespace
          # with NO signal plane, and its emitted Rust carries NO runtime
          # floor (no Plane, no OriginRoute, no NexusMail). The floor lives
          # once in the horizon component, not duplicated into the type
          # library.
          types-only-core-has-no-runtime-floor = pkgs.runCommand "horizon-next-types-only-core-has-no-runtime-floor" { } ''
            # The schema declares no signal plane (two-position document).
            ! grep -R "(Input" ${src}/core/schema/magnitude.schema
            ! grep -R "(Output" ${src}/core/schema/magnitude.schema
            # The emitted core carries the type, but none of the floor.
            grep -R "pub enum Magnitude" ${src}/core/src/schema/magnitude.rs >/dev/null
            ! grep -R "pub enum Plane" ${src}/core/src/schema/magnitude.rs
            ! grep -R "pub struct OriginRoute" ${src}/core/src/schema/magnitude.rs
            ! grep -R "pub struct NexusMail" ${src}/core/src/schema/magnitude.rs
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
