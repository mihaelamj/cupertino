# How to add a new content source

**State**: living doc. Reflects the post-#1055 layer-2 close-out as of 2026-05-26. Adding a new source within the per-source documentation FTS family is genuinely a **2-file PR**: one new `Packages/Sources/<X>Source/` target + one `.register(<X>Source())` line in `Cupertino.CompositionRoot.swift`.

The 2-file claim is empirically proven by `Issue1042PluggabilityContractTests`, the registry-aware iterations across Doctor / Setup / SaveSiblingGate / Services.ReadService / CLI Search dispatch / MCP CompositeToolProvider, and the layer-2 deepenings (`makeReadStrategy`, `SearchRoute` open struct, `isSearchTier`) closed on 2026-05-26.

## Required: the two files

A new source's minimum surface area is:

1. **A new SPM target** under `Packages/Sources/<X>Source/<X>Source.swift` carrying:
   - The `Search.SourceProvider` conformer (descriptor + capabilities + strategy + indexer + fetch + read strategies)
   - The indexer concrete (`Search.SourceIndexer`)
   - The strategy concrete (`Search.SourceIndexingStrategy`)
   - The fetch strategy concrete (`Search.SourceFetchStrategy`) if the source is fetchable
   - The read strategy concrete (`Search.SourceReadStrategy`) — the shared `Search.DocsReadStrategy` works for any source whose data lives in the per-source documentation FTS family

2. **One `.register(<X>Source())` line** in `Packages/Sources/CupertinoComposition/Cupertino.CompositionRoot.swift`.

Plus the per-source manifest documentation page at `docs/sources/<source-id>/manifest.yaml` (corpus shape, not code) and a row in `Shared.Models.DatabaseDescriptor` if the source ships its own DB.

That's it. No edits to `Fetch.swift`, `Save.Indexers.swift`, `SaveSiblingGate.swift`, `Services.ReadService.swift`, `CLIImpl.Command.Search.swift`, `CompositeToolProvider.swift`, `Doctor.swift`, `SetupService.swift`, `SmartReport.swift`, or any cross-cutting CLI plumbing.

## The `Search.SourceProvider` protocol

Declared in `Packages/Sources/SearchModels/Search.SourceProvider.swift`. Required surfaces:

```swift
public struct WWDCSource: Search.SourceProvider {
    public init() {}

    public var definition: Search.SourceDefinition {
        Search.SourceDefinition(
            id: "wwdc",
            displayName: "WWDC Transcripts",
            emoji: "🎬",
            properties: Search.SourceProperties(
                authority: 0.9,
                freshness: 0.7,
                comprehensiveness: 0.6,
                codeExamples: 0.4,
                hasAvailability: 0.0,
                designFocus: 0.5,
                languageFocus: 0.3,
                searchQuality: 0.7
            ),
            intents: [.howTo, .api]
        )
    }

    public var fetchInfo: Search.FetchInfo? {
        Search.FetchInfo(
            displayName: "WWDC Transcripts",
            sourceID: "wwdc",
            crawlBaseURLs: ["https://developer.apple.com/wwdc/"],
            defaultOutputDirKey: Search.FetchInfo.DefaultOutputDirKey(rawValue: "wwdc")
            // ... see existing concretes for the full surface
        )
    }

    public var destinationDB: Shared.Models.DatabaseDescriptor { .wwdc }

    public var capabilities: Search.Capabilities {
        .init(
            searchers: [.text],
            operations: [.readByURI],
            metadata: [
                .hasMinPlatformVersion: false,
                .hasFrameworkColumn: false,
                .hasMinSwiftVersion: false,
            ]
        )
    }

    public var legacySourceIDAliases: Set<String> { [] }

    public func makeStrategy(env: Search.IndexEnvironment) -> any Search.SourceIndexingStrategy {
        WWDCStrategy(
            wwdcDirectory: env.sourceDirectory,
            markdownStrategy: env.markdownStrategy,
            logger: env.logger,
            importLogSink: env.importLogSink
        )
    }

    public func makeIndexer() -> any Search.SourceIndexer {
        WWDCIndexer()
    }

    public func makeFetchStrategy() -> (any Search.SourceFetchStrategy)? {
        WWDCFetchStrategy()
    }

    public func makeReadStrategy() -> (any Search.SourceReadStrategy)? {
        // FTS-family source — the shared DocsReadStrategy handles it.
        Search.DocsReadStrategy(sourceID: definition.id)
    }

    // Default extensions cover everything below if your source is FTS-family
    // and uses the default search route. Override only when you differ from
    // the default.

    // var searchRoute: Search.SearchRoute { .docs }       // default
    // var isSearchTier: Bool { true }                     // default
}
```

The strategy + indexer + fetch + read concretes live in the same target. Look at `Packages/Sources/AppleDocsSource/` for the reference layout.

## When to override the protocol defaults

