# Design: CupertinoDataEngine (iOS-buildable read engine)

| Field | Value |
|---|---|
| **Status** | accepted, facade slice published, concrete reader extraction in progress |
| **Created** | 2026-05-30 |
| **Last revised** | 2026-06-08 |
| **Tracking issue** | #1261 |
| **Implementation note** | #1261 has shipped the external `CupertinoDataEngine` backend facade at v0.2.2, but the issue is not complete. The engine conforms to the public read/browse contracts, fans out across configured source readers plus packages, and now has a public source-corpus read-only construction path. Samples, packages, and the current full production reader parity path still come through Cupertino-internal composition, so external app clients cannot yet construct the complete engine by public API alone. The remaining #1261 work is the §13 extraction of `Search.Connection` plus the read/write type split so the concrete read-storage closure lives in the external engine package. |
| **Companion docs** | [`per-source-db-split.md`](per-source-db-split.md), [`536-standalone-portability-and-linux-port.md`](536-standalone-portability-and-linux-port.md) |

---

## TL;DR

Extract cupertino's real read engine into a new cupertino-owned public package, CupertinoDataEngine, that builds for iOS and exposes source, sample, and package reader capabilities. cupertino-desktop's iOS variants cannot spawn `cupertino serve` (no subprocess), so the iOS app must embed a real read engine in-process; this package is that engine, consumed by version tag like the other owned packages. The public contract must never expose storage files, database handles, or SQLite vocabulary to app UI code. The headline decision: the engine ships the read path, while the write/index/crawl machinery that lives in the same concrete target today is excluded or kept behind Cupertino-internal composition seams so the iOS product carries no crawl code. This is a larger, riskier carve-out than CupertinoDataKit (pure value types) because the current concrete reader implementation interleaves read and write across many files.

2026-06-08 implementation slice: `CupertinoDataEngine` now exists as an app-facing backend boundary in an external package consumed by this repo through a SwiftPM URL dependency. v0.2.0 made the engine itself the composed `Search.Database` / `Search.DocumentBrowsing` facade: it routes reads by URI source, fans out source-level queries, includes package search, and fuses unified results without exposing storage. v0.2.1 adds a public empty-facade initializer so downstream tests and previews do not import SPI just to exercise composition. v0.2.2 adds the first public concrete source-corpus reader: configured source resources open read-only inside the engine package, and engine-package tests cover search, reads, browsing, symbols, availability, and inheritance. It is not yet the final standalone lean package described above because samples, packages, and the current full production parity path still rely on `CupertinoComposition`. The remaining extraction must move those concrete read-storage slices out of the monorepo so embedded apps can open the complete corpus without SPI.

---

## 1. Context

