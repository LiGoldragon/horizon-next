# Intent

`horizon-next` is the concept that proves Horizon's datatypes generate from a
PURE schema, demonstrated end to end with real artifacts and a Nix witness.

Psyche intent (2026-05-28, records 1048 / 1049 / 1050 / 1034):

*Build a working concept prototype that generates all needed Horizon datatypes
from a pure schema, demonstrated step by step — schema source, imports,
assembled schema, emitted Rust — actually running, with the REAL artifacts
shown at each step. Prior schema-stack work read as marketing; the requirement
is to SEE a fully-working pipeline, not be told it works. If something does not
work, show that honestly too.*

*Horizon's runtime shape is open (signal-only? triad? library?). The concept
illuminates the shape, it does not force it. Declaring `Input`/`Output` makes
Horizon a signal-leaning component; that is what this concept demonstrates,
while leaving the pure-library and full-triad alternatives on the table.*

*Collections are the enabling step (record 1034): the cluster proposal is
collection-bearing, and it could not emit while a schema type reference was a
bare name. The positional, collection-name-first forms — `Vec <element>`,
`KeyValueMap <key> <value>`, and `Option <inner>` — express the collections at
reference positions.*

## What this repository is

A two-crate workspace. `horizon-core` is the shared-types crate that declares
`Magnitude` (the cross-crate trust noun). `horizon-next` is the component: its
`schema/horizon.schema` imports `Magnitude`, declares Horizon's `Input`
(`Project ClusterProposal`) and `Output` (`Projected <map>` / `Rejected
ProjectionError`), and uses `KeyValueMap` / `Vec` / `Option` for the cluster
aggregate roots. The cluster proposal, the per-node config, and the projection
output are all schema-emitted; only the projection BEHAVIOR is hand-written, as
a method on the emitted `ClusterProposal` noun.

## Why it exists

It closes the `/40` feasibility audit's first-and-decisive gate with running
code: with collections landed in schema-next + schema-rust-next, the
collection-bearing Horizon aggregate roots emit as schema-driven nouns. It also
mirrors the `schema-core` cross-crate import proof (record /39) so the imported
`Magnitude` is referenced, not re-declared.

## Honest concept-stage limits

- The cluster slice is scaled (nodes / services / cache / trust); the real
  `horizon-rs` `ClusterProposal` carries far more collection fields.
- `ClusterTrust` emits as a newtype because it is single-field (the existing
  one-field-becomes-newtype rule).
- The runtime shape is demonstrated, not decided — the concept shows the
  datatypes generate regardless of which shape Horizon ultimately takes.
