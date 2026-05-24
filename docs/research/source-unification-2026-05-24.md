# Source unification: making "add a new source" a one-target operation

**Date:** 2026-05-24
**Status:** research / analysis. No code yet.
**Authoring context:** user direction "research, analyze, read rules, ask cupertino. We will make a document first." after `feedback_sources_100pct_pluggable` was challenged with two concrete examples.

## Problem

Cupertino's "source pluggability" claim was overstated. The #935 end-to-end test (PR #941) proved the **search-side pipeline** accepts a fake source given the right wiring, but it did not exercise the CLI's `cupertino fetch` surface. Adding a new source today actually requires editing **5 files across 3 SPM targets**, not 2 files in 1 target:

| # | Edit | File | Co-located with strategy? |
|---|---|---|---|
| 1 | Strategy concrete | new `<X>Strategy/` target | yes (post #899) |
| 2 | Indexer concrete | `SearchSQLite/Search.SourceIndexer.swift` (along with the other 7) | no |
| 3 | `Search.SourceDefinition` literal | `CLI/CLIImpl.SourceLookup.swift` | no |
| 4 | `FetchType` enum case + ~6 switch arms | `CLI/SupportingTypes.swift` | no |
| 5 | Indexer-dict entry | `CLI/Commands/CLIImpl.Command.Save.Indexers.swift` | no |

Two additional structural issues surfaced when reviewing the live code:

- **`FetchType` is a closed enum** with six `switch self` sites (displayName, crawlBaseURLs, defaultOutputDir, webCrawlTypes, etc.). Every new fetch type forces an edit at every switch arm. This is the textbook anti-pluggability shape.
- **`FetchType` (10 cases) is not 1:1 with `Search.Source` (8 cases).** `.availability` and `.all` are fetch-only meta-types; `swiftOrg` and `swiftBook` are search sources but not fetch types. A unification must handle the asymmetry without collapsing it.

## What the rules require

### `mihaela-agents/Rules/swift/gof-di-rules.md`

- **Rule 3.** Cross-package coupling via named protocols, declared in foundation-only `*Models` targets. The composition root is the only place that wires concretes from multiple producers.
- **Rule 4.** No closure typealiases at cross-target seams. Forbidden: `typealias Indexer = (URL) async throws -> Void`. Required: `protocol IndexerStrategy: Sendable { func index(url: URL) async throws }`.
- **Rule 5.** Every package lifts out (`scripts/check-target-portability.sh`). Each per-source target must be standalone-buildable.
- **Rule 6.** Binary name stays clean, `*Impl` marks the wiring source. Composition roots can import anything; producers cannot.
- **Rule 8 target regime.** Producer foundation-only; each producer declares its own protocols inline; `*Models` dissolves long-term. Interim regime (current) allows `*Models` companions.
- **Rule 1.** No Singletons reachable from producer code, including `Shared.Constants.defaultX`-style accessors.

### `mihaela-agents/Rules/swift/per-package-import-contract.md`

- Standalone-portable unit: producer + its `*Models` companion. A new per-source target must lift out alone with `<X>Source` + `SearchModels` + `SharedConstants` + `LoggingModels`.
- Foundation primitives + foundation-tier (`Resources`, `Diagnostics`, `ASTIndexer`) + `*Models` seams are always allowed.
- A producer target may not import another producer's concrete writer target. The composition root supplies concretes.

### `mihaela-agents/Rules/swift/components/`

The Component system is the canonical mihaela-agents plugin shape for SwiftUI components. Key elements:
- `protocol Component: Sendable` with associated types + `static var kind: ComponentKind` + `init(data: Data)` + `make() -> ViewBody`.
- `ComponentsRegistry` with a `decoders: [ComponentKind: ...]` dict.
- Type-erased `AnyComponent` wrapper for heterogeneous storage.
- Each component registers itself: `static func register(in registry: ComponentsRegistry)`.

The shape is reusable for any plugin domain, not just SwiftUI components.

## Reference implementations (cross-referenced)

### secret-life (`mihaela-analytics/secret-life`)

Direct prior art, audited at `Docs/protocol-seam-audit.md`. The same shape we want for cupertino:

```swift
// Sources/Import/Importer/Importer.swift (foundation-only target)
public protocol Importer: Sendable {
    var sourceKind: String { get }
    var parserVersion: Int { get }
    func discoverFiles(under sourcesRoot: URL) throws -> [URL]
    func importFile(at url: URL, into transaction: Transaction) throws -> ImportSummary
}

// Sources/Import/Importer/ImporterRegistry.swift
public struct ImporterRegistry: Sendable {
    public struct Entry: Sendable {
        public let importer: any Importer
        public let isEnabled: Bool
    }
    private var entries: [String: Entry] = [:]
    public mutating func register(_ importer: any Importer, isEnabled: Bool = true) { ... }
}
```

48 concrete importers, **each its own SPM target** with `public struct <Name>Importer: Importer`. The registry wiring file (`CLIImpl.Registry.swift`) is **generated** from filesystem layout by `cli regenerate-registry`, which greps for `public struct <Name>: Importer` under `Sources/Import/Importers/`. A `RegistryDriftTests` runs the codegen in `--check` mode every test; CI fails loudly on drift.

The secret-life add-a-source workflow (`AddingASource.md`):

1. Pick a source-kind name.
2. Write the DDL chunk + migration (if the source needs new tables).
3. Scaffold the importer package (flat-single-file or folder-based).
4. Pin a real-fixture test.
5. Regenerate the registry.
6. Commit single PR.

This is exactly the shape the user described: **per-source code lives in ONE place**; registration is mechanical and generated.

### SwiftNIO (`apple/swift-nio`)

Referenced in `per-package-import-contract.md`. `NIOCore` is foundation-only (protocols + value types). `NIOPosix` is the concrete impl. `NIOHTTP1` is a higher feature with `NIOCore`-only deps. Confirms: protocols live in a foundation-only target; concretes are in separate targets; no concrete imports another concrete.

### swift-log (Apple SSWG)

Single foundation-only `Logging` target carries the `LogHandler` protocol. OS-coupled handlers live in separate packages. Cupertino's `LoggingModels` + `Logging` writer follow the same shape, and cupertino's six `*Models` companions generalize it per-producer.

### mihaela-agents `Component` pattern

Three-package hierarchy: `Components` (core, zero deps) → `SharedComponents` (hot reload) → `AppComponents`. Each component is a `Component` conformer with `static var kind`, `static func register(in:)`. Same pattern adapts to non-UI domains.

## Design space

Four shapes considered. Trade-offs first, then ranking.

### Option A: closure manifests in a value type

```swift
public struct SourceManifest: Sendable {
    public let definition: Search.SourceDefinition
    public let fetchInfo: Search.FetchInfo?
    public let makeStrategy: @Sendable (Environment) -> any Search.SourceIndexingStrategy
    public let makeIndexer: @Sendable () -> any Search.SourceIndexer
}
```

Pros: simple to construct, no protocol gymnastics, no metatype `any Source.Type` to thread through APIs.

Cons: **violates Rule 4** (closure typealiases at cross-target seams). The `makeStrategy` field is a `@Sendable` closure-typed cross-target contract. Same shape the rule explicitly forbids.

**Rejected.** Rule 4 is canonical.

### Option B: protocol with associated types

```swift
public protocol Source: Sendable {
    associatedtype Strategy: Search.SourceIndexingStrategy
    associatedtype Indexer: Search.SourceIndexer
    static var definition: Search.SourceDefinition { get }
    static var fetchInfo: Search.FetchInfo? { get }
    static func makeStrategy(env: Environment) -> Strategy
    static func makeIndexer() -> Indexer
}
```

Pros: type-safe; the concrete strategy/indexer types appear in the conforming target's signature.

Cons: associated types prevent `[any Source.Type]` collections. You either need a type-erased `AnyStorageRegistration` wrapper (as the Component system uses) or restrict to homogeneous lists. Forces a `AnySource` wrapper at the composition root for the registry.

**Plausible.** Higher type-safety but extra wrapper.

### Option C: protocol with `any` existentials in the static API

```swift
public protocol Source: Sendable {
    static var definition: Search.SourceDefinition { get }
    static var fetchInfo: Search.FetchInfo? { get }
    static func makeStrategy(env: Environment) -> any Search.SourceIndexingStrategy
    static func makeIndexer() -> any Search.SourceIndexer
}
```

Pros: simple existential storage in `[any Source.Type]`; the composition root iterates without wrappers; matches secret-life's `[any Importer]` pattern. Static requirements are GoF Factory Method (p. 107).

Cons: the existential `any Search.SourceIndexingStrategy` cost shows up at index time, not query time; irrelevant given the indexing arc runs once per source per crawl.

**Recommended.** Matches secret-life's verified working pattern. No closure typealiases. Simple registry shape.

### Option D: instance-method protocol on a registered factory

```swift
public protocol SourceProvider: Sendable {
    var definition: Search.SourceDefinition { get }
    var fetchInfo: Search.FetchInfo? { get }
    func makeStrategy(env: Environment) -> any Search.SourceIndexingStrategy
    func makeIndexer() -> any Search.SourceIndexer
}
```

The composition root holds `[any SourceProvider]` (instances), not metatypes.

Pros: lets a provider hold per-instance configuration (e.g., env-overridable URLs). Matches the secret-life `ImporterRegistry.register(_ importer: any Importer)` shape exactly.

Cons: most cupertino sources have zero per-instance state; the metatype version (C) is leaner.

**Equivalent.** Choose C or D based on whether per-instance config is wanted.

## Recommendation

**Adopt Option C or D.** Both are GoF-canonical (Factory Method, Strategy), Rule-3-compliant, Rule-4-compliant, Rule-5-compliant.

Lean toward **D** because it matches secret-life's `ImporterRegistry` shape verbatim. It is the user's own audited reference implementation. Adapting that exact pattern is the lowest-risk path. The slight extra ceremony (instances instead of metatypes) is worth the precedent alignment.

### Concrete shape

```swift
// SearchModels/Search.SourceProvider.swift  (foundation-only)
extension Search {
    public protocol SourceProvider: Sendable {
        var definition: Search.SourceDefinition { get }
        var fetchInfo: Search.FetchInfo? { get }
        func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy
        func makeIndexer() -> any Search.SourceIndexer
    }
}

// SearchModels/Search.SourceRegistry.swift  (foundation-only)
extension Search {
    public struct SourceRegistry: Sendable {
        public struct Entry: Sendable {
            public let provider: any Search.SourceProvider
            public let isEnabled: Bool
        }
        private var entries: [String: Entry] = [:]
        public init() {}
        public mutating func register(_ provider: any Search.SourceProvider, isEnabled: Bool = true) {
            entries[provider.definition.id] = Entry(provider: provider, isEnabled: isEnabled)
        }
        public var allEnabled: [any Search.SourceProvider] {
            entries.values.filter(\.isEnabled).map(\.provider)
        }
        public func provider(for sourceID: String) -> (any Search.SourceProvider)? {
            entries[sourceID]?.provider
        }
    }
}

// AppleDocsSource/AppleDocsSource.swift  (its own SPM target)
public struct AppleDocsSource: Search.SourceProvider {
    public init() {}
    public var definition: Search.SourceDefinition { .appleDocs }       // value type literal at module load
    public var fetchInfo: Search.FetchInfo? { .appleDocs }
    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        AppleDocsStrategy(docsDirectory: env.docsDirectory, markdownStrategy: env.markdownStrategy, logger: env.logger)
    }
    public func makeIndexer() -> any Search.SourceIndexer {
        Search.AppleDocsIndexer()
    }
}

// CLI composition root  (the only edit point for adding a source)
let registry = Search.SourceRegistry().register(AppleDocsSource())
    .register(HIGSource())
    .register(SamplesSource())
    .register(AppleArchiveSource())
    .register(SwiftEvolutionSource())
    .register(SwiftOrgSource())
    .register(SwiftBookSource())
    .register(PackagesSource())
    // .register(WWDCTranscriptsSource())   <- adding a new source = ONE line here
```

### Per-source target structure

Each source gets its own SPM target (e.g., `AppleDocsSource/`):

```
Packages/Sources/AppleDocsSource/
├── AppleDocsSource.swift                # the SourceProvider conformer
├── AppleDocsSource.Definition.swift     # the static let appleDocs: SourceDefinition literal
├── AppleDocsSource.FetchInfo.swift      # the static let appleDocs: FetchInfo literal
├── AppleDocsStrategy.swift              # the indexing strategy (moved here from AppleDocsStrategy/)
└── AppleDocsIndexer.swift               # the indexer (moved here from SearchSQLite)
```

Adding a new source becomes:
1. Create `Packages/Sources/<X>Source/` with the 4-5 files above.
2. Add `<X>Source` as a library target in `Packages/Package.swift` (allowed imports: `SearchModels`, `SharedConstants`, `LoggingModels`, `CoreProtocols`, `Resources`).
3. Append `.register(<X>Source())` to the composition root list.

Three edits, all small. Adding the SPM target manifest entry could be optionally automated via codegen (secret-life precedent) but is not required.

### What dissolves

- `FetchType` enum (10 cases + 6 switch arms): replaced by iterating `registry.allEnabled` for `cupertino fetch`. Meta-types `availability` and `all` become CLI flags, not enum cases.
- `Search.IndexerRegistry` (live as a `[String: any Search.SourceIndexer]` dict at composition root today): collapses into `registry.provider(for:)?.makeIndexer()`.
- `CLIImpl.makeProductionSourceLookup` (8-literal hardcoded list): collapses into `Search.SourceLookup(definitions: registry.allEnabled.map(\.definition))`.

## Open design questions

1. **`Search.IndexEnvironment` shape.** The strategy/indexer factories need shared environment (logger, docs dir, markdown strategy, etc.). Define a single `IndexEnvironment` value type in `SearchModels`, or pass each dep separately? Single value type is cleaner; let providers ignore the bits they don't need.

2. **Codegen vs hand-wired registry assembly.** secret-life generates `Registry.swift` from filesystem layout + adds a `RegistryDriftTests`. Worth it for cupertino's 8 sources? Probably not initially; the value is in the scaling argument (48 importers in secret-life made it worth it). Can be added later if cupertino grows past ~15 sources.

3. **Migration strategy.** Parallel path (new `SourceProvider` shape alongside `FetchType` enum, migrate one source at a time) vs big-bang. Strict-DI epic showed parallel-path is safer. Recommend: define protocol + registry + migrate AppleDocs as proof-of-concept first; only after that lands and is reviewed, migrate the other 7 in lockstep.

4. **What about `Search.Source` (the `String`-wrapping value type)?** Already pluggable post-#924 (open struct, not closed enum). The 8 static-constant accessors stay as convenience; the registry doesn't replace them.

5. **`SearchSQLite/Search.SourceIndexer.swift` extension files.** Some indexers are 200+ lines and reach into `import SQLite3`. Moving them to per-source targets requires the per-source target to import SQLite3. That violates Rule 5 if `<X>Source` is supposed to be standalone-portable with foundation-only deps. Resolution: keep the indexer protocol surface in `SearchModels` and the concrete indexer LOGIC in `<X>Source/`; the SQLite operations the indexer needs go through the `Search.IndexWriter` protocol that's already injected via the strategy's `index(into:progress:)` signature. Indexers don't need direct SQLite3 access; they convert source items to typed writes that the writer applies.

6. **Test fixtures.** Each per-source target gets its own test target with a real-corpus fixture (secret-life precedent). Adds ~1-2 test files per source. Worth doing as part of each migration PR.

## Scope estimate

Epic shape, similar to #893 producer-backend-split:

| Phase | Scope | PRs | Estimate |
|---|---|---|---|
| 1 | Define `Search.SourceProvider` protocol + `Search.SourceRegistry` value type in `SearchModels`. Define `Search.FetchInfo` value type. Define `Search.IndexEnvironment`. Migrate AppleDocs as proof-of-concept (new `AppleDocsSource/` target, registry assembly at composition root in parallel to existing `FetchType` enum). | 1 | 1-2 days |
| 2-8 | Migrate the remaining 7 sources one at a time: HIG, Samples, AppleArchive, SwiftEvolution, SwiftOrg, SwiftBook, Packages. Each is a small PR creating a `<X>Source/` target + moving the indexer in + appending to the registry. | 7 | ~½-1 day each |
| 9 | Dissolve `FetchType` enum + `IndexerRegistry` + `makeProductionSourceLookup`. Add a `cupertino fetch --source <id>` runtime flag iterating the registry. Update CHANGELOG + `docs/package-import-contract.md`. | 1 | 1 day |
| 10 | (Optional) Codegen registry assembly + drift test, secret-life-style. | 1 | ½ day |

Total: 9-10 PRs over 1-2 weeks of focused work.

## Risks

- **Build-time complexity.** Adding 8 new SPM targets bumps the producer count from 47 to 55. Cold build time should not regress meaningfully (each new target is small and depends only on foundation-tier seams).
- **Strategy / indexer ownership.** A few strategies share helpers (`SearchStrategyHelpers`). Need to keep that shared target intact and just move the per-source files into the new target.
- **`FetchInfo` migration drift.** The `FetchType` enum encodes URL knowledge (`Shared.Constants.BaseURL.*`) and path resolution (`Shared.Paths`). The migration must preserve both. Worth a test that asserts the new `FetchInfo` value for each migrated source matches the old `FetchType` enum case's outputs.
- **Test coverage gap.** Each per-source migration must keep the existing 1473-test suite green. The fixture-per-source recommendation adds tests but is not a strict requirement; the existing integration tests should keep passing.

## Recommendation

Open an epic ("#NEW: Source unification: per-source self-contained targets + registry"). Phase 1 (define protocol + migrate AppleDocs as proof) is the load-bearing PR. Subsequent migrations are mechanical follow-ons.

The user's `feedback_sources_100pct_pluggable` rule is met when:
- adding a new source = create `<X>Source/` target + append one `.register(<X>Source())` line at the composition root
- no edits to `FetchType` (it's gone), `IndexerRegistry` (gone), `makeProductionSourceLookup` (collapsed to iteration), or `SearchSQLite/Search.SourceIndexer.swift` (concretes moved to per-source targets)
- mechanical drift test (optional, secret-life-style) catches divergence

## Cross-refs

- `mihaela-agents/Rules/swift/gof-di-rules.md` (Rules 1, 3, 4, 5, 6, 8 load-bearing for this design)
- `mihaela-agents/Rules/swift/per-package-import-contract.md` (foundation-only producer regime)
- `mihaela-agents/Rules/swift/components/` (the canonical mihaela-agents plugin shape; same pattern, different domain)
- `mihaela-analytics/secret-life/Docs/protocol-seam-audit.md` + `AddingASource.md` (audited prior art; 48-importer working implementation)
- Memory: `feedback_sources_100pct_pluggable` (the standing rule this design fulfills)
- Memory: `cupertino-epic-893-closed-2026-05-24` (the structural infrastructure this builds on)
- Memory: `feedback_gof_di_rules_canonical` (the principle layer)
- Cupertino code:
  - `Packages/Sources/SearchModels/Search.SourceIndexingStrategy.swift` (existing strategy protocol; stays in place)
  - `Packages/Sources/SearchSQLite/Search.SourceIndexer.swift` (existing indexer protocol + 7 concretes; concretes migrate per-source)
  - `Packages/Sources/SearchModels/Search.SourceDefinition.swift` (existing descriptor value type; stays)
  - `Packages/Sources/CLI/CLIImpl.SourceLookup.swift` (existing composition root; dissolves into iteration)
  - `Packages/Sources/CLI/SupportingTypes.swift` (FetchType enum; deleted in Phase 9)
  - `Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift` (existing indexer dict at composition root; collapses)
