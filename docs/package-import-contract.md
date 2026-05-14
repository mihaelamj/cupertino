# Per-package import contract

Single source of truth for what each target is **allowed** to import. Anything else in `^import` lines under that target's `Sources/` is a **violation** of the strict-DI / standalone-portability rules.

## Target regime (post-#536) — foundation-only producers

**Goal:** every producer target plus its `*Models` companion is a standalone-portable unit. Pull out `(Search + SearchModels)` into a fresh repo with the foundation tier and it builds against external SwiftPM deps alone.

**Allowed imports for a producer target:**

1. **External primitives** — `Foundation`, `OSLog`, `os`, `SQLite3`, `SwiftSyntax`, `SwiftParser`, `ArgumentParser`, `Testing`, `XCTest`, `WebKit`, `AppKit`, `UIKit`, `SwiftUI`, `CryptoKit`, `FoundationNetworking`, system frameworks. Ambient — always allowed.
2. **Foundation tier (Cupertino-side, foundation-only by construction)** — `SharedConstants`, `LoggingModels`, `Resources`, `Diagnostics`, `ASTIndexer`, `MCPCore`, `MCPSharedTools`. Any producer may import any of these.
3. **`*Models` protocol seams** — `CoreProtocols`, `CrawlerModels`, `CorePackageIndexingModels`, `SearchModels`, `SampleIndexModels`, `ServicesModels`. Any producer may import its own + any other producer's seam (the seams are foundation-only by contract; importing a seam carries no behavioural coupling).

**Forbidden for a producer:**

