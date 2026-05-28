# ARCHITECTURE — horizon-next

## Purpose

`horizon-next` is the running concept that Horizon's datatypes generate from a
PURE schema. It demonstrates, end to end and in Nix, the schema-derived stack
on the real Horizon domain: the cluster proposal and its projection are emitted
from `schema/horizon.schema`, not hand-written. It exists to answer two
questions with WORKING code rather than prose:

1. Can the collection-bearing Horizon aggregate roots (`ClusterProposal`,
   `NodeProposal`) be schema-emitted? — yes, once collections land
   (psyche record 1034, the `/40` first-and-decisive gate).
2. What runtime shape does Horizon take? — the schema declares it as a
   COMPONENT with an `Input` (`Project ClusterProposal`) and an `Output`
   (`Projected <map>` / `Rejected ProjectionError`), so it is signal-leaning.

## Workspace shape

A two-member Cargo workspace, modelled on `schema-core` (the cross-crate import
proof, record /39):

```text
horizon-next/                    # workspace root + flake
├── core/                        # package horizon-core — the shared-types crate
│   ├── Cargo.toml               #   links = "horizon-core"
│   ├── build.rs                 #   lowers schema/magnitude.schema; emits schema-dir metadata
│   ├── schema/magnitude.schema  #   declares Magnitude (the shared trust noun)
│   └── src/schema/magnitude.rs  #   checked-in generated Rust
└── horizon/                     # package horizon-next — the component crate
    ├── Cargo.toml               #   depends on horizon-core
    ├── build.rs                 #   reads DEP_HORIZON_CORE_SCHEMA_DIR; resolves the import
    ├── schema/horizon.schema    #   imports horizon-core:magnitude:Magnitude; ClusterProposal etc.
    ├── src/schema/horizon.rs    #   checked-in generated Rust (collections + import alias)
    ├── src/lib.rs               #   the projection METHOD on the emitted ClusterProposal
    └── tests/projection.rs      #   constructs a real cluster + projects it
```

## The pipeline

```text
horizon/schema/horizon.schema
  -> horizon/build.rs
       -> reads DEP_HORIZON_CORE_SCHEMA_DIR (Cargo sets it from horizon-core's links metadata)
       -> ImportResolver::with_dependency("horizon-core", <dir>, "0.1.0")
       -> SchemaEngine::lower_source_with_resolver(horizon.schema, .., resolver)
            -> nota-next parses the four-position document into blocks
            -> schema-next lowers: imports resolved, macros applied, collection
               TypeReferences (Vector / Map / Optional) built at field + variant positions
            -> Asschema (the assembled schema)
       -> RustEmitter emits src/schema/horizon.rs:
            pub use horizon_core::schema::magnitude::Magnitude as Magnitude;
            pub struct ClusterProposal { pub nodes: BTreeMap<NodeName, NodeProposal>, .. }
            pub enum Output { Projected(BTreeMap<NodeName, NodeConfig>), Rejected(ProjectionError) }
       -> build.rs freshness-checks the checked-in src/schema/horizon.rs
```

The Rust this crate hand-writes is ONLY the behavior: `ClusterProposal::project`
and `NodeProposal::project_node` are methods on the schema-emitted nouns. The
data shapes are generated; changing a shape means editing the schema and
regenerating, never hand-editing `src/schema/horizon.rs`.

## What the schema exercises

`schema/horizon.schema` is built to demonstrate the full feature set on a
representative slice of the real `horizon-rs` `ClusterProposal`:

- **KeyValueMap** — `ClusterProposal.nodes: BTreeMap<NodeName, NodeProposal>`
  and the `Output::Projected(BTreeMap<NodeName, NodeConfig>)` variant.
- **Vec** — `NodeProposal.services`, `ClusterProposal.cluster_services`.
- **Option** — `ClusterProposal.cache: Option<BinaryCache>`,
  `NodeConfig.cache: Option<CacheUrl>`.
- **Cross-crate import** — `Magnitude` from `horizon-core`, used at
  `ClusterTrust.cluster`, `NodeProposal.trust`, `NodeConfig.trust`.
- **Four-position document** — imports + Input + Output + namespace.

## Runtime-shape note (open)

Declaring `Input`/`Output` makes Horizon a SIGNAL-leaning component: the
projection is `Project -> Projected`. This is the shape the concept
demonstrates. It is not the only option — a pure-library Horizon would want a
types-only module (the `/39` gap), and a full triad would add a Sema plane for
durable cluster state. The concept shows the datatypes generate regardless of
which runtime shape is chosen; the choice stays open.

## The Nix witness

`nix flake check` (crane, modelled on spirit-next + schema-core) builds the
whole pipeline, compiles the emitted Rust, runs the projection tests, and
asserts the collection fields + the cross-crate import alias are present in the
generated source. The flake vendors the `collections-horizon-2026-05-28`
branches of schema-next and schema-rust-next.

## Concept-stage limits (honest)

- `ClusterTrust` is a single-field record, so it emits as a newtype
  (`ClusterTrust(pub Magnitude)`) rather than a named-field struct — the
  existing one-field-becomes-newtype rule. Multi-field records (`NodeProposal`,
  `ClusterProposal`, `NodeConfig`) emit as named-field structs.
- The slice is scaled: the real `horizon-rs` `ClusterProposal` carries ~10
  collection fields across users / domains / secrets / vpn / ai; this concept
  keeps nodes + services + cache + trust to stay demonstrable.
- The map NOTA encoding is a brace of `key value` pairs; ordering is the
  `BTreeMap` key order (deterministic).
