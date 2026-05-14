# Per-package import contract

Single source of truth for what each target is **allowed** to import. Anything else in `^import` lines under that target's `Sources/` is a **violation** of the strict-DI / standalone-portability rules.

**Rules of thumb:**

- Foundation primitives (`Foundation`, `SwiftSyntax`, `SwiftParser`, `os`, `OSLog`, `WebKit`, `AppKit`, `SQLite3`, `CryptoKit`, `FoundationNetworking`, `ArgumentParser`, `Testing`) — always allowed.
- A target may import its own `*Models` companion (foundation-only).
- A target may import other `*Models` targets (they're all foundation-only protocol + value-type seams).
- A target may import the **infra** trio: `Logging`-side is `LoggingModels` only (the concrete `Logging` writer is binary-only, never imported by features); `Diagnostics` is read-only probes; `ASTIndexer` is a SwiftSyntax wrapper.
- A target **may not** import another **feature** target. Cross-feature coupling is via protocols defined in `*Models`; concrete is supplied at the composition root.
- A target **may not** reach for `Shared.Constants.BinaryConfig.shared` or any `Shared.Constants.defaultX` static accessor — those are the Singleton + Service-Locator surface being removed in #535. Paths are injected via `Shared.Paths` or explicit `URL` parameters.

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

| Target | Allowed imports | Current state |
|---|---|---|
| `CLI` | everything | ✅ composition root |
| `TUI` | everything | ✅ |
| `MCP` (lib) | everything in its layer | ✅ |
| `MockAIAgent` | everything | ✅ |
| `ReleaseTool` | ArgumentParser, Foundation, SQLite3, SharedConstants, SharedCore, SharedUtils | ✅ (binary, not a producer) |

## What this contract bans

If you grep `^import ` under `Sources/<Target>/` and see anything not in the **Allowed imports** column for that target — it's a violation. Examples of what would be bad:

- `Sources/Search/**` importing `Core` (concrete feature → feature). Fix: lift the type to a `*Models` target or define a protocol seam.
- `Sources/Crawler/**` importing `Logging` (concrete writer; only `LoggingModels` is allowed).
- Any producer target reading `Shared.Constants.BinaryConfig.shared` or `Shared.Constants.defaultBaseDirectory` (Singleton + Service Locator). Fix: receive `Shared.Paths` or an explicit `URL` by parameter.

The build CI enforces this via `scripts/check-package-purity.sh` (source-import audit) + `scripts/check-target-portability.sh` (proves each target lifts standalone with only its declared deps).