- Another producer's concrete writer target (e.g. `Search` cannot `import Indexer`).
- `Logging` (the writer concrete). Only `LoggingModels` allowed.
- `SharedCore`, `SharedUtils`, `SharedModels`, `SharedConfiguration` — these dissolve into `SharedConstants` during the epic.
- `Shared.Constants.BinaryConfig.shared` and the deleted `Shared.Constants.defaultX` static accessors (already gone post-#535).

## Why this shape

Validated against four independent references:

- **GoF (1994) Strategy p. 315 / Factory Method p. 107** — protocol/Strategy lives in a single interface; concretes live in conformer targets. SPM equivalent: protocol-host target is foundation-only.
- **Apple SwiftNIO** — `NIOCore` (foundation-only protocols) + `NIOPosix` (concrete impl). Same shape as cupertino's `LoggingModels` + `Logging` writer, applied per-producer.
- **Apple swift-log (SSWG)** — single foundation-only `Logging` target with `LogHandler` protocol + pure-Swift defaults; OS-coupled handlers in separate packages.
- **Point-Free swift-dependencies** — protocol-or-struct interface + live/preview/test conformances. Orthogonal to where the interface lives; compatible with our choice.
- **everliv-monorepo (`Packages/Sources/SharedModels/Coordinators`)** — single foundation-only `SharedModels` carrying all protocols; each feature target imports it and provides its own conformance.

cupertino's shape (6 per-producer `*Models` companions instead of 1 combined) is MORE decoupled than everliv's, more aligned with SwiftNIO's per-layer separation, and never deviates from GoF.

## CI enforcement

Two guard scripts back the contract:

- `scripts/check-package-purity.sh` — interim guard from #503. Bans any producer importing a concrete writer of another producer. Stays green throughout the epic.
- `scripts/check-target-foundation-only.sh` — **new**, #536 phase 0. Enforces the foundation-only allow-list for any producer listed in its `STRICT_PRODUCERS` array. Phase 0 ships with `STRICT_PRODUCERS` empty; each phase 3 PR adds producers to it after the producer is audited.

Both scripts run as part of the verification rule for every PR in this epic.

## Interim regime (Sept 2025 to mid-May 2026)

The table below documents what's still tolerated until each producer migrates. This is the CURRENT state — the target state is the section above.

**Rules of thumb (interim):**

- Foundation primitives — always allowed.
- A target may import its own `*Models` companion (foundation-only).
- A target may import other `*Models` targets (foundation-only protocol + value-type seams).
- A target may import the **infra** trio: `Logging`-side is `LoggingModels` only (the concrete `Logging` writer is binary-only, never imported by features); `Diagnostics` is read-only probes; `ASTIndexer` is a SwiftSyntax wrapper.
- A target **may not** import another **feature** target. Cross-feature coupling is via protocols defined in `*Models`; concrete is supplied at the composition root.
- A target **may not** reach for `Shared.Constants.BinaryConfig.shared` or any `Shared.Constants.defaultX` static accessor — those are the Singleton + Service-Locator surface removed in #535.

## Status legend

- ✅ matches contract
- ⚠ has more imports than contract permits (each excess listed)
- 🔄 in flight — being fixed in current PR

## Layers

### Foundation (own imports only, Models / Foundation primitives, plus `*Models` companions)

| Target | Allowed imports | Current state |
|---|---|---|
| `LoggingModels` | Foundation | ✅ Foundation |
| `SharedConstants` | Foundation, CryptoKit | ✅ CryptoKit, Foundation, SharedConstants, SharedUtils (the SharedUtils import is a circular tunnel for `Shared.Utils.JSONCoding` used by `BinaryConfig`; resolved when #535 lands and the file-scope `BinaryConfig.shared` accessor is gone — until then this is the one residual cycle) |
| `SharedUtils` | Foundation, SharedConstants | ✅ |
| `SharedModels` | Foundation, SharedConstants, SharedUtils | ✅ |
| `SharedCore` | Foundation, SharedConstants | ✅ |
| `SharedConfiguration` | Foundation, SharedConstants, SharedUtils | ✅ |
| `Resources` | Foundation | ✅ |
| `MCPCore` | Foundation | ✅ Foundation |
| `MCPSharedTools` | Foundation, MCPCore, SharedConstants, SharedCore | ✅ |

### Models (protocol seams + value types; foundation-layer deps only)

| Target | Allowed imports | Current state |
|---|---|---|
| `CoreProtocols` | Foundation, SharedConstants, SharedCore, SharedModels, Resources | ✅ |
| `CrawlerModels` | Foundation, SharedConstants, SharedModels | ✅ |
| `CorePackageIndexingModels` | Foundation, SharedConstants, SharedModels, CoreProtocols, ASTIndexer | ✅ |
| `SearchModels` | Foundation, SharedConstants, SharedModels | ✅ |
| `SampleIndexModels` | Foundation, SharedConstants | ✅ (`Sample.Index.databasePath(baseDirectory:)` / `.sampleCodeDirectory(baseDirectory:)` take explicit base directory — no static reach to `Shared.Constants.defaultBaseDirectory` after #535) |
| `ServicesModels` | Foundation, SharedConstants, SharedCore, SearchModels, SampleIndexModels | ✅ |

### Infrastructure (wraps a system API; foundation-layer deps + foundation-tier system frameworks)

| Target | Allowed imports | Current state |
|---|---|---|
| `ASTIndexer` | Foundation, SwiftSyntax, SwiftParser | ✅ |
| `Diagnostics` | Foundation, SQLite3 | ✅ |
| `Logging` (writer) | Foundation, OSLog, LoggingModels, SharedConstants, SharedCore | ✅ binary-only (CLI / TUI / MockAIAgent are the only consumers — features import only `LoggingModels`) |

### Features (behaviour; consume protocols from Models layer, no other features)

| Target | Allowed imports | Current state |
|---|---|---|
| `Core` | Foundation, WebKit, LoggingModels, Resources, ASTIndexer, CoreProtocols, CorePackageIndexingModels, SharedConfiguration, SharedConstants, SharedCore, SharedModels, SharedUtils | ✅ |
| `CoreJSONParser` | Foundation, CoreProtocols, SharedConstants, SharedModels | ✅ |
| `CorePackageIndexing` | Foundation, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, Resources, SharedConstants, SharedCore, SharedModels, SharedUtils | ✅ |
| `CoreSampleCode` | Foundation, AppKit, WebKit, LoggingModels, SharedConstants, SharedCore, SharedUtils | ✅ |
| `Crawler` | Foundation, os, WebKit, CoreProtocols, CrawlerModels, LoggingModels, Resources, SharedConfiguration, SharedConstants, SharedCore, SharedModels, SharedUtils | ✅ |
| `Cleanup` | Foundation, LoggingModels, SharedConstants, SharedCore, SharedModels | ✅ |
| `Search` | Foundation, SQLite3, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, SearchModels, SharedConstants, SharedCore, SharedModels, SharedUtils | ✅ |
| `SampleIndex` | Foundation, OSLog, SQLite3, ASTIndexer, LoggingModels, SampleIndexModels, SharedConstants, SharedCore, SharedUtils | ✅ |
| `Services` | Foundation, SampleIndexModels, SearchModels, ServicesModels, SharedConstants, SharedCore, SharedUtils | ✅ |
| `Indexer` | Foundation, SampleIndexModels, SearchModels, SharedConstants, SharedCore, SharedUtils | ✅ |
| `Ingest` | Foundation, LoggingModels, SharedConstants, SharedCore, SharedModels, SharedUtils | ✅ |
| `Distribution` | Foundation, SharedConstants, SharedCore | ✅ |
| `Availability` | Foundation, FoundationNetworking, SharedConstants, SharedUtils | ✅ |
| `RemoteSync` | Foundation, SharedConstants, SharedCore, SharedUtils | ✅ |
| `MCPSupport` | Foundation, LoggingModels, MCPCore, MCPSharedTools, SharedConfiguration, SharedConstants, SharedCore, SharedModels, SharedUtils | ✅ |
| `SearchToolProvider` | Foundation, MCPCore, MCPSharedTools, SampleIndexModels, SearchModels, ServicesModels, SharedConstants, SharedCore, SharedUtils | ✅ |

### Apps (composition roots; can import anything)

Build-system convention: every entry in this section is declared `.executableTarget(...)` in `Package.swift` (not a library). They are inherently impls — they wire feature targets together to produce a binary, so the "every target must lift out of the monorepo cleanly" rule does not apply. The Swift namespace anchors inside (`enum CLIImpl`, files named `CLIImpl.*.swift`, the renamed `ReleaseToolImpl.swift`) carry the `*Impl` suffix so the impl/library distinction is visible at a glance without checking `Package.swift`.

| Target | Allowed imports | Current state |
|---|---|---|
| `CLI` (`enum CLIImpl`) | everything | ✅ composition root, executableTarget → `cupertino` |
| `TUI` | everything | ✅ executableTarget → `cupertino-tui` |
| `MCP` (lib) | everything in its layer | ✅ |
| `MockAIAgent` | everything | ✅ executableTarget → `mock-ai-agent` |
| `ReleaseTool` (`ReleaseToolImpl.swift`) | ArgumentParser, Foundation, SQLite3, SharedConstants, SharedCore, SharedUtils | ✅ executableTarget → `cupertino-rel`, binary, not a producer |

## What this contract bans

If you grep `^import ` under `Sources/<Target>/` and see anything not in the **Allowed imports** column for that target — it's a violation. Examples of what would be bad:

- `Sources/Search/**` importing `Core` (concrete feature → feature). Fix: lift the type to a `*Models` target or define a protocol seam.
- `Sources/Crawler/**` importing `Logging` (concrete writer; only `LoggingModels` is allowed).
- Any producer target reading `Shared.Constants.BinaryConfig.shared` or `Shared.Constants.defaultBaseDirectory` (Singleton + Service Locator). Fix: receive `Shared.Paths` or an explicit `URL` by parameter.

The build CI enforces this via `scripts/check-package-purity.sh` (source-import audit) + `scripts/check-target-portability.sh` (proves each target lifts standalone with only its declared deps).
