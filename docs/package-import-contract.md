# Per-package import contract

Single source of truth for what each target is **allowed** to import. Anything else in `^import` lines under that target's `Sources/` is a **violation** of the strict-DI / standalone-portability rules.

Last refresh: 2026-05-22 (#895 hygiene PR). Adds the `EnrichmentModels` seam (introduced by #837 for the postprocessor pipeline) to the `*Models` allow-list and to the audit-script `MODELS_TARGETS` + `STRICT_PRODUCERS` arrays, adds the `AppleConstraintsKit` producer to `STRICT_PRODUCERS` (was already documented here but never audited), updates the `Search` row to list `EnrichmentModels`, and adds an `EnrichmentModels` Models-tier row. The `Enrichment` producer is flagged here but intentionally not yet in `STRICT_PRODUCERS`; its 6 sibling passes import `Search` + `SampleIndex` concretes directly, which #906 (child of epic #893) is set up to fix. Previous refresh: 2026-05-15, after #536 phases 0 / 1a-1d / 2a, when the four legacy `Shared*` sub-targets (`SharedCore`, `SharedUtils`, `SharedModels`, `SharedConfiguration`) were absorbed into `SharedConstants` and `Core.PackageIndexing.GitHubCanonicalizer` + `Core.PackageIndexing.ExclusionList` moved out of `CoreProtocols`.

## The target regime (post-#536)

**Goal:** every producer target plus its `*Models` companion is a standalone-portable unit. Pull out `(Search + SearchModels)` into a fresh repo with the foundation tier and it builds against external SwiftPM deps alone.

**Allowed imports for a producer target:**

1. **External primitives** — `Foundation`, `OSLog`, `os`, `Combine`, `SQLite3`, `SwiftSyntax`, `SwiftParser`, `ArgumentParser`, `Testing`, `XCTest`, `WebKit`, `AppKit`, `UIKit`, `SwiftUI`, `CryptoKit`, `FoundationNetworking`, system frameworks (`Darwin`, `Glibc`). Ambient — always allowed.
2. **Foundation tier (Cupertino-side, foundation-only by construction)** — `SharedConstants`, `LoggingModels`, `Resources`, `Diagnostics`, `ASTIndexer`, `MCPCore`, `MCPSharedTools`. Any producer may import any of these.
3. **`*Models` protocol seams + foundation-only constants targets**: `CoreProtocols`, `CrawlerModels`, `CorePackageIndexingModels`, `SearchModels`, `SampleIndexModels`, `ServicesModels`, `IndexerModels`, `DistributionModels`, `CleanupModels`, `CoreSampleCodeModels`, `RemoteSyncModels`, `EnrichmentModels`, `SearchSchema`. Any producer may import its own + any other producer's seam (the seams are foundation-only by contract; importing a seam carries no behavioural coupling).

**Forbidden for a producer:**

- Another producer's concrete writer target (e.g. `Search` cannot `import Indexer`).
- `Logging` (the writer concrete). Only `LoggingModels` allowed.
- `SharedCore`, `SharedUtils`, `SharedModels`, `SharedConfiguration` — these were absorbed into `SharedConstants` during #536 phase 1; they no longer exist.
- `Shared.Constants.BinaryConfig.shared` or any `Shared.Constants.defaultX` static accessor (deleted in #535).

## Why this shape

Validated against five independent references (see `mihaela-agents/Rules/swift/per-package-import-contract.md` for the full audit):

- **GoF (1994) Strategy p. 315 / Factory Method p. 107** — protocol/Strategy lives in a single interface; concretes live in conformer targets.
- **Apple SwiftNIO** — `NIOCore` (foundation-only protocols) + `NIOPosix` (concrete impl).
- **Apple swift-log (SSWG)** — single foundation-only `Logging` target with `LogHandler` protocol + pure-Swift defaults.
- **Point-Free swift-dependencies** — protocol-or-struct interface + live/preview/test conformances.
- **everliv-monorepo** — single foundation-only `SharedModels` with all coordinator protocols; features import + implement.

## Status legend

- ✅ matches contract
- ⚠ has more imports than contract permits (each excess listed)
- 🔄 in flight — being fixed in current PR

## Layers

### Foundation tier (own imports only; foundation-only by construction)

| Target | Allowed imports | Current state |
|---|---|---|
| `LoggingModels` | Foundation | ✅ Foundation |
| `SharedConstants` | Foundation, CryptoKit | ✅ Foundation, CryptoKit (post-#536 1a-1d: absorbed `SharedCore` / `SharedUtils` / `SharedModels` / `SharedConfiguration`) |
| `Resources` | Foundation | ✅ Foundation |
| `MCPCore` | Foundation | ✅ Foundation |
| `MCPSharedTools` | Foundation, MCPCore, SharedConstants | ✅ Foundation, MCPCore, SharedConstants |

### Models tier (protocol seams + value types; foundation-only)

| Target | Allowed imports | Current state |
|---|---|---|
| `CoreProtocols` | Foundation, SharedConstants, Resources | ✅ Foundation, Resources, SharedConstants (post-#536 2a: GitHubCanonicalizer + ExclusionList moved out to CorePackageIndexing) |
| `CrawlerModels` | Foundation, SharedConstants | ✅ Foundation, SharedConstants |
| `CorePackageIndexingModels` | Foundation, ASTIndexer, CoreProtocols, SharedConstants | ✅ Foundation, ASTIndexer, CoreProtocols, SharedConstants |
| `SearchModels` | Foundation, SharedConstants | ✅ Foundation, SharedConstants |
| `SampleIndexModels` | Foundation, SharedConstants | ✅ Foundation, SharedConstants |
| `ServicesModels` | Foundation, SearchModels, SampleIndexModels, SharedConstants | ✅ Foundation, SampleIndexModels, SearchModels, SharedConstants |
| `IndexerModels` | Foundation | ✅ Foundation (closures-to-Observer epic seam: owns `Indexer.*Service.Request`/`Outcome`/`Event` value types + the three `*Service.EventObserving` Observer protocols) |
| `DistributionModels` | Foundation, SharedConstants | ✅ Foundation, SharedConstants (closures-to-Observer epic seam: owns `Distribution.SetupService.Request`/`Outcome`/`Event` + `ArtifactDownloader.Progress` + `InstalledVersion.Status` + `SetupError` value types + `SetupService.EventObserving` / `ArtifactDownloader.ProgressObserving` / `ArtifactExtractor.TickObserving` protocols) |
| `CleanupModels` | Foundation, SharedConstants | ✅ Foundation, SharedConstants (closures-to-Observer epic seam: owns the `Sample.Cleanup.CleanerProgressObserving` Observer protocol; payload `Shared.Models.CleanupProgress` already lives in `SharedConstants`) |
| `CoreSampleCodeModels` | Foundation, SharedConstants | ✅ Foundation, SharedConstants (closures-to-Observer epic seam: owns `Sample.Core.GitHubFetcherProgress` value type + `Sample.Core.GitHubFetcherProgressObserving` Observer protocol; flat-named because the producer `Sample.Core.GitHubFetcher` is a `public final class`, extends the `Sample.Core` namespace owned by `SharedConstants`) |
| `RemoteSyncModels` | Foundation, SharedConstants | ✅ Foundation, SharedConstants (closures-to-Observer epic seam: owns the `RemoteSync` namespace anchor + `Progress` / `IndexState` / `IndexerResult` / `IndexerError` value types + `DocumentIndexing` Strategy protocol + `IndexerProgressObserving` / `IndexerDocumentObserving` Observer protocols; flat-named because the producer `RemoteSync.Indexer` is a `public actor`) |
| `EnrichmentModels` | Foundation | ✅ Foundation (#837 postprocessor seam: owns `EnrichmentPass` protocol + `EnrichmentModels.Target` enum + `EnrichmentModels.Result` value type. Consumed by the postprocessor binary planned under #769 + by the `Enrichment` producer for live conformances) |
| `SearchSchema` | Foundation, SearchModels | ✅ Foundation, SearchModels (#898 sub-PR A: foundation-only target carrying the search.db DDL SQL constant `Search.Schema.createAllTablesSQL` + the `Search.Schema.currentVersion: Int32` constant. Executor methods on `Search.Index` consume these constants via `import SearchSchema`; the executors themselves stay in the Search target until #898 sub-PR E moves them into `SearchSQLite`.) |

### Infrastructure tier (wraps a system API; foundation-tier deps)

| Target | Allowed imports | Current state |
|---|---|---|
| `ASTIndexer` | Foundation, SwiftSyntax, SwiftParser | ✅ Foundation, SwiftParser, SwiftSyntax |
| `Diagnostics` | Foundation, SQLite3 | ✅ Foundation, SQLite3 |
| `Logging` (writer concrete) | Foundation, OSLog, LoggingModels, SharedConstants | ✅ Foundation, LoggingModels, OSLog, SharedConstants — binary-only (CLI / TUI / MockAIAgent / ReleaseTool only; features import only `LoggingModels`) |

### Producers (behaviour; consume protocols from Models, no other producers)

| Target | Allowed imports | Current state |
|---|---|---|
| `AppleConstraintsKit` | Foundation, SearchModels | ✅ Foundation, SearchModels (#759 iter 3 — parses `swift symbolgraph-extract` output via local Codable schema, maps `pathComponents → apple-docs://...` URIs, ships the filtered table as `Search.StaticConstraintsLookup` conformance) |
| `Availability` | Foundation, FoundationNetworking, SharedConstants | ✅ Foundation, FoundationNetworking, SharedConstants |
| `Cleanup` | Foundation, CleanupModels, LoggingModels, SharedConstants | ✅ Foundation, CleanupModels, LoggingModels, SharedConstants (closures-to-Observer epic: `cleanup` signature now takes `any Sample.Cleanup.CleanerProgressObserving` from seam) |
| `Core` | Foundation, WebKit, LoggingModels, Resources, ASTIndexer, CoreProtocols, CorePackageIndexingModels, SharedConstants | ✅ ASTIndexer, CorePackageIndexingModels, CoreProtocols, Foundation, LoggingModels, Resources, SharedConstants, WebKit |
| `CoreJSONParser` | Foundation, CoreProtocols, SharedConstants | ✅ |
| `CorePackageIndexing` | Foundation, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, Resources, SharedConstants | ✅ (post-#536 2a: now owns the moved GitHubCanonicalizer + ExclusionList) |
| `CoreSampleCode` | Foundation, AppKit, WebKit, CoreSampleCodeModels, LoggingModels, SharedConstants | ✅ AppKit, CoreSampleCodeModels, Foundation, LoggingModels, SharedConstants, WebKit (closures-to-Observer epic: `Sample.Core.GitHubFetcher.fetch` signature now takes `any Sample.Core.GitHubFetcherProgressObserving` from seam) |
| `Crawler` | Foundation, os, WebKit, CoreProtocols, CrawlerModels, LoggingModels, Resources, SharedConstants | ✅ CoreProtocols, CrawlerModels, Foundation, LoggingModels, Resources, SharedConstants, WebKit, os |
| `Distribution` | Foundation, DistributionModels, SharedConstants | ✅ Foundation, DistributionModels, SharedConstants (closures-to-Observer epic: `@_exported import DistributionModels` so existing callers reading `Distribution.SetupService.Request` via `import Distribution` still resolve) |
| `Enrichment` | Foundation, EnrichmentModels, LoggingModels, SearchModels, SampleIndexModels, SharedConstants | ⚠️ Foundation, EnrichmentModels, SampleIndex, SampleIndexModels, Search, SearchModels, SharedConstants. Allowed-imports column above is the TARGET shape per `gof-di-rules.md` rules 5 + 8. Current state diverges: 6 sibling passes import `Search` + `SampleIndex` concretes directly (write-side coupling) and the orchestrator does not yet emit log lines (LoggingModels listed in TARGET because #837 specifies `[enrichment/<pass>] affected=N skipped=M (Tms)` output for the per-pass split). Not yet added to `STRICT_PRODUCERS`; #906 (child of epic #893) splits each pass into its own SPM target consuming `EnrichmentModels.EnrichmentPass` against protocol-fronted Search / SampleIndex writers |
| `Indexer` | Foundation, IndexerModels, SampleIndexModels, SearchModels, SharedConstants | ✅ Foundation, IndexerModels, SampleIndexModels, SearchModels, SharedConstants (closures-to-Observer epic: `@_exported import IndexerModels` so consumers reading `Indexer.*Service.Request`/`Outcome`/`Event` via `import Indexer` still resolve) |
| `Ingest` | Foundation, LoggingModels, SharedConstants | ✅ Foundation, LoggingModels, SharedConstants |
| `MCPSupport` | Foundation, LoggingModels, MCPCore, MCPSharedTools, SharedConstants | ✅ Foundation, LoggingModels, MCPCore, MCPSharedTools, SharedConstants |
| `RemoteSync` | Foundation, RemoteSyncModels, SharedConstants | ✅ Foundation, RemoteSyncModels, SharedConstants (closures-to-Observer epic: `@_exported import RemoteSyncModels` so existing callers reading `RemoteSync.Indexer`/`Progress`/`IndexState` via `import RemoteSync` still resolve; `Indexer.run` signature now takes `any DocumentIndexing` Strategy + `any IndexerProgressObserving` Observer + optional `any IndexerDocumentObserving` Observer) |
| `SampleIndex` | Foundation, OSLog, SQLite3, ASTIndexer, LoggingModels, SampleIndexModels, SharedConstants | ✅ ASTIndexer, Foundation, LoggingModels, OSLog, SQLite3, SampleIndexModels, SharedConstants |
| `Search` | Foundation, SQLite3, ASTIndexer, CorePackageIndexingModels, CoreProtocols, EnrichmentModels, LoggingModels, SearchModels, SearchSchema, SharedConstants | ✅ ASTIndexer, CorePackageIndexingModels, CoreProtocols, EnrichmentModels, Foundation, LoggingModels, SQLite3, SearchModels, SearchSchema, SharedConstants (#837: `Search.IndexBuilder` consumes the `EnrichmentModels.EnrichmentPass` seam; #898 sub-PR A: `Search.Index.createTables` consumes the `Search.Schema.createAllTablesSQL` constant lifted to `SearchSchema`.) |
| `SearchToolProvider` | Foundation, MCPCore, MCPSharedTools, SampleIndexModels, SearchModels, ServicesModels, SharedConstants | ✅ Foundation, MCPCore, MCPSharedTools, SampleIndexModels, SearchModels, ServicesModels, SharedConstants |
| `Services` | Foundation, SampleIndexModels, SearchModels, ServicesModels, SharedConstants | ✅ Foundation, SampleIndexModels, SearchModels, ServicesModels, SharedConstants |

**31 producers are opted into `scripts/check-target-foundation-only.sh`'s `STRICT_PRODUCERS`** array and audit clean against the foundation-only allow-list. Breakdown: 13 foundation-only seam targets in the Models tier (the 11 `*Models`-suffixed targets + `CoreProtocols`, grouped with the seams despite the unsuffixed name, + `SearchSchema`, the search.db DDL + version-constant target added by #898 sub-PR A) + 18 feature producers (every row in the Producers table above except `Enrichment`, plus `Logging`, which is documented in the Infrastructure tier above but audited as a feature producer because its import surface is producer-shaped). `Enrichment` is documented in the Producers table but is NOT in `STRICT_PRODUCERS`: its 6 sibling passes still import `Search` + `SampleIndex` concretes directly, breaking `gof-di-rules.md` rule 5. Opt-in happens after #906 (child of epic #893) lifts each pass into its own SPM target consuming `EnrichmentModels.EnrichmentPass`. The opt-in cadence is #536 phase 3's pattern: per-producer PR, with `scripts/check-target-portability.sh <Target>` green, then add the target to `STRICT_PRODUCERS` in the same change. (`AppleConstraintsKit` was the most recent producer added under this cadence by PR #908; its portability test is queued, not yet run.)

### Apps (composition roots; can import anything)

Build-system convention: every entry in this section is declared `.executableTarget(...)` in `Package.swift` (not a library). They are inherently impls — they wire feature targets together to produce a binary, so the "every target must lift out of the monorepo cleanly" rule does not apply. The Swift namespace anchors inside (`enum CLIImpl`, files named `CLIImpl.*.swift`, the renamed `ReleaseToolImpl.swift`) carry the `*Impl` suffix so the impl/library distinction is visible at a glance without checking `Package.swift`.

| Target | Allowed imports | Current state |
|---|---|---|
| `CLI` (`enum CLIImpl`) | everything | ✅ composition root, `executableTarget` → `cupertino` |
| `TUI` | everything | ✅ `executableTarget` → `cupertino-tui` |
| `MockAIAgent` | everything | ✅ `executableTarget` → `mock-ai-agent` |
| `ReleaseTool` (`ReleaseToolImpl.swift`) | everything | ✅ `executableTarget` → `cupertino-rel`, binary, not a producer |
| `ConstraintsGen` (`ConstraintsGen.swift`) | Foundation, ArgumentParser, AppleConstraintsKit, SearchModels | ✅ `executableTarget` → `cupertino-constraints-gen`, binary, parses `swift symbolgraph-extract` output into the `apple-constraints.json` table consumed by `Search.IndexBuilder` (#759 iter 3) |

## CI enforcement

Two guard scripts back the contract:

- `scripts/check-package-purity.sh` — bans any producer importing a concrete writer of another producer. Green throughout the epic.
- `scripts/check-target-foundation-only.sh` — per-target allow-list. `STRICT_PRODUCERS` empty during phase 0-2; each phase 3 PR opts a producer in.

Both scripts run as part of every PR's verification.

## What this contract bans

If you grep `^import ` under `Sources/<Target>/` and see anything not in the **Allowed imports** column for that target — it's a violation. Examples:

- `Sources/Search/**` importing `Core` (concrete feature → feature). Fix: lift the type to a `*Models` target or define a protocol seam.
- `Sources/Crawler/**` importing `Logging` (concrete writer; only `LoggingModels` is allowed).
- Any producer target importing `SharedCore` / `SharedUtils` / `SharedModels` / `SharedConfiguration` — those don't exist anymore (absorbed in #536 phase 1). Use `SharedConstants`.
- Any producer target reading `Shared.Constants.BinaryConfig.shared` or `Shared.Constants.defaultBaseDirectory` — those are deleted (#535). Receive `Shared.Paths` or an explicit `URL` by parameter.
