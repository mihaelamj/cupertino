# Per-package import contract

Single source of truth for what each target is **allowed** to import. Anything else in `^import` lines under that target's `Sources/` is a **violation** of the strict-DI / standalone-portability rules.

Last refresh: 2026-05-15, after #536 phases 0 / 1a-1d / 2a. The four legacy `Shared*` sub-targets (`SharedCore`, `SharedUtils`, `SharedModels`, `SharedConfiguration`) have been absorbed into `SharedConstants`; `Core.PackageIndexing.GitHubCanonicalizer` + `Core.PackageIndexing.ExclusionList` moved out of `CoreProtocols`. Every producer's actual imports now match the foundation-only target regime — phase 3 will lock that in via `scripts/check-target-foundation-only.sh` opt-in.

## The target regime (post-#536)

**Goal:** every producer target plus its `*Models` companion is a standalone-portable unit. Pull out `(Search + SearchModels)` into a fresh repo with the foundation tier and it builds against external SwiftPM deps alone.

**Allowed imports for a producer target:**

1. **External primitives** — `Foundation`, `OSLog`, `os`, `Combine`, `SQLite3`, `SwiftSyntax`, `SwiftParser`, `ArgumentParser`, `Testing`, `XCTest`, `WebKit`, `AppKit`, `UIKit`, `SwiftUI`, `CryptoKit`, `FoundationNetworking`, system frameworks (`Darwin`, `Glibc`). Ambient — always allowed.
2. **Foundation tier (Cupertino-side, foundation-only by construction)** — `SharedConstants`, `LoggingModels`, `Resources`, `Diagnostics`, `ASTIndexer`, `MCPCore`, `MCPSharedTools`. Any producer may import any of these.
3. **`*Models` protocol seams** — `CoreProtocols`, `CrawlerModels`, `CorePackageIndexingModels`, `SearchModels`, `SampleIndexModels`, `ServicesModels`. Any producer may import its own + any other producer's seam (the seams are foundation-only by contract; importing a seam carries no behavioural coupling).

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

### Infrastructure tier (wraps a system API; foundation-tier deps)

| Target | Allowed imports | Current state |
|---|---|---|
| `ASTIndexer` | Foundation, SwiftSyntax, SwiftParser | ✅ Foundation, SwiftParser, SwiftSyntax |
| `Diagnostics` | Foundation, SQLite3 | ✅ Foundation, SQLite3 |
| `Logging` (writer concrete) | Foundation, OSLog, LoggingModels, SharedConstants | ✅ Foundation, LoggingModels, OSLog, SharedConstants — binary-only (CLI / TUI / MockAIAgent / ReleaseTool only; features import only `LoggingModels`) |

### Producers (behaviour; consume protocols from Models, no other producers)

| Target | Allowed imports | Current state |
|---|---|---|
| `Availability` | Foundation, FoundationNetworking, SharedConstants | ✅ Foundation, FoundationNetworking, SharedConstants |
| `Cleanup` | Foundation, LoggingModels, SharedConstants | ✅ Foundation, LoggingModels, SharedConstants |
| `Core` | Foundation, WebKit, LoggingModels, Resources, ASTIndexer, CoreProtocols, CorePackageIndexingModels, SharedConstants | ✅ ASTIndexer, CorePackageIndexingModels, CoreProtocols, Foundation, LoggingModels, Resources, SharedConstants, WebKit |
| `CoreJSONParser` | Foundation, CoreProtocols, SharedConstants | ✅ |
| `CorePackageIndexing` | Foundation, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, Resources, SharedConstants | ✅ (post-#536 2a: now owns the moved GitHubCanonicalizer + ExclusionList) |
| `CoreSampleCode` | Foundation, AppKit, WebKit, LoggingModels, SharedConstants | ✅ AppKit, Foundation, LoggingModels, SharedConstants, WebKit |
| `Crawler` | Foundation, os, WebKit, CoreProtocols, CrawlerModels, LoggingModels, Resources, SharedConstants | ✅ CoreProtocols, CrawlerModels, Foundation, LoggingModels, Resources, SharedConstants, WebKit, os |
| `Distribution` | Foundation, SharedConstants | ✅ Foundation, SharedConstants |
| `Indexer` | Foundation, IndexerModels, SampleIndexModels, SearchModels, SharedConstants | ✅ Foundation, IndexerModels, SampleIndexModels, SearchModels, SharedConstants (closures-to-Observer epic: `@_exported import IndexerModels` so consumers reading `Indexer.*Service.Request`/`Outcome`/`Event` via `import Indexer` still resolve) |
| `Ingest` | Foundation, LoggingModels, SharedConstants | ✅ Foundation, LoggingModels, SharedConstants |
| `MCPSupport` | Foundation, LoggingModels, MCPCore, MCPSharedTools, SharedConstants | ✅ Foundation, LoggingModels, MCPCore, MCPSharedTools, SharedConstants |
| `RemoteSync` | Foundation, SharedConstants | ✅ Foundation, SharedConstants |
| `SampleIndex` | Foundation, OSLog, SQLite3, ASTIndexer, LoggingModels, SampleIndexModels, SharedConstants | ✅ ASTIndexer, Foundation, LoggingModels, OSLog, SQLite3, SampleIndexModels, SharedConstants |
| `Search` | Foundation, SQLite3, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, SearchModels, SharedConstants | ✅ ASTIndexer, CorePackageIndexingModels, CoreProtocols, Foundation, LoggingModels, SQLite3, SearchModels, SharedConstants |
| `SearchToolProvider` | Foundation, MCPCore, MCPSharedTools, SampleIndexModels, SearchModels, ServicesModels, SharedConstants | ✅ Foundation, MCPCore, MCPSharedTools, SampleIndexModels, SearchModels, ServicesModels, SharedConstants |
| `Services` | Foundation, SampleIndexModels, SearchModels, ServicesModels, SharedConstants | ✅ Foundation, SampleIndexModels, SearchModels, ServicesModels, SharedConstants |

**Every producer matches the target regime.** Phase 3 of #536 will opt them into `scripts/check-target-foundation-only.sh`'s `STRICT_PRODUCERS` array one-by-one.

### Apps (composition roots; can import anything)

Build-system convention: every entry in this section is declared `.executableTarget(...)` in `Package.swift` (not a library). They are inherently impls — they wire feature targets together to produce a binary, so the "every target must lift out of the monorepo cleanly" rule does not apply. The Swift namespace anchors inside (`enum CLIImpl`, files named `CLIImpl.*.swift`, the renamed `ReleaseToolImpl.swift`) carry the `*Impl` suffix so the impl/library distinction is visible at a glance without checking `Package.swift`.

| Target | Allowed imports | Current state |
|---|---|---|
| `CLI` (`enum CLIImpl`) | everything | ✅ composition root, `executableTarget` → `cupertino` |
| `TUI` | everything | ✅ `executableTarget` → `cupertino-tui` |
| `MCP` (lib) | everything in its layer | ✅ |
| `MockAIAgent` | everything | ✅ `executableTarget` → `mock-ai-agent` |
| `ReleaseTool` (`ReleaseToolImpl.swift`) | everything | ✅ `executableTarget` → `cupertino-rel`, binary, not a producer |

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
