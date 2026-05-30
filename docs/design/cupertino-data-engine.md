# Design: CupertinoDataEngine (iOS-buildable read engine)

| Field | Value |
|---|---|
| **Status** | draft |
| **Created** | 2026-05-30 |
| **Last revised** | 2026-05-30 |
| **Tracking issue** | none (follow-on to CupertinoDataKit #1183) |
| **Companion docs** | [`per-source-db-split.md`](per-source-db-split.md), [`536-standalone-portability-and-linux-port.md`](536-standalone-portability-and-linux-port.md) |

---

## TL;DR

Extract cupertino's real FTS-SQLite read engine (`Search.Index`, today in the `SearchSQLite` target) into a new cupertino-owned public package, CupertinoDataEngine, that builds for iOS and conforms to CupertinoDataKit's `Search.Database` contract. cupertino-desktop's iOS variants cannot spawn `cupertino serve` (no subprocess), so the iOS app must embed a real read engine in-process; this package is that engine, consumed by version tag like the other owned packages. The headline decision: the engine ships the read path, while the write/index/crawl machinery that lives in the same `SearchSQLite` target is excluded or seamed off so the iOS product carries no crawl code. This is a larger, riskier carve-out than CupertinoDataKit (pure value types) because `Search.Index` interleaves read and write across 33 files.

---

## 1. Context

### 1.1 Problem
CupertinoDataKit (#1183, shipped) gave us the read contract (`Search.Database` = `DocumentReading` + `SymbolReading`, plus all read value types, Foundation-only, v0.1.0). It is protocols only: it has no implementation a third party can run. cupertino-desktop's macOS app reaches the engine over MCP (`cupertino serve` subprocess); the iOS app cannot, because iOS has no subprocess. The iOS app therefore needs the actual FTS-SQLite read engine compiled into the app.

### 1.2 Why the obvious approaches do not work
- Reimplement a minimal SQLite reader on the app side: produces a second engine implementation, the exact drift the contract extraction exists to kill.
- Fold the engine into CupertinoDataKit: that package is zero-impl, Foundation-only; adding SQLite breaks its purity and forces every contract consumer to link SQLite.
- Ship `SearchSQLite` as-is for iOS: it carries write/index/crawl code the app never runs.

### 1.3 Why now
#1183 just landed, so the contract is stable and `Search.Index` already conforms to it. Desktop's MobileData is merged and explicitly blocked on this engine for the iOS path.

---

## 2. Goals

### P0
- **G1**: A public package CupertinoDataEngine that builds standalone for iOS (acceptance: `xcrun swift build` for an iOS destination is green).
- **G2**: It conforms `Search.Database` from CupertinoDataKit (full read surface).
- **G3**: cupertino owns/publishes/tags it; consumers depend by version tag (same sole-control rule as SwiftMCPCore / SwiftMCPClient / CupertinoDataKit).
- **G4**: Single source of truth preserved: the monorepo consumes the engine package and re-exports; no duplicated engine code; full `xcrun swift build` + `xcrun swift test` stay green.

### P1
- **G5**: The shipped iOS engine product contains no crawl/fetch/index-write symbols.

### P2
- **G6**: Engine recipes added to `check-target-portability.sh` and `check-target-foundation-only.sh` so the guards stay green.

---

## 3. Non-goals

- **NG1**: Crawl / fetch / index-write capability on iOS. The iOS engine is read-only at runtime; the corpus is built on macOS/server and shipped as a prebuilt SQLite DB the app opens.
- **NG2**: Reimplementing or forking the engine for iOS. Desktop does not want a second impl.
- **NG3**: Changing the `Search.Database` contract or the CupertinoDataKit v0.1.0 tag.
- **NG4**: Corpus delivery to the device (bundled vs downloadable DB). That is the app's `CatalogStore` concern.

---

## 4. Requirements

### 4.1 Functional

| ID | Requirement | Verified by |
|---|---|---|
| F1 | Engine conforms `Search.DocumentReading` (search / getDocumentContent / listFrameworks / documentCount / disconnect) | existing SearchSQLite read tests, run against the engine package |
| F2 | Engine conforms `Search.SymbolReading` (symbol / inheritance / availability / resource methods) | existing AST + inheritance tests |
| F3 | Engine opens a read-only / bundled DB without assuming a writable base dir | new test against a read-only DB file |

### 4.2 Non-functional

| ID | Requirement | Target | Current state |
|---|---|---|---|
| N1 | iOS-buildable | engine + closure compile for an iOS destination | imports verified iOS-clean (no WebKit/AppKit/FoundationNetworking/Cocoa); iOS build NOT yet run |
| N2 | No crawl symbols in product | 0 fetch/index-write symbols in the engine target | not yet measured (write files still in SearchSQLite) |
| N3 | Monorepo stays green | 0 build errors, full test suite passing | green at develop f74202a9 before this work |

---

## 5. Design Overview

```
CupertinoDataKit (contract: protocols + value types, Foundation-only)
        ^                                   ^
        | conforms                          | depends (by tag)
        |                                    \
CupertinoDataEngine (Search.Index read engine, SQLite3, iOS-buildable)
        ^
        | @_exported re-export + write concretes
        |
cupertino monorepo (SearchSQLite successor) ----> CLI / serve / indexers
        ^
        | depends (by tag), embeds in-process
        |
cupertino-desktop iOS app (MobileBackend.live(dataSource:))
```

CupertinoDataEngine holds the `Search.Index` actor and the read-required helpers, depends on CupertinoDataKit (the contract) plus the minimal foundation-tier seams the read path needs, and links `SQLite3`. The monorepo depends on the engine and re-exports it, retaining only the write/index concretes. The iOS app embeds the engine and opens a prebuilt DB.

---

## 6. Detailed Design

### 6.1 Read / write classification (the load-bearing step)

`SearchSQLite` is 33 files (MEASURED). `Search.Index` is one actor whose extensions span query (read) and indexing (write). The extraction stands or falls on splitting these cleanly.

Draft classification (to be confirmed by the compiler in §13):

- **READ (ship in engine):** `Search.Index.swift`, `.Search`, `.QueryParsing`, `.SemanticSearch`, `.SearchByAttribute`, `.Inheritance`, `.InheritanceFromMarkdown`, `.CountsAndAliases`, `.CamelCaseSplitter`, `.Database`, `.Schema` (version read), `.ResourceListing`, `.PlatformAvailability`, `.Helpers`, `.DocLinkRewriter`, `Search.PackageQuery`, `Search.SearchResult`, `DocKind`, `CandidateFetcher` (read half).
- **WRITE / INDEX (exclude or seam to monorepo):** `Search.Index.IndexWriter`, `.Indexing`, `.IndexingDocs`, `.ContentAndPackages` (write half), `.Migrations`, `.CodeExamples`, `.AppleStaticConstraints`, `.AppleStaticConformances`, `.HierarchyConstraints`, `.HIGPlatformInference`, `PackageIndex`, `PackageIndexer`, `Search.PackageIndex.Writer`, `Search.SourceIndexer`.

Note: `Search.Index.Search.swift` itself matched the crawl/write grep; that is expected (it references shared helpers), so per-file compilation, not grep, is the authority on which side a file lands.

### 6.2 Dependency closure

SearchSQLite deps today (MEASURED): `SearchModels`, `SearchSchema`, `SharedConstants`, `LoggingModels`, `CoreProtocols`, `CorePackageIndexingModels`, `ASTIndexer`, `SampleIndexModels`. Target state: CupertinoDataEngine depends on CupertinoDataKit + only the seams the read path needs. Each dep is admitted only when the compiler proves the read closure requires it. `CorePackageIndexingModels` is a strong candidate to drop (it is index-side); `SampleIndexModels` enters only if read results reference sample types.

### 6.3 Conformance

`extension Search.Index: Search.Database {}` already holds in-repo and moves with the engine. The engine imports CupertinoDataKit for the protocol and value types (which the monorepo already re-exports from there post-#1183).

### 6.4 Monorepo rewire

Two candidate shapes, decided after the §6.1 split compiles:
- (a) `SearchSQLite` becomes a thin target: `@_exported import CupertinoDataEngine` plus the retained write concretes.
- (b) `SearchSQLite` dissolves into the engine (read) plus a sibling `SearchSQLiteIndexing` (write).

Either way the `@_exported` re-export pattern from #1183 keeps every existing consumer compiling with no per-target import edits.

### 6.5 Ownership / distribution

Public repo `mihaelamj/CupertinoDataEngine`, cupertino-owned; owner publishes + tags v0.1.0; consumers pin the tag. During development the monorepo uses a local `path:` dep, swapped to the URL after the first tag (the #1183 playbook). The owner publishes; this session never pushes to GitHub.

---

## 7. Data Model

No new schema. The engine reads the existing per-source DBs defined in [`per-source-db-split.md`](per-source-db-split.md) and [`per-db-schema-spec.md`](per-db-schema-spec.md). The one new requirement (F3) is that the engine opens a read-only / bundled DB without assuming a writable base dir.

---

## 9. Scalability Analysis

Not applicable. The engine is the existing query path unchanged; this is a packaging extraction, not a perf or scale change. Read latency and corpus scale are governed by the existing FTS5 design.

---

## 10. Reliability & Failure Modes

| Failure mode | Detection | Mitigation |
|---|---|---|
| A "read" method transitively needs an index helper | compile error during §6.1 split | move the helper into the engine, or refactor it behind a seam so the write concrete stays in the monorepo |
| Engine compiles but pulls crawl symbols into the iOS product | symbol audit on the built engine (G5/N2) | exclude the fetch/index files from the engine target |
| iOS build fails despite clean imports | `xcrun swift build` iOS destination (N1) | the iOS build is the acceptance bar, not import inspection; fall back to read-only slice (see §15.1) |
| Monorepo consumer breaks on rewire | full `xcrun swift build` + test | `@_exported` re-export pattern (proven zero-edit in #1183) |

What we explicitly do not recover: index/write on iOS. It is a non-goal; the DB is prebuilt off-device.

---

## 11. Security & Privacy

No data collection. No network access at runtime (read-only local SQLite). The engine opens a bundled/downloaded DB file; corpus delivery and its trust model are the app's concern (NG4). No new threat surface beyond reading a local file.

---

## 13. Testing Strategy

Phased, each phase compiler-verified, one step at a time:

1. Classify the 33 files read vs write (the §6.1 draft, confirmed by compilation).
2. Scaffold CupertinoDataEngine (Package.swift, iOS16/macOS13/tvOS16/watchOS9/visionOS1, swift-tools 6.0, CupertinoDataKit dep). Acceptance: `xcrun swift build` green (empty).
3. Move read files + minimal dep closure; conform `Search.Database`. Acceptance: engine builds standalone on macOS.
4. iOS build proof. Acceptance: `xcrun swift build` for an iOS destination is green (the real bar for N1).
5. Rewire monorepo SearchSQLite to depend on engine + re-export; keep write concretes. Acceptance: full `xcrun swift build` 0 errors.
6. Full `xcrun swift test` green across cupertino (cite counts). Add engine recipes to `check-target-portability.sh` + `check-target-foundation-only.sh`.
7. Hand off to owner to publish + tag v0.1.0; swap monorepo path to URL dep; ping desktop to wire `MobileBackend.live(dataSource:)`.

CI gates: the existing foundation-only + portability guards must learn the CupertinoDataEngine recipe (they already learned CupertinoDataKit's in #1183).

---

## 14. Rollout & Migration

No runtime behaviour change for existing cupertino users: the CLI / serve paths consume the same engine via re-export. Distribution of the new package follows the #1183 playbook (local `path:` during dev, versioned URL after tag). No DB schema bump. Backward compatibility: the engine reads the same per-source DBs as today.

---

## 15. Alternatives Considered

### 15.1 Read-only slice only (DocumentReading)
**Considered**: extract only the FTS read path conforming `Search.DocumentReading`, exactly what iOS consumes today.
**Rejected**: maintainer chose the full engine so the package is the single home for FTS-SQLite read+intel and does not need re-carving when SymbolReading lands.
**Cost paid**: a bigger, riskier first carve-out; this slice remains the documented fallback if the full engine proves not iOS-clean (R-iOS).

### 15.2 Reimplement a minimal SQLite reader on the app side
**Considered**: cupertino-desktop writes its own small reader against the bundled DB.
**Rejected**: two engine implementations drift; the contract extraction exists to prevent exactly that. Desktop explicitly declined.
**Cost paid**: none worth keeping.

### 15.3 Fold the engine into CupertinoDataKit
**Considered**: one package for contract + impl.
**Rejected**: CupertinoDataKit is zero-impl, Foundation-only; adding SQLite forces every contract consumer to link it and breaks the purity that makes it a clean contract.
**Cost paid**: none.

### 15.4 Keep SearchSQLite as-is, add an iOS build product
**Considered**: no extraction, just an extra product/target for iOS.
**Rejected**: the write/crawl code in the same target bloats the app with unused index machinery and risks Mac-only linkage.
**Cost paid**: none.

---

## 16. Open Questions & Risks

### Open

| ID | Question | Tracking |
|---|---|---|
| Q1 | Final monorepo shape: thin re-export shell vs read/write target split (§6.4) | open, settle after §6.1 compiles |
| Q2 | Does the full SymbolReading/inheritance read path stay iOS-clean, or reach index-time helpers? | open, determines full-engine vs fallback to 15.1 |
| Q3 | Does `Search.Index(dbPath:...)` work against a read-only bundled DB with no writable base dir? | open (F3) |
| Q4 | Name: CupertinoDataEngine vs CupertinoDataSQLite (tech-specific) | open, maintainer preference |

### Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Read/write entanglement in `Search.Index` makes a clean split hard | high | high | per-file classify, compile iteratively, move the seam where the compiler points |
| R2 | `URLSession`/fetcher refs ride into the engine target | high | med | exclude fetch/index files; audit product for crawl symbols |
| R3 | Foundation-tier rewire blast radius across the monorepo | med | med | `@_exported` re-export (zero-edit in #1183) + full build/test + CI guards |
| R4 | "No iOS-hostile imports" does not equal "iOS-builds" | med | high | real iOS `xcrun swift build` is the acceptance bar |
| R5 | Tag immutability / ownership | low | med | sole-control rule established + acked by desktop |

---

## 17. Future Work

- Wire CupertinoDataEngine behind `cupertino-desktop`'s `MobileBackend.live(dataSource:)` once tagged (desktop's task, after v0.1.0).
- Corpus delivery to device (bundled vs downloadable) as a separate app-side design.
- If full engine proves not iOS-clean, ship the read-only slice (15.1) as v0.1.0 and grow later.

---

## 19. References

### Internal
- [`per-source-db-split.md`](per-source-db-split.md): the per-source DB model the engine reads.
- [`per-db-schema-spec.md`](per-db-schema-spec.md): the schema the engine reads.
- [`536-standalone-portability-and-linux-port.md`](536-standalone-portability-and-linux-port.md): the portability discipline + `check-target-*` guards this extends.
- `Packages/Sources/SearchSQLite/` (33 files): the engine being extracted.
- `Packages/Sources/SearchModels/Search.Database.swift` (re-exported from CupertinoDataKit post-#1183): the conformance target.

### Roadmap
- PR #1183: CupertinoDataKit extraction (the contract this engine conforms; the carve-out + re-export pattern this follows).
