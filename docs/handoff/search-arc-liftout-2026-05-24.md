# Search arc lift-out trace, 2026-05-24

Mechanical trace evidence for [#901](https://github.com/mihaelamj/cupertino/issues/901) (verification PR for the Search arc standalone-portability claim under epic [#893](https://github.com/mihaelamj/cupertino/issues/893)). Per `mihaela-agents/Rules/swift/gof-di-rules.md` rule 5 (standalone-portable packages) and `mihaela-agents/Rules/swift/per-package-import-contract.md` (the import-contract this trace verifies, sequencing the cupertino strict-DI epic). #901's "See also" referenced an external `protocol-seam-audit.md` template; that file does not exist on this checkout, so the trace inlines the lift-out check methodology directly: per-target portability harness (`scripts/check-target-portability.sh`) running `swift build --target <T>` against a generated minimal `Package.swift` containing only the target and its transitive closure.

Recorded against develop @ commit 835b621 (PR #997 squash-merge of #900 sub-PR B: Search to SearchAPI rename).

## What this trace proves

Each of the 10 producer + Models-tier targets that came out of the Search dissection arc (#898 + #899 + #900) builds standalone. The dependency closure for each is foundation-only by contract: Foundation tier targets (`SharedConstants`, `LoggingModels`, `Resources`, `ASTIndexer`) plus Models tier seams (`CoreProtocols`, `CorePackageIndexingModels`, `SearchModels`, `SearchSchema`, `SearchStrategyHelpers`, `EnrichmentModels`). The two tiers are defined in `docs/package-import-contract.md`; this trace cross-checks the empirical closure against that contract.

The producer-backend-split principle (epic #893) holds for the Search arc: the orchestration target (`SearchAPI`) is backend-agnostic, the concrete (`SearchSQLite`) is the only target in the arc carrying `import SQLite3`, and the 6 source-indexing strategies plus 1 strategy-helpers utility lift independently of both.

## Acceptance evidence

### 1. Per-target portability check

`bash scripts/check-target-portability.sh <Target>` runs `swift build --target <Target>` against the full workspace and exits 0 iff the target builds.

| Target | Build time | Result |
|---|---|---|
| `SearchAPI` | 3.43s | OK |
| `SearchModels` | 3.97s | OK |
| `SearchSchema` | 4.03s | OK |
| `SearchStrategyHelpers` | 4.06s | OK |
| `AppleArchiveStrategy` | 4.69s | OK |
| `AppleDocsStrategy` | 4.10s | OK |
| `HIGStrategy` | 4.30s | OK |
| `SampleCodeStrategy` | 3.98s | OK |
| `SwiftEvolutionStrategy` | 4.61s | OK |
| `SwiftOrgStrategy` | 4.67s | OK |

All 10 targets exit 0.

### 2. No `SQLite3` in the lifted graph

```
grep -l '^import SQLite3' \
  Packages/Sources/SearchAPI/*.swift \
  Packages/Sources/SearchModels/*.swift \
  Packages/Sources/SearchSchema/*.swift \
  Packages/Sources/SearchStrategyHelpers/*.swift \
  Packages/Sources/AppleArchiveStrategy/*.swift \
  Packages/Sources/AppleDocsStrategy/*.swift \
  Packages/Sources/HIGStrategy/*.swift \
  Packages/Sources/SampleCodeStrategy/*.swift \
  Packages/Sources/SwiftEvolutionStrategy/*.swift \
  Packages/Sources/SwiftOrgStrategy/*.swift
```

Zero hits. The only target in the Search arc that imports SQLite3 is `SearchSQLite` (the concrete), which is correctly outside the lifted-graph set.

### 3. `docs/package-import-contract.md` rows all `OK`

The Producers table in `docs/package-import-contract.md` carries a `✅` mark for every Search-arc target, meaning the actual production-truth dependencies match the foundation-only allowlist. Empirical row content (verified by reading the file at HEAD):

- `SearchModels`: Foundation, SharedConstants
- `SearchAPI`: Foundation, EnrichmentModels, LoggingModels, SearchModels, SharedConstants
- `SearchSQLite`: Foundation, SQLite3, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, SearchModels, SearchSchema, SharedConstants
- `SearchSchema`: Foundation, SearchModels
- `SearchStrategyHelpers`: Foundation, SearchModels, SharedConstants
- Each `<X>Strategy`: Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants

The `SearchAPI` row's allowed-import list is foundation-only by definition: every entry is Foundation, a Foundation-tier target (`SharedConstants`, `LoggingModels`), or a Models-tier seam (`SearchModels`, `EnrichmentModels`). No producer target leaks into the SearchAPI deps.

## Sub-PR shapes recorded by this trace

### Sub-PR A: Whole-Search lift-out

`SearchAPI`'s actual transitive closure (per `Packages/Package.swift` and verified by `scripts/check-target-portability.sh SearchAPI`):

```
SearchAPI + SearchModels + EnrichmentModels + LoggingModels + SharedConstants
```

5 targets. Foundation-tier (`SharedConstants`, `LoggingModels`, Foundation) plus 2 Models-tier seams (`SearchModels`, `EnrichmentModels`). The #901 spec text listed a larger set (`Resources + ASTIndexer + CorePackageIndexingModels + CoreProtocols`); those targets are not in `SearchAPI`'s closure post-#898 sub-PR E (they belong to `SearchSQLite`'s closure, which is excluded from the lift-out). The smaller actual closure is a stronger result, not a weaker one.

Build green via `bash scripts/check-target-portability.sh SearchAPI` (3.43s).

### Sub-PR B: Per-strategy lift-outs

The #901 spec table called for 7 traces (`7 traces, one per <X>Strategy target`). 6 strategies materialized: `AppleArchiveStrategy`, `AppleDocsStrategy`, `HIGStrategy`, `SampleCodeStrategy`, `SwiftEvolutionStrategy`, `SwiftOrgStrategy`. The 7th was never split out: `SwiftPackagesStrategy` was deleted in #789 when the search.db `packages` tables were dropped. The trace records the 6 that exist.

Each strategy's actual closure (per `Packages/Package.swift` and `scripts/check-target-portability.sh`):

```
<X>Strategy + SearchModels + SharedConstants + LoggingModels + CoreProtocols + Resources + SearchStrategyHelpers
```

7 targets per strategy. The #901 spec listed a 4-target closure (`<X>Strategy + SearchModels + SharedConstants + LoggingModels`); the actual closure adds `CoreProtocols` (Models-tier seam for the strategy's protocol interface), `Resources` (Foundation-tier embedded resources), and `SearchStrategyHelpers` (Models-tier helper, foundation-only by contract; extracted by #899 so per-strategy targets share helpers without dragging the SearchStrategies concrete). All 3 extra targets are Foundation- or Models-tier, so the foundation-only contract holds.

All 6 strategy builds green via `bash scripts/check-target-portability.sh <X>Strategy`.

## What this PR ships

- This trace document (`docs/handoff/search-arc-liftout-2026-05-24.md`).
- No code changes. The acceptance criteria were already mechanically green when this trace was captured; the PR's role is to record the evidence and close #901.

## Note on #901 spec drift

#901's acceptance-criteria grep enumerates `Packages/Sources/SearchQuery/`, `Packages/Sources/SearchRanking/`, `Packages/Sources/SearchIntent/`, `Packages/Sources/SearchUtilities/`. None of these targets materialized. #900 stopped at the `Search` to `SearchAPI` rename (sub-PR B) and explicitly deferred sub-PR A (the `SearchQuery` extraction) as low-value organizational churn (the `Search.Database` protocol seam already operates through `SearchModels`). The other 3 names (`SearchRanking`, `SearchIntent`, `SearchUtilities`) were #898 sub-PRs B/C/D in the original dissection plan; only sub-PRs A (`SearchSchema`, PR #913) and E (`SearchSQLite`, PR #914) plus follow-up F (PR #917) shipped. B/C/D were dropped at execution time and their material folded into `SearchModels` (the `Search.QueryIntent` enum + `detectQueryIntent` + `Search.SourceProperties` + `Search.SourceDefinition`) and `SearchSQLite` (the BM25 + heuristics ranking path, the query-parsing helpers). The acceptance grep is therefore reduced to the targets that do exist, all of which are covered by the table in section 1.

## Cross-refs

- Epic [#893](https://github.com/mihaelamj/cupertino/issues/893): producer-backend split.
- Sibling close ceremony: [#907](https://github.com/mihaelamj/cupertino/issues/907) (full epic audit + plan-doc finalisation).
- Pluggability epic [#919](https://github.com/mihaelamj/cupertino/issues/919) (closed by #935 end-to-end TDD proof in PR #941).
- `mihaela-agents/Rules/swift/gof-di-rules.md` rule 5 (standalone-portable packages).
- `mihaela-agents/Rules/swift/per-package-import-contract.md` (the import-contract this trace verifies).