| Default | Override when |
|---|---|
| `searchRoute: .docs` | Your source has a bespoke search runner (HIG, samples, packages). Declare `static let myRoute = SearchRoute(rawValue: "my-source-id")` in `Search.SourceRoute` extensions and return it. Unknown routes fall through to `.unified`. |
| `isSearchTier: true` | Your source ships its OWN database family with a non-FTS schema (today: `SampleCodeSource` → `apple-sample-code.db` catalog tables; `PackagesSource` → `packages.db` BM25 + chunks). Return `false` and the unified docs fan-out skips you. |
| `makeFetchStrategy()` returns `nil` (default) | Your source has no direct fetch path and is populated by setup or another source-specific mechanism. Otherwise return your strategy concrete. |
| `makeReadStrategy()` returns `nil` (default) | Always override. Use `Search.DocsReadStrategy(sourceID:)` for the FTS family, or write your own conformer for a custom backend. |

## Pluggable today — surfaces that pick up the new source automatically

Every consumer surface below derives its source list from `Cupertino.CompositionRoot.makeProductionSourceRegistry()`. A new source flows through without editing any of these:

| Consumer | What is automatic |
|---|---|
| **Setup**'s required-DB bundle list | `Distribution.SetupService.Request.required` enumerates `registry.allEnabled.map(\.destinationDB)`. |
| **Doctor**'s `healthChecks` | One `Distribution.SearchHealthCheck` instance per docs-tier descriptor + the transitional `.search` legacy probe. |
| **Doctor**'s `printSchemaVersions` | Registry-iteration; 2 special-case path resolvers handle `.packages` + `.appleSampleCode`. |
| **CLI Save**'s sibling-gate classifier | `SaveSiblingGate.classifyPostSplitSourceID` resolves the source-id via the registry and switches on `destinationDB` (3 stable bucket arms). |
| **CLI Save**'s `Indexers.resolveSourceDirectory` | Registry-built dict with optional typed CLI flag overrides; 2 live sentinel arms (`swift-book`, `samples`) + default. |
| **CLI Read** dispatch (`Services.ReadService.read`) | Iterates `providers: registry.allEnabled` and runs the first `provider.makeReadStrategy()` that returns non-nil. URI-scheme prefix and explicit `--source` hints narrow the candidate set. |
| **CLI Search** runner dispatch | `provider.searchRoute` picks the runner; unknown routes fall through to the unified fan-out. |
| **CLI Search** SmartReport docs fan-out | `.filter(\.isSearchTier)` covers every FTS-family source automatically. |
| **CLI Search** capability-driven CandidateFetcher wiring | `swiftVersionSources` + `frameworkScopedSources` derived from `provider.capabilities.metadata[.hasMinSwiftVersion]` + `.hasFrameworkColumn`. |
| **CLI Fetch** dispatch | `Fetch.swift` collapses to 2 special-token arms + `default → runRegistryFetchStrategy` which runs `provider.makeFetchStrategy()?.run(env:)`. |
| **MCP** `search` tool schema | `CompositeToolProvider.searchToolSourceEnumValues` enumerates registered ids; the Serve composition root wires it. |
| **MCP** `search` tool dispatch | Same `searchRoute`-based dispatch as the CLI side; unknown routes fall through to unified. |
| **MCP** `DocsResourceProvider.knownURISchemes` | Set built from registered ids. |
| **Formatters** (`Footer.Search`, `Unified.{Markdown,Text}`, `TeaserResults`, `Frameworks.*`, `Sample.Format.*`, `HIG.*`) | `availableSources` is non-optional and is the registry-derived list; new sources flow through every formatter. |
| **RemoteSync** indexer phase-URI dispatch | `phaseURIPrefixes: [Phase: String]` consults the composition-root override first. |
| **SearchAPI** fusion weights | `SmartQuery.sourceWeightsOverride: [String: Double]` consulted by `weight(forSource:)` before the static literal. |
| **`Shared.Paths`** generic directory lookup | `Shared.Paths.directory(named: key.rawValue)` handles any `defaultOutputDirKey` value. |
| **Package.swift** test/binary dep lists | `allSourceTargetNames` is the single source of truth; `allSourceTargetDeps` + `allSourceProducts` derive from it. |

## Verifying the new source

After registering:

1. **Build**: `cd Packages && xcrun swift build`
2. **Test sweep**: `cd Packages && xcrun swift test` — expect green; the registry-driven consumers pick up the new source automatically.
3. **Contract test**: `xcrun swift test --filter Issue1042PluggabilityContractTests` — every registry-aware surface + the 3 layer-2 deepenings (`makeReadStrategy` protocol-requirement pin, `SearchRoute` open-struct shape, `isSearchTier` provider override) are pinned here.
4. **Setup check**: `cupertino setup` against a release bundle that ships the new source's DB. The post-extract hard-fail check derives the required-DB list from the production registry; a missing DB fails loudly.
6. **MCP schema check**: `cupertino serve` then `tools/list` shows the new source in the `search` tool's `source` enum.
7. **Doctor check**: `cupertino doctor` runs the registry-iterated health check + schema-version probe against the new source's DB.

## Related design docs

- `docs/audits/2026-05-26-pluggability-deep-audit.md` — the 15-layer deep audit that drove the layer-1 + layer-2 close-out.
- `docs/plans/2026-05-22-source-independence-day.md` — original epic plan; kept as historical context.
- `docs/design/per-source-db-split.md` — #1036's per-source DB split, which created the `destinationDB` field's modern semantics.
- `Packages/Tests/CLITests/Issue1042PluggabilityContractTests.swift` — machine-checkable contract (includes the 3 layer-2 deepenings).
