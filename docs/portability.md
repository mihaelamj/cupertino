# Target Portability

Every producer target (Models, Foundation, Features, Infra) must be liftable
from the monorepo as a standalone Swift package without dragging undeclared
concerns along. This is what "standalone packages" means in practice: a
user copies `Sources/<Target>/` into a fresh repository with a minimal
`Package.swift` listing only the target's declared dependencies, and it
builds.

## How to verify

`scripts/check-target-portability.sh` lifts a target plus its transitive
dependency closure into `/tmp/cupertino-portability-<target>/`, generates a
minimal `Package.swift` for that subset, and runs `xcrun swift build` (or
`swift test` with `--test`).

```
scripts/check-target-portability.sh Services
scripts/check-target-portability.sh Services --test
scripts/check-target-portability.sh Crawler
```

A green run proves the target can be lifted out without touching the
monorepo's `Package.swift` for hidden dependencies.

## What it catches

The script is the empirical companion to `scripts/check-package-purity.sh`:

- **Purity** answers "do you import what you declare?" — forbids consumer
  imports of unrelated producer concretes.
- **Portability** answers "do you declare what you actually need?" —
  forbids manifest entries that under-declare. SwiftPM is lenient about
  cross-target imports within the same package; the lift-out test exposes
  those cracks.

Example caught during initial rollout: `ServicesModels` imported
`SampleIndexModels` in eight formatter files but the manifest only
declared `["SearchModels", "SharedCore", "SharedConstants"]`. Build was
green in the monorepo because SwiftPM resolved the sibling module
anyway. The portability harness failed loudly:

```
error: no such module 'SampleIndexModels'
```

Fix was a one-line addition to the manifest. Without the harness this
gap would have survived until someone tried to actually lift the target
out.

## Layered constraint

The architecture, from `CLAUDE.md`:

```
Foundation -> Infrastructure -> Features -> Apps   (one direction only)
```

Refreshed 2026-05-22 (PR #908). The Foundation, Models, and Features
bullets below mirror `scripts/check-target-foundation-only.sh`'s
`FOUNDATION_TIER` + `MODELS_TARGETS` + `STRICT_PRODUCERS` arrays
respectively (the audit script is the source of truth). Two
additional bullets enumerate documented producers that the script
arrays do NOT cover, so the doc is a superset, not an exact mirror.
Changes since the previous refresh: the four legacy `Shared*`
sub-targets (`SharedCore`, `SharedUtils`, `SharedModels`,
`SharedConfiguration`) were absorbed into `SharedConstants` per #536;
the closures-to-Observer epic added 5 new `*Models` seams
(Indexer / Distribution / Cleanup / CoreSampleCode / RemoteSync);
#837 added `EnrichmentModels` for the postprocessor pipeline;
`ReleaseTool` + `ConstraintsGen` added to Apps; `AppleConstraintsKit`
(PR #908) added to Features.

Each producer target must build given only its declared dependencies on
the layers below it. The portability test enforces this empirically.

- **Foundation** (allowed to every producer): `SharedConstants`,
  `LoggingModels`, `Resources`, `Diagnostics`, `ASTIndexer`, `MCPCore`,
  `MCPSharedTools`. (`Diagnostics` wraps SQLite3 for read-only probes;
  `ASTIndexer` wraps SwiftSyntax. Both are foundation-tier by
  construction because they have no actors with I/O beyond their
  declared system-framework deps.)
- **Models** (foundation-only protocol seams + value-type / constants
  targets; allowed to every producer): `CoreProtocols`, `CrawlerModels`,
  `CorePackageIndexingModels`, `SearchModels`, `SampleIndexModels`,
  `ServicesModels`, `IndexerModels`, `DistributionModels`,
  `CleanupModels`, `CoreSampleCodeModels`, `RemoteSyncModels`,
  `EnrichmentModels`, `SearchSchema`. (`CoreProtocols` is grouped with
  the seams despite the unsuffixed name. `SearchSchema` carries the
  search.db DDL SQL constants + `Search.Schema.currentVersion`; lifted
  out of the Search target by #898 sub-PR A.)
- **Features** (the producers in the `STRICT_PRODUCERS` array's
  Phase 3 block): `AppleConstraintsKit`, `Availability`, `Cleanup`,
  `Core`, `CoreJSONParser`, `CorePackageIndexing`, `CoreSampleCode`,
  `Crawler`, `Distribution`, `Enrichment`, `Indexer`, `Ingest`,
  `Logging`, `MCPSupport`, `RemoteSync`, `SampleIndex`,
  `SampleIndexSQLite`, `SearchAPI`, `SearchSQLite`, `SearchToolProvider`,
  `Services`. (`Logging` is a writer concrete: the audited feature
  producer over `LoggingModels` + `OSLog`, and composition roots are
  the only places that may import the `Logging` target. Producers
  import `LoggingModels` only. The two `*SQLite` producers
  (`SearchSQLite` and `SampleIndexSQLite`) are the SQLite-backed
  concretes for their `*Models` protocol seams; both now audit
  cleanly against the strict rule after the domain-types lift in
  #898F let `SearchSQLite` drop its `import Search`. `Enrichment`
  graduated in #906 once the 6 sibling passes were rewired to take
  `any Search.IndexWriter` / `any Search.PackageWriter` /
  `any Sample.Index.Writer` via init injection.)
- **No documented producers remain outside `STRICT_PRODUCERS`.** The
  prior holdouts (`Enrichment`, `SearchSQLite`) both graduated:
  `Enrichment` via the protocol-rewire in #906, `SearchSQLite` via
  the domain-types lift in #898F. Every producer documented in
  `docs/package-import-contract.md`'s Producers table is now audited
  against the foundation-only allow-list, and
  `check-package-purity.sh`'s `GRANDFATHERED_TARGETS` array is empty.
- **Other producers not audited by these scripts**: `MCPClient` is
  declared in `Package.swift` but is consumed only by the test target
  + MockAIAgent; it does not pass through the `STRICT_PRODUCERS` or
  `MODELS_TARGETS` allow-lists today (pre-existing gap; tracked
  separately for the strict-DI epic).
- **Apps** (composition roots, allowed to import any feature):
  `CLI`, `TUI`, `MockAIAgent`, `ReleaseTool`, `ConstraintsGen`.
  (Library targets `MCPCore`, `MCPClient`, `MCPSupport`,
  `MCPSharedTools` are NOT apps; the MCP server runs inside the
  `CLI` binary via `cupertino serve`.)

For the per-target allowed-imports contract, see
`docs/package-import-contract.md`.

## Background

Standalone packages with GoF as the design ideal. Closes the loop on the
GoF protocol-DI arc (#494–#508), Phase B import purity (#503–#506),
Crawler purification (#508), and the dead-manifest-dep cleanup (#516).
After that arc, every feature target imports only its declared deps. The
portability test proves it.
