# Per-package import contract

Single source of truth for what each target is **allowed** to import. Anything else in `^import` lines under that target's `Sources/` is a **violation** of the strict-DI / standalone-portability rules.

Last refresh: 2026-05-23 (#903 closed: Crawler WebKit extraction lifts WebKit-backed concretes to the new `CrawlerWebKit` sibling target; Crawler producer is foundation-only; HIG + AppleDocs take `any Crawler.HTTPFetcherFactory` via init injection). Closing summary count refreshed to **47 producers strict**. Earlier refresh: 2026-05-23 (#906 sub-PRs B-G closed: per-pass split landed 6 new foundation-tier sibling targets `AppleConstraintsPass`, `HierarchyPass`, `PackagesAppleConstraintsPass`, `PackagesAppleImportsPass`, `SamplesAppleConstraintsPass`, `SynonymsPass`). The `Enrichment` package retains only the `LiveRunner` orchestrator. Previous refresh (2026-05-22, #906 Enrichment protocol-rewire) flipped the `Enrichment` row from `⚠️` to `✅` after the 6 sibling passes were rewired to take `any Search.IndexWriter` / `any Search.PackageWriter` / `any Sample.Index.Writer` via init injection; `SearchModels` gained a new `Search.PackageWriter` protocol; `SampleIndexModels` gained a `SearchModels` dep so `Sample.Index.Writer` can name `Search.StaticConstraintsLookup`. Earlier refresh: 2026-05-22 (#895 hygiene PR), which added the `EnrichmentModels` seam to the `*Models` allow-list and to the audit-script arrays, added the `AppleConstraintsKit` producer to `STRICT_PRODUCERS`, updated the `Search` row to list `EnrichmentModels`, and added an `EnrichmentModels` Models-tier row. Earlier refresh: 2026-05-15, after #536 phases 0 / 1a-1d / 2a, when the four legacy `Shared*` sub-targets (`SharedCore`, `SharedUtils`, `SharedModels`, `SharedConfiguration`) were absorbed into `SharedConstants` and `Core.PackageIndexing.GitHubCanonicalizer` + `Core.PackageIndexing.ExclusionList` moved out of `CoreProtocols`.

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
| `AvailabilityModels` | Foundation | ✅ Foundation (#905: namespace anchor + value types + Networking / NetworkingFactory protocols) |
| `Availability` | Foundation, AvailabilityModels, SharedConstants | ✅ Foundation, AvailabilityModels, SharedConstants (#905: FoundationNetworking removed: URLSession moved to AvailabilityFoundationNetworking) |
| `AvailabilityFoundationNetworking` | Foundation, FoundationNetworking, AvailabilityModels | ✅ Foundation, FoundationNetworking, AvailabilityModels (#905: `LiveAvailabilityNetworking` + factory: isolates URLSession use to this target so Availability stays foundation-only) |
| `Cleanup` | Foundation, CleanupModels, LoggingModels, SharedConstants | ✅ Foundation, CleanupModels, LoggingModels, SharedConstants (closures-to-Observer epic: `cleanup` signature now takes `any Sample.Cleanup.CleanerProgressObserving` from seam) |
| `Core` | Foundation, WebKit, LoggingModels, Resources, ASTIndexer, CoreProtocols, CorePackageIndexingModels, SharedConstants | ✅ ASTIndexer, CorePackageIndexingModels, CoreProtocols, Foundation, LoggingModels, Resources, SharedConstants, WebKit |
| `CoreJSONParser` | Foundation, CoreProtocols, SharedConstants | ✅ |
| `CorePackageIndexing` | Foundation, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, Resources, SharedConstants | ✅ (post-#536 2a: now owns the moved GitHubCanonicalizer + ExclusionList) |
| `CoreSampleCode` | Foundation, AppKit, WebKit, CoreSampleCodeModels, LoggingModels, SharedConstants | ✅ AppKit, CoreSampleCodeModels, Foundation, LoggingModels, SharedConstants, WebKit (closures-to-Observer epic: `Sample.Core.GitHubFetcher.fetch` signature now takes `any Sample.Core.GitHubFetcherProgressObserving` from seam) |
| `Crawler` | Foundation, os, CoreProtocols, CrawlerModels, LoggingModels, Resources, SharedConstants | ✅ CoreProtocols, CrawlerModels, Foundation, LoggingModels, Resources, SharedConstants, os (#903: WebKit dropped: `Crawler.WebKit.*` concretes + `LiveHTTPFetcherFactory` lifted to the `CrawlerWebKit` sibling target; HIG / AppleDocs take `any Crawler.HTTPFetcherFactory` via init injection.) |
| `CrawlerWebKit` | Foundation, WebKit, CoreProtocols, CrawlerModels, SharedConstants | ✅ Foundation, WebKit, CoreProtocols, CrawlerModels, SharedConstants (#903: WebKit-backed concretes lifted out of the Crawler producer. Provides `Crawler.WebKit.ContentFetcher`, `Crawler.WebKit.Engine`, and `Crawler.WebKit.LiveHTTPFetcherFactory` (the production conformer for `Crawler.HTTPFetcherFactory`). CLI composition root constructs the factory and threads it into `Crawler.AppleDocs` / `Crawler.HIG`.) |
| `Distribution` | Foundation, DistributionModels, SharedConstants | ✅ Foundation, DistributionModels, SharedConstants (closures-to-Observer epic: `@_exported import DistributionModels` so existing callers reading `Distribution.SetupService.Request` via `import Distribution` still resolve) |
| `Enrichment` | Foundation, EnrichmentModels, SearchModels, SampleIndexModels, SharedConstants | ✅ Foundation, EnrichmentModels, SampleIndexModels, SearchModels, SharedConstants (#906: 6 sibling passes rewired from concrete `Search.Index` / `Search.PackageIndex` / `Sample.Index.Database` parameters to `any Search.IndexWriter` / `any Search.PackageWriter` / `any Sample.Index.Writer` via init injection. New `Search.PackageWriter` protocol added to `SearchModels`; `applyAppleStaticConstraints` added to `Sample.Index.Writer`. The target now imports only Models + foundation tier and audits clean against the strict rule.) |
| `Indexer` | Foundation, IndexerModels, SampleIndexModels, SearchModels, SharedConstants | ✅ Foundation, IndexerModels, SampleIndexModels, SearchModels, SharedConstants (closures-to-Observer epic: `@_exported import IndexerModels` so consumers reading `Indexer.*Service.Request`/`Outcome`/`Event` via `import Indexer` still resolve) |
| `Ingest` | Foundation, LoggingModels, SharedConstants | ✅ Foundation, LoggingModels, SharedConstants |
| `MCPSupport` | Foundation, LoggingModels, MCPCore, MCPSharedTools, SharedConstants | ✅ Foundation, LoggingModels, MCPCore, MCPSharedTools, SharedConstants |
| `RemoteSync` | Foundation, RemoteSyncModels, SharedConstants | ✅ Foundation, RemoteSyncModels, SharedConstants (closures-to-Observer epic: `@_exported import RemoteSyncModels` so existing callers reading `RemoteSync.Indexer`/`Progress`/`IndexState` via `import RemoteSync` still resolve; `Indexer.run` signature now takes `any DocumentIndexing` Strategy + `any IndexerProgressObserving` Observer + optional `any IndexerDocumentObserving` Observer) |
| `SampleIndex` | Foundation, OSLog, SQLite3, ASTIndexer, LoggingModels, SampleIndexModels, SharedConstants | ✅ ASTIndexer, Foundation, LoggingModels, OSLog, SQLite3, SampleIndexModels, SharedConstants |
| `Search` | Foundation, ASTIndexer, CoreProtocols, EnrichmentModels, LoggingModels, SearchModels, SharedConstants | ✅ ASTIndexer, CoreProtocols, EnrichmentModels, Foundation, LoggingModels, SearchModels, SharedConstants (#898 sub-PR E: SQLite3 dropped. `Search.Index` plus 19 extensions, `PackageIndex`, `Search.PackageQuery`, `PackageIndexer`, and the two `CandidateFetcher` concretes lifted into `SearchSQLite`. Search now operates strictly through the `SearchModels` protocol seams: `Search.IndexBuilder` + the 6 strategies + `Search.SmartQuery` consume `any Search.Database & Search.IndexWriter` / `any Search.CandidateFetcher`. `SearchSchema` and `CorePackageIndexingModels` deps dropped because the executors that consumed them moved to SearchSQLite.) |
| `SearchSQLite` | Foundation, SQLite3, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, SearchModels, SearchSchema, SharedConstants | ✅ ASTIndexer, CorePackageIndexingModels, CoreProtocols, Foundation, LoggingModels, SQLite3, SearchModels, SearchSchema, SharedConstants (#898 sub-PR E shipped the extraction; #898F dropped the `import Search` by lifting `Search.Source`, `Search.QueryIntent`, `detectQueryIntent`, `Search.SourceProperties` out of `Search.ComposableResult.swift` into `SearchModels`, moving `Search.SourceDefinition.swift` whole to `SearchModels`, and moving `Search.SearchResult.swift`, `DocKind.swift`, `Search.SourceIndexer.swift`, `Search.Index.DocLinkRewriter.swift` whole to `SearchSQLite`. `Sample.Indexer` was renamed to `Search.SampleCodeIndexer` to remove the `Sample.Search` namespace ambiguity exposed by the move. SearchSQLite now audits cleanly against the strict rule and is the only target outside Diagnostics + SampleIndexSQLite + ReleaseTool that imports SQLite3.) |
| `SearchStrategyHelpers` | Foundation, SearchModels, SharedConstants | ✅ Foundation, SearchModels, SharedConstants (#899: foundation-only shared utility target carrying `Search.StrategyHelpers` enum. Extracted from SearchStrategies so per-strategy SPM targets can consume the helpers without depending on the SearchStrategies concrete.) |
| `AppleDocsStrategy` | Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants | ✅ Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants (#899 sub-PR B: first per-strategy extraction; extracts Search.AppleDocsStrategy out of the deleted SearchStrategies umbrella into its own SPM sibling target conforming `Search.SourceIndexingStrategy`. Pattern-setter for remaining 5 strategy splits; HIG / SwiftEvolution / SwiftOrg / AppleArchive / SampleCode follow.) |
| `HIGStrategy` | Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants | ✅ Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants (#899 sub-PR C: extracts Search.HIGStrategy.) |
| `SampleCodeStrategy` | Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants | ✅ Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants (#899 sub-PR D: extracts Search.SampleCodeStrategy.) |
| `SwiftEvolutionStrategy` | Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants | ✅ Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants (#899 sub-PR E: extracts Search.SwiftEvolutionStrategy.) |
| `SwiftOrgStrategy` | Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants | ✅ Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants (#899 sub-PR F: extracts Search.SwiftOrgStrategy.) |
| `AppleArchiveStrategy` | Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants | ✅ Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants (#899 sub-PR G: extracts Search.AppleArchiveStrategy; closes the 6-of-6 strategy split, the SearchStrategies umbrella target was deleted.) |
| `AppleConstraintsPass` | Foundation, EnrichmentModels, SearchModels, SharedConstants | ✅ Foundation, EnrichmentModels, SearchModels, SharedConstants (#906 sub-PR B: extracts Enrichment.AppleConstraintsPass into its own SPM sibling target conforming `EnrichmentModels.EnrichmentPass`; pattern-setter for the per-pass split.) |
| `HierarchyPass` | Foundation, EnrichmentModels, SearchModels | ✅ Foundation, EnrichmentModels, SearchModels (#906 sub-PR C: extracts Enrichment.HierarchyPass; second per-pass split following the AppleConstraintsPass pattern.) |
| `PackagesAppleConstraintsPass` | Foundation, EnrichmentModels, SearchModels | ✅ Foundation, EnrichmentModels, SearchModels (#906 sub-PR D: extracts Enrichment.PackagesAppleConstraintsPass; #837 stage 2 — applies the authoritative Apple-type generic constraints table to packages.db's `package_symbols.generic_constraints`.) |
| `PackagesAppleImportsPass` | Foundation, EnrichmentModels, SearchModels | ✅ Foundation, EnrichmentModels, SearchModels (#906 sub-PR E: extracts Enrichment.PackagesAppleImportsPass; #837 stage 1 — populates packages.db's `package_metadata.apple_imports_json`.) |
| `SamplesAppleConstraintsPass` | Foundation, EnrichmentModels, SampleIndexModels, SearchModels, SharedConstants | ✅ Foundation, EnrichmentModels, SampleIndexModels, SearchModels, SharedConstants (#906 sub-PR F: extracts Enrichment.SamplesAppleConstraintsPass; #837 stage 1 — applies Apple-type generic constraints table to samples.db's `file_symbols.generic_constraints`.) |
| `SynonymsPass` | Foundation, EnrichmentModels, SearchModels | ✅ Foundation, EnrichmentModels, SearchModels (#906 sub-PR G: extracts Enrichment.SynonymsPass; final per-pass split, registers the 22-entry framework-alias table on search.db.) |
| `SampleIndexSQLite` | Foundation, SQLite3, ASTIndexer, CoreProtocols, LoggingModels, SampleIndexModels, SharedConstants | ✅ Foundation, SQLite3, ASTIndexer, CoreProtocols, LoggingModels, SampleIndexModels, SharedConstants (#902: extracts the SQLite-backed `Sample.Index.Database` concrete out of SampleIndex; SampleIndex now operates strictly through the `Sample.Index.Reader` / `Sample.Index.Writer` protocol seams.) |
| `MCPClient` | Foundation, MCPCore, MCPSharedTools, SharedConstants | ✅ Foundation, MCPCore, MCPSharedTools, SharedConstants (cross-platform MCP client over JSON-RPC stdio; consumed by the cupertino MCP host integrations + tests.) |
| `SearchToolProvider` | Foundation, MCPCore, MCPSharedTools, SampleIndexModels, SearchModels, ServicesModels, SharedConstants | ✅ Foundation, MCPCore, MCPSharedTools, SampleIndexModels, SearchModels, ServicesModels, SharedConstants |
| `Services` | Foundation, SampleIndexModels, SearchModels, ServicesModels, SharedConstants | ✅ Foundation, SampleIndexModels, SearchModels, ServicesModels, SharedConstants |

**47 producers are opted into `scripts/check-target-foundation-only.sh`'s `STRICT_PRODUCERS`** array and audit clean against the foundation-only allow-list. Breakdown: 13 foundation-only seam targets in the Models tier (the 11 `*Models`-suffixed targets + `CoreProtocols`, grouped with the seams despite the unsuffixed name, + `SearchSchema`, the search.db DDL + version-constant target added by #898 sub-PR A) + 34 feature producers (every row in the Producers table above, plus `Logging`, which is documented in the Infrastructure tier above but audited as a feature producer because its import surface is producer-shaped, plus the 6 strategy siblings from #899, the 6 enrichment-pass siblings from #906, and `CrawlerWebKit` from #903). Every producer documented in this table is now in `STRICT_PRODUCERS`; `check-package-purity.sh`'s `GRANDFATHERED_TARGETS` array is empty. The opt-in cadence is #536 phase 3's pattern: per-producer PR, with `scripts/check-target-portability.sh <Target>` green, then add the target to `STRICT_PRODUCERS` in the same change. (Recent additions: 6 strategy siblings via #899 sub-PRs B-G; 6 enrichment-pass siblings via #906 sub-PRs B-G; `CrawlerWebKit` via #903.)

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
