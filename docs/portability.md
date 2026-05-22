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

Each producer target must build given only its declared dependencies on
the layers below it. The portability test enforces this empirically:

Refreshed 2026-05-22 (PR #908). The four legacy `Shared*` sub-targets
(`SharedCore`, `SharedUtils`, `SharedModels`, `SharedConfiguration`)
were absorbed into `SharedConstants` per #536. The closures-to-Observer
epic added 5 new `*Models` seams (Indexer / Distribution / Cleanup /
CoreSampleCode / RemoteSync). #837 added `EnrichmentModels` for the
postprocessor pipeline. `Logging` moved from Foundation to Infrastructure
(it is a writer concrete; only `LoggingModels` is foundation-only).
`ReleaseTool` + `ConstraintsGen` added to Apps.

- **Foundation**: `SharedConstants`, `LoggingModels`, `Resources`,
  `MCPCore`, `MCPSharedTools`
- **Models** (foundation-only protocol seams; `*Models` companions):
  `CoreProtocols`, `SearchModels`, `SampleIndexModels`, `ServicesModels`,
  `CorePackageIndexingModels`, `CrawlerModels`, `IndexerModels`,
  `DistributionModels`, `CleanupModels`, `CoreSampleCodeModels`,
  `RemoteSyncModels`, `EnrichmentModels`
- **Infrastructure**: `ASTIndexer`, `Diagnostics`, `Logging` (the writer
  concrete; only composition roots may import it)
- **Features**: `AppleConstraintsKit`, `Availability`, `Cleanup`, `Core`,
  `CoreJSONParser`, `CorePackageIndexing`, `CoreSampleCode`, `Crawler`,
  `Distribution`, `Enrichment` (write-side coupling, pending #906),
  `Indexer`, `Ingest`, `MCPSupport`, `RemoteSync`, `SampleIndex`,
  `Search`, `SearchToolProvider`, `Services`, `MCPClient`
- **Apps**: `CLI`, `MCP`, `TUI`, `MockAIAgent`, `ReleaseTool`,
  `ConstraintsGen` (composition roots, allowed to import any feature)

For the per-target allowed-imports contract, see
`docs/package-import-contract.md`.

## Background

Standalone packages with GoF as the design ideal. Closes the loop on the
GoF protocol-DI arc (#494–#508), Phase B import purity (#503–#506),
Crawler purification (#508), and the dead-manifest-dep cleanup (#516).
After that arc, every feature target imports only its declared deps. The
portability test proves it.
