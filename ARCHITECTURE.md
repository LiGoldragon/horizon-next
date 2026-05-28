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

## The Plane runtime surface + the running three-engine chain

Beyond datatype generation, the concept now demonstrates the runtime model
(records 1054 / 1038 / 1039 / 1028 / 1030):

- **`Plane` — the data-carrying plane surface (record 1054).** The emitter
  generates a single enum `Plane` whose `Signal` / `Nexus` / `Sema` variants
  CARRY the actual plane messages. Runtime code matches DIRECTLY on the plane —
  it is NOT a thin kind tag beside a separate envelope (record 1052 names that
  shape wrong). For Horizon: `Signal(OriginRoute, Input)` is the ingress,
  `Sema(OriginRoute, Output)` is the reply.
- **OriginRoute folded onto the root (records 1038/1039).** The auto-created
  origin route is the leading tuple element of each `Plane` variant. It is
  minted at ingress (`Plane::at_ingress`), threaded through every engine hop,
  and echoed back on the reply `Plane`. It also rides on `NexusMail` /
  `MessageSent` / `MessageProcessed`.
- **The three trait-ordered engines (record 1028).** `SignalEngine::admit`,
  `NexusEngine::execute`, `SemaEngine::apply` — each `Plane -> Plane`. The
  concept's `src/lib.rs` implements them on real data-bearing nouns:
  `SignalGate` (admission policy), `ProjectionNexus` (runs `ClusterProposal::
  project`), `ProjectionSema` (owns the durable last-projection map).
- **`Plane::drive` — the RUNNING chain (record 1030).** It threads a request
  Signal → Nexus → Sema and returns the reply, echoing the origin route. This
  is a chain that ACTUALLY DRIVES, not emitted-but-dead scaffolding.
  `tests/three_engine_chain.rs` pushes a real Horizon projection request end to
  end through all three engines and asserts the projected output + the echoed
  route; a second test drives the engines one crossing at a time so each plane
  boundary is visible (the `skills/testing.md` per-plane-chain-typing rule).

So Horizon's runtime shape, left open by record 1050, is here shown as a
component whose Signal/Nexus/Sema planes are one coherent `Plane` enum driven by
the three engines.

## Types-only `horizon-core` (no vestigial signal plane)

`horizon-core` is now a pure TYPES-ONLY module (report /42 D3). Its
`schema/magnitude.schema` is the two-position document `{} { Magnitude (...) }`
— Imports + Namespace, NO `Input` / `Output`. The emitted `magnitude.rs`
therefore carries ONLY the `Magnitude` type + its NOTA codec; it has no `Plane`,
no `OriginRoute`, no `NexusMail`, no runtime floor at all (dropped from ~520 to
~150 lines). The generic runtime floor lives once in the `horizon` component and
is no longer duplicated into the imported type library — the concrete instance
of report /42's D2.

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