### 1.1 Problem
CupertinoDataKit (#1183, shipped; v0.2.0 for the document-browser refinements) gives us the read contracts (`DocumentReading` + `SymbolReading`, plus optional `Search.DocumentBrowsing`, all read value types, and open-ended source IDs). It is protocols only: it has no implementation a third party can run. cupertino-desktop's macOS app reaches the engine over MCP (`cupertino serve` subprocess); the iOS app cannot, because iOS has no subprocess. The iOS app therefore needs the actual read engine compiled into its Cupertino backend layer, while app UI code still talks only to backend interfaces.

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
- **G2**: It exposes full read + UI browser capabilities through source-reader interfaces conforming to CupertinoDataKit's read contracts; app UI code never receives database handles or storage implementation types.
- **G3**: cupertino owns/publishes/tags it; consumers depend by version tag (same sole-control rule as SwiftMCPCore / SwiftMCPClient / CupertinoDataKit).
- **G4**: Single source of truth preserved: the monorepo consumes the engine package and re-exports; no duplicated engine code; full `xcrun swift build` + `xcrun swift test` stay green.

### P1
- **G5**: The shipped iOS engine product contains no crawl/fetch/index-write symbols.

### P2
- **G6**: Engine recipes added to `check-target-portability.sh` and `check-target-foundation-only.sh` so the guards stay green.

---

## 3. Non-goals

- **NG1**: Crawl / fetch / index-write capability on iOS. The iOS engine is read-only at runtime; the corpus is built on macOS/server and handed to the Cupertino backend as an installed catalog handle.
- **NG2**: Reimplementing or forking the engine for iOS. Desktop does not want a second impl.
- **NG3**: Making a breaking read-contract change or retagging an existing CupertinoDataKit release.
- **NG4**: Corpus delivery to the device. Mobile delivery is download-only, uses `Application Support/Catalogs` by default, and remains the app's `CatalogStore` concern.

---

## 4. Requirements

### 4.1 Functional

| ID | Requirement | Verified by |
|---|---|---|
| F1 | Engine conforms `Search.DocumentReading` (search / getDocumentContent / listFrameworks / documentCount / disconnect) | read tests in the engine package's own test target (see test-migration note below) |
| F2 | Engine conforms `Search.SymbolReading` (symbol / inheritance / availability / resource methods) | AST + inheritance tests in the engine test target |
| F3 | Engine opens a read-only corpus resource at a CONFIGURABLE path, asserting the file exists, with no directory-create and no write-pragmas (§7.1) | new test: open a read-only corpus file from a read-only dir, assert success; assert clear failure when a configured corpus resource is absent |

### 4.2 Non-functional

| ID | Requirement | Target | Current state |
|---|---|---|---|
| N1 | iOS-buildable | engine + closure compile for an iOS destination | macOS package build/test are green for v0.2.2; the iOS destination build remains the acceptance bar for the full closure, and the §6 Bridge/type split still matters because the complete read/write separation is not done |
| N2 | No crawl symbols in product | 0 fetch/index-write symbols in the engine target | not yet measured (write files still in SearchSQLite) |
| N3 | Monorepo stays green | 0 build errors, full test suite passing | green at develop f74202a9 before this work |

---

## 5. Design Overview

```
CupertinoDataKit (contract: protocols + value types, Foundation-only)
        ^                                   ^
        | conforms                          | depends (by tag)
        |                                    \
CupertinoDataEngine (source/sample/package readers, iOS-buildable)
        ^
        | @_exported re-export + write concretes
        |
cupertino monorepo (SearchSQLite successor) ----> CLI / serve / indexers
        ^
        | depends (by tag), embeds in-process
        |
cupertino-desktop iOS app (MobileBackend.live(dataSource:))
```

Target-state design: CupertinoDataEngine holds Cupertino's read-required helpers, depends on CupertinoDataKit (the contract) plus the minimal foundation-tier seams the read path needs, and owns the concrete storage integration internally. The monorepo depends on the engine and re-exports it, retaining only the write/index concretes. The iOS app embeds the engine behind `MobileBackend.live(dataSource:)`; only that Cupertino backend implementation opens a prebuilt corpus, while UI code talks to the backend interface.

First implementation slice: CupertinoDataEngine is an external backend facade, not yet the final extracted reader. Clients that receive an already-constructed engine can use it directly as the composed read/browser facade or ask for source, sample, and package readers. File presence, schema validation, and the first public source-corpus read-only constructor live in the engine package. `CupertinoComposition` still supplies the current production factories that import `SearchSQLite` / `SampleIndexSQLite`, and samples/packages still require their own extraction slices; app UI packages should depend on the facade or app-specific backend protocols, not on those concrete storage targets.

### 5.1 Single-source vs multi-source fan-out (verified, scope-critical)

Internal implementation fact: one current concrete source reader wraps exactly one source corpus file. The CLI/serve composition root builds one reader per source descriptor (`CLIImpl.Command.Save.Indexers.swift` loops `orderedGroups`). Post per-source split (#1036) the current corpus ships 8 source resources (apple-documentation, hig, swift-org, swift-book, swift-evolution, apple-archive, apple-sample-code, packages), but the source set is open-ended and future sources must not require a contract redesign.

The cross-source UNIFIED search (RRF fusion across opened per-source readers) does NOT live in the current concrete source reader; it lives ABOVE it, in `ServicesModels.UnifiedSearcher` + `SearchAPI.SmartQuery` + `SearchToolProvider.CompositeToolProvider` (verified). So embedding a single source reader on iOS yields ONE source's results, not the unified search a user expects.

Therefore "embed the engine" is under-specified. Two sub-options (Q6):
- **(A) Engine ships source-leaf readers only.** Cupertino backend opens N source readers and the app layer would need its own fusion. Smallest engine, but pushes the fusion algorithm onto the consumer, which re-introduces the drift the extraction exists to kill (desktop would reimplement RRF).
- **(B) Engine ships the fan-out too.** Pull contract-typed fan-out into / alongside the engine so app backends get one call that fuses across the opened source readers. Larger, but the consumer gets real unified search with no reimplementation. Portability is favorable: `SearchToolProvider` imports only `MCPCore`/`MCPSharedTools`/`SearchModels`/`SampleIndexModels`/`ServicesModels`/`SharedConstants` (verified iOS-clean), and `UnifiedSearcher` is in Foundation-only `ServicesModels`.

This is unresolved and material: option (A) means desktop's current `DocumentReading` adapter (wired to a single source reader) silently returns single-source results; the doc must not let that ship as if it were complete (see Q6, R6).

---

## 6. Detailed Design

### 6.1 Read / write classification (the load-bearing step)

`SearchSQLite` is 33 files (MEASURED). `Search.Index` is one actor whose extensions span query (read) and indexing (write). The extraction stands or falls on splitting these cleanly.

**The split is type-level, not just file-level (verified against source).** This is the crux the rest of this section depends on:

- `Search.Index` conforms BOTH `Search.Database` (read; `Search.Index.Database.swift:14`) AND `Search.IndexWriter` (write; `Search.Index.IndexWriter.swift:17`). It is one actor with two conformances. Moving the type into a read-only package cannot simply "leave the write files behind": the `IndexWriter` conformance lives on the same type.
- The write methods mutate the actor's **`internal`** stored state: `var database: OpaquePointer?`, `var isInitialized`, `let dbPath`, `public internal(set) var incrementalSkips` (verified, `Search.Index.swift`). Swift extensions in a *different module* can access `public`/`open` members only, NOT `internal`/`private`. So the write methods cannot stay in the monorepo as an extension on an engine-module `Search.Index` while touching that internal state. The compiler will reject it.
- Consequence: the per-file READ/WRITE table below is necessary but NOT sufficient. One of these must hold for the engine to be read-only:
  - (i) **The whole `Search.Index` actor ships in the engine, write methods included**, and the monorepo simply does not call them on iOS. The engine then is not literally read-only code, only read-only in use. Smallest refactor; violates G5/N2 (crawl/write symbols in the product).
  - (ii) **Split the type:** the engine owns a read-only `Search.Index` (conforming `Search.Database` only); the write surface moves to a distinct type (e.g. `Search.Indexer` actor in the monorepo) that owns its own DB handle. True separation; largest refactor; the honest path to G5.
  - (iii) **Promote the shared stored state** (DB handle + lifecycle) to a small `public` base the engine owns, with write methods as a monorepo extension over the public surface. Middle cost; risks leaking the DB handle as public API.
  **DECIDED (maintainer 2026-05-30): decoupling is mandatory, so option (ii), the type split, via the GoF Bridge pattern.** Options (i) "ship the whole actor" and (iii) "promote shared state to public" are rejected: (i) ships dormant crawl+parse code and SwiftSyntax onto iOS (§6.2) and leaves read and write fused; (iii) leaks the DB handle as public API. Both fail the decoupling requirement. See §6.6 for the Bridge design. Q5 is resolved.

  New evidence bearing on Q5 (see §6.2): option (i) "ship the whole actor" drags SwiftSyntax/ASTIndexer onto iOS even though the read path never parses Swift, bloating the iOS binary with crawl+parse code that is dormant at runtime. Option (ii) "split the type" lets the read engine drop SwiftSyntax entirely. So the dependency-weight argument now favours (ii), partially against the earlier convenience lean toward (i): (i) is a smaller refactor but a heavier iOS binary; (ii) is a bigger refactor but a genuinely lean read-only iOS engine.

Draft classification (to be confirmed by the compiler in §13):

- **READ (ship in engine):** `Search.Index.swift`, `.Search`, `.QueryParsing`, `.SemanticSearch`, `.SearchByAttribute`, `.Inheritance`, `.InheritanceFromMarkdown`, `.CountsAndAliases`, `.CamelCaseSplitter`, `.Database`, `.Schema` (version read), `.ResourceListing`, `.PlatformAvailability`, `.Helpers`, `.DocLinkRewriter`, `Search.PackageQuery`, `Search.SearchResult`, `DocKind`, `CandidateFetcher` (read half).

  Note (verified): `Search.PackageQuery` (`Search.PackageQuery.swift:27`) is a SEPARATE actor from `Search.Index`, conforming `Search.PackagesSearcher` (`:1010`) for the packages.db reader. The engine must carry this second reader type + its protocol. Confirm `PackagesSearcher` lives in (or moves to) the contract so the engine conforms it the same way it conforms `Search.Database`.
- **WRITE / INDEX (exclude or seam to monorepo):** `Search.Index.IndexWriter`, `.Indexing`, `.IndexingDocs`, `.ContentAndPackages` (write half), `.Migrations`, `.CodeExamples`, `.AppleStaticConstraints`, `.AppleStaticConformances`, `.HierarchyConstraints`, `.HIGPlatformInference`, `PackageIndex`, `PackageIndexer`, `Search.PackageIndex.Writer`, `Search.SourceIndexer`.

Note: `Search.Index.Search.swift` itself matched the crawl/write grep; that is expected (it references shared helpers), so per-file compilation, not grep, is the authority on which side a file lands.

### 6.2 Dependency closure

SearchSQLite deps today (MEASURED): `SearchModels`, `SearchSchema`, `SharedConstants`, `LoggingModels`, `CoreProtocols`, `CorePackageIndexingModels`, `ASTIndexer`, `SampleIndexModels`. Target state: CupertinoDataEngine depends on CupertinoDataKit + only the seams the read path needs. Each dep is admitted only when the compiler proves the read closure requires it. `CorePackageIndexingModels` is a strong candidate to drop (it is index-side); `SampleIndexModels` enters only if read results reference sample types.

**ASTIndexer / SwiftSyntax is index-time only, NOT a read dependency (verified, first-principles).** Five SearchSQLite files import `ASTIndexer`: `Search.Index.swift`, `Search.Index.IndexingDocs.swift`, `Search.Index.Indexing.swift`, `PackageIndexer.swift`, `PackageIndex.swift`. Every actual `ASTIndexer.` CALL (`ASTIndexer.Extractor()`, `ASTIndexer.Symbol`, `ASTIndexer.AvailabilityParsers`) is in a WRITE/INDEX file (`IndexingDocs`, `Indexing`, `PackageIndexer`, `PackageIndex`, verified by grep). The import in `Search.Index.swift` is line 1 only with NO use in that file's body (verified: the sole `ASTIndexer` token in the file is the import statement). The READ path, including `SymbolReading`, reads pre-extracted symbol columns from the DB; it never parses Swift source, so it needs neither `ASTIndexer` nor SwiftSyntax/SwiftParser. Consequence: a type-split read engine (§6.1 option ii) sheds the heaviest external dependency (SwiftSyntax), shrinking the closure and the iOS binary; the vestigial line-1 import in `Search.Index.swift` is removed when the index methods move out. This is a concrete payoff of (ii) over (i) and strengthens N1 feasibility. Acceptance: the read target compiles with no `ASTIndexer` dependency.

**Constructor pulls index-side types (verified).** `Search.Index.init` takes `indexers: [String: any Search.SourceIndexer]` and `sourceLookup: Search.SourceLookup` (both `public nonisolated let`, `Search.Index.swift`). `Search.SourceIndexer` is the indexer (write-side) protocol. So even the read engine's constructor signature references index-side types unless the type is split per §6.1 option (ii). For option (i)/(iii), the iOS app must construct `Search.Index` supplying an empty `indexers: [:]` and an `.empty` `sourceLookup` (the same values the existing read-only tests pass, e.g. `Issue1073` fixtures use `indexers: [:], sourceLookup: .empty`). The engine's public API should offer a read-only convenience init that defaults these, so an iOS caller never names a write-side type. This is part of F3.

### 6.3 Conformance

`extension Search.Index: Search.Database {}` already holds in-repo and moves with the engine. The engine imports CupertinoDataKit for the protocol and value types (which the monorepo already re-exports from there post-#1183).

### 6.4 Monorepo rewire

Two candidate shapes, decided after the §6.1 split compiles:
- (a) `SearchSQLite` becomes a thin target: `@_exported import CupertinoDataEngine` plus the retained write concretes.
- (b) `SearchSQLite` dissolves into the engine (read) plus a sibling `SearchSQLiteIndexing` (write).

Either way the `@_exported` re-export pattern from #1183 keeps every existing consumer compiling with no per-target import edits.

### 6.5 Ownership / distribution

Public repo `mihaelamj/CupertinoDataEngine`, cupertino-owned; v0.1.0 is the first facade tag, v0.2.0 adds the composed fan-out read surface, v0.2.1 adds a public empty-facade initializer for downstream composition tests, and v0.2.2 adds the first public source-corpus read-only construction slice. Consumers pin the tag range, and the monorepo consumes the URL dependency using the same #1183 playbook as CupertinoDataKit.

### 6.6 Decoupling via the GoF Bridge pattern (decided)

The problem, stated precisely (verified §6.1 + handle scan): two abstractions, read (`Search.Database`) and write (`Search.IndexWriter`), are conformed by one `Search.Index` actor, and BOTH access the same low-level resource directly: the `database: OpaquePointer?` handle plus its lifecycle (`openDatabase`, `disconnect`, `isInitialized`). Read files reference `database` 11 to 23 times each. Decoupling them while they share a connection is exactly the problem GoF Bridge addresses: "decouple an abstraction from its implementation so the two can vary independently" (GoF 1994, p.151).

Mapping to Bridge roles:

- **Implementor** = `Search.Connection` (new): owns `database: OpaquePointer?`, `openDatabase` / read-only-open (§7.1) / `disconnect` / `isInitialized`, and the low-level `prepare` / `exec` / `step` helpers. This is the single home for SQLite-handle management. An actor (the isolation that today lives on `Search.Index` moves here).
- **Refined Abstraction A (read)** = the engine's read type conforming `Search.Database` (+ `Search.SymbolReading`), holding a `Search.Connection`. Ships in CupertinoDataEngine. No SwiftSyntax (§6.2).
- **Refined Abstraction B (write)** = `Search.Indexer` conforming `Search.IndexWriter`, holding its own `Search.Connection`, plus the index/migration/crawl-adjacent methods and the `ASTIndexer` dependency. Stays in the monorepo.

Why Bridge specifically (vs the rejected options):
- It removes the cross-module `internal`-access blocker (Finding A/B): the write type is its OWN type with its OWN `Connection` reference, never an extension reaching into a foreign module's private actor state. The shared surface is `Search.Connection`'s PUBLIC helpers, deliberately designed as the implementor API, not a leaked handle (which is why option iii was rejected: iii leaks the raw `OpaquePointer`; Bridge exposes typed prepare/exec, not the pointer).
- Read and write now vary independently: a new read method touches only Abstraction A; a new index pass touches only Abstraction B; neither forces a change on the other or on the implementor unless the SQLite primitive surface itself changes.
- The implementor can have two creation modes (read-only open per §7.1, read-write open for the writer) without the abstractions knowing which: the Bridge implementor encapsulates that.

Migration shape (each step compiler-verified, §13): (1) extract `Search.Connection` from `Search.Index`'s stored state + open/close + prepare/exec helpers; (2) rewrite the read methods to call through `Search.Connection` instead of the bare `database`; (3) move write methods to a new `Search.Indexer` over its own `Search.Connection`; (4) `Search.Index` (read) ships in the engine, `Search.Indexer` (write) in the monorepo. This is the bulk of the work and the reason the epic is non-trivial; Bridge is the structure that makes each step local and compilable rather than a big-bang rewrite.

---

## 7. Data Model

No new schema. The engine reads the existing per-source DBs defined in [`per-source-db-split.md`](per-source-db-split.md) and [`per-db-schema-spec.md`](per-db-schema-spec.md).

### 7.1 Read-only open + configurable path (maintainer directive 2026-05-30)

The current `Search.Index` open path is incompatible with a bundled read-only DB on iOS (verified against `Search.Index.swift`):
- `init` calls `FileManager.default.createDirectory(...)` (line 157), assuming a writable parent dir. iOS app-bundle resources are read-only.
- `openDatabase` does a read-write `sqlite3_open` (line 224) and executes `PRAGMA journal_mode = WAL`, `PRAGMA synchronous = NORMAL`, `PRAGMA journal_size_limit` (lines 246/272/289). WAL + those pragmas are writes to the DB and its `-wal`/`-shm` sidecars; they fail against a read-only file in a read-only directory.

Maintainer directive sets the contract, removing this from "open question" to "fixed design":
1. **Assume the DBs are where they need to be.** The engine does NOT create directories, does NOT assume `~/.cupertino`, and does NOT crawl/build. It is handed a location.
2. **Assert presence.** On open, the engine asserts each configured DB file exists and is a valid DB; if not, it fails fast with a clear error (no silent fallback, no implicit build).
3. **The path is configurable.** The caller (iOS app, CLI, serve) injects where the DBs live; the engine has no hardcoded base dir.

Design consequence: the engine gains a **read-only open mode** for the embedded case: `sqlite3_open_v2(..., SQLITE_OPEN_READONLY)`, skipping `createDirectory`, skipping the WAL/synchronous/journal write-pragmas (a read-only connection needs none of them; readers can read a WAL or non-WAL DB without setting journal mode). The existing read-write open path stays for the CLI/serve writer. This is a behaviour-preserving addition (a new init/open mode), not a change to the existing writer path. Satisfies F3.

### 7.2 Schema-version binding (first-principles: "DBs are where they need to be" is necessary but not sufficient)

"Assume the DBs are present and configurable" (§7.1) is about *location*. It does not cover *compatibility*, which is a separate hard coupling (verified against source):

- The binary carries a compile-time `Search.Schema.currentVersion` (= 18 today, `SearchSchema/Search.Schema.CurrentVersion.swift:24`).
- On open, `checkAndMigrateSchema` (`Search.Index.Migrations.swift`) reads the DB's `PRAGMA user_version` and, on mismatch with no migrator, THROWS: "this binary is being run against a database produced by a different build. Run `cupertino setup`."
- The recovery path (migrate, or stamp `user_version`) WRITES the DB. On a read-only bundled DB that write cannot happen.

First-principles consequence the engine design must own:
- A tagged **CupertinoDataEngine release is hard-bound to a schema version** (v18 at the facade tags). The iOS app ships {engine tag, DB bundle, app} and the engine tag's schema version MUST equal the bundle's `user_version`, or the engine cannot open the DB and cannot migrate it (read-only).
- The read-only open mode (§7.1) must therefore **assert schema match and skip migration entirely**: if `user_version == currentVersion`, open and serve; otherwise fail fast with a clear "engine vX expects schema N, bundle is schema M; ship a matching pair" error. It must NOT attempt the write-path migration.
- This makes the engine's schema version part of its PUBLIC contract: a schema bump is a breaking engine release, and the bundle + engine tag move together. Document the engine tag to schema-version mapping at publish time so consumers pin a compatible pair. (Relates to the #1071 per-source-bundle chain, which produces the bundles the engine will read.)

### 7.3 The fan-out is a second contract, not just a movable type (first-principles on Q6)

`Services.UnifiedSearcher` is a PROTOCOL (`ServicesModels/Services.UnifiedSearcher.swift:17`) with `func searchAll(...)`, a DIFFERENT shape than `Search.Database.search`. So "ship the fan-out" (Q6 option B) is not "move a type": it requires (a) the `UnifiedSearcher` protocol as part of the read contract (it arguably belongs in CupertinoDataKit next to `Search.Database`), and (b) a concrete conformer that holds N `Search.Database` instances (one per opened DB) and fuses with RRF. The monorepo builds such a conformer today in its composition root; the engine package would need to ship one so an iOS caller gets unified search without reimplementing fusion. This is the substance behind Q6 and R6: the choice is whether CupertinoDataEngine owns the `UnifiedSearcher` conformer (real unified search for consumers) or leaves it out (each consumer wires N engines + its own fusion).

**DECIDED (Q6): the engine ships a cross-source reader, structured as GoF Composite, defined on CONTRACT types, NOT the existing `Services.UnifiedSearcher`.** First-principles reading of the source settles both the shape and a trap:

- Shape = GoF Composite (1994, p.163): "compose objects into tree structures and let clients treat individual objects and compositions uniformly." The cross-source reader is the composite; each per-DB `Search.Database` is a leaf; a client calls one search surface and the composite fans out to its leaves. This is exactly the leaf/composite uniformity Composite exists for, and it composes cleanly with the §6.6 Bridge (each leaf is a Bridge read abstraction over its own `Search.Connection`).
- Trap (verified, do NOT reuse the existing type): the in-repo `Services.UnifiedSearcher.searchAll(...)` returns `Services.Formatter.Unified.Input` (a PRESENTATION type) and does not itself rank-fuse; it gathers per-source arrays for the formatter, and carries an 11-arg signature coupled to cupertino's source registry (`availableSources: [String]`, `appleImports`, etc.). Shipping that as the engine's cross-source API would (a) drag `Services.Formatter` presentation types into the contract, violating CupertinoDataKit's data-only purity, and (b) export cupertino's registry coupling to every consumer.
- Therefore the engine implements the composite directly on the existing `Search.Database` / `Search.DocumentBrowsing` contracts, returning contract types only. The constructor takes the set of `Search.Database` leaves the caller opened through Cupertino-internal factories. cupertino's existing `Services.UnifiedSearcher` stays in the monorepo as the presentation-coupled wrapper over read results. No presentation type crosses into the engine contract.
- Scope note: cross-source RRF fusion shipped in `CupertinoDataEngine` v0.2.0 as a `Search.Result`-level ranking step over merged leaf results. It depends only on rank/score already on `Search.Result` (contract type), so it stays iOS-portable.

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
7. Publish + tag the facade package, swap the monorepo path to a URL dep, and ping desktop to wire `MobileBackend.live(dataSource:)` against the tagged engine.

CI gates: the existing foundation-only + portability guards must learn the CupertinoDataEngine recipe (they already learned CupertinoDataKit's in #1183).

**Test-migration cost (verified, do not understate).** 86 test files `@testable import SearchSQLite` today (70 in `SearchTests`, 12 in `SearchToolProviderTests`, 2 in `SearchSQLiteTests`, plus `CLICommandTests`/`MCP`). `@testable` reaches `internal` symbols, which does NOT cross a module boundary once the engine is a separate package, the same `internal`-access constraint as §6.1. So the read tests for engine code must either move into the engine package's own test target (where `@testable import CupertinoDataEngine` works) or convert to public-API tests. This is a substantial sub-task, sequenced in phase 6; F1/F2 are verified there, not by leaving the tests in the monorepo pointed at a now-external module. Tests for code that STAYS in the monorepo (write/index) keep their `@testable import` of the monorepo target.

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
**Rejected**: two engine implementations drift; the contract extraction exists to prevent exactly that. Desktop explicitly declined, and desktop UI code must not touch the DB directly.
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
| Q3 | Read-only open against a bundled DB | RESOLVED by directive (§7.1): add a read-only open mode (`SQLITE_OPEN_READONLY`, no dir-create, no write-pragmas), configurable path, assert-exists |
| Q4 | Name: CupertinoDataEngine (confirmed by maintainer 2026-05-30) | resolved |
| Q5 | Type-split: whole actor (i) / split (ii) / promote base (iii)? | RESOLVED: option (ii), the type split via GoF Bridge (§6.6); decoupling is mandatory, so the read abstraction, the write abstraction, and the shared `Search.Connection` implementor vary independently |
| Q6 | Fan-out scope (§5.1): per-DB only vs engine ships cross-source reader? | RESOLVED: engine ships a cross-source reader as GoF Composite over `Search.Database` leaves (§5.1, §7.3), using existing CupertinoDataKit contract types, NOT the presentation-coupled `Services.UnifiedSearcher`. cupertino's `Services.UnifiedSearcher` remains a monorepo presentation wrapper |
| Q6a | Does the composite apply cross-source RRF fusion, or return grouped per-source results? | RESOLVED in v0.2.0: apply lightweight RRF fusion over contract `Search.Result` rows |

### Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Read/write entanglement: `Search.Index` conforms BOTH `Search.Database` and `Search.IndexWriter` on one actor sharing a SQLite handle | high | high | RESOLVED structurally by GoF Bridge (§6.6): extract `Search.Connection` implementor, split into read (`Search.Index`) + write (`Search.Indexer`) abstractions over it; each migration step compiler-verified |
| R2 | `URLSession`/fetcher refs ride into the engine target | high | med | exclude fetch/index files; audit product for crawl symbols |
| R3 | Foundation-tier rewire blast radius across the monorepo | med | med | `@_exported` re-export (zero-edit in #1183) + full build/test + CI guards |
| R4 | "No iOS-hostile imports" does not equal "iOS-builds" | med | high | real iOS `xcrun swift build` is the acceptance bar |
| R5 | Tag immutability / ownership | low | med | sole-control rule established + acked by desktop |
| R6 | iOS ships single-source search (one `Search.Index`) thinking it is complete, because the cross-source fan-out was left in the monorepo | med | high | RESOLVED by Q6: engine ships the Composite cross-source reader, so a consumer gets unified search without reimplementing fusion |
| R8 | Engine's cross-source API leaks presentation types (`Services.Formatter.*`) or registry coupling into the contract by reusing `Services.UnifiedSearcher` as-is | med | med | Q6 forbids reuse: define a new contract-typed composite protocol returning `Search.Result`/`Search.UnifiedResults`; keep `Services.UnifiedSearcher` as a monorepo presentation wrapper |
| R7 | Engine tag and DB bundle drift on schema version; engine refuses to open the bundle (and cannot migrate, read-only) | med | high | §7.2: read-only mode asserts schema match + skips migration; publish the engine-tag to schema-version mapping; move bundle + engine tag together |

---

## 17. Future Work

- Complete the sample/package/full production parity slices after the v0.2.2 source-corpus reader.
- Wire CupertinoDataEngine behind `cupertino-desktop`'s mobile backend using the v0.2.2 composed read facade.
- Corpus delivery to device as a separate app-side `CatalogStore` design; mobile is download-only and never stores catalog data in `Documents`.
- If the full engine proves not iOS-clean, keep the external facade as the stable read-only slice and grow the lean concrete implementation behind it later.

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
