# Search arc lift-out trace — 2026-05-24

Mechanical trace evidence for [#901](https://github.com/mihaelamj/cupertino/issues/901) (verification PR for the Search arc standalone-portability claim under epic [#893](https://github.com/mihaelamj/cupertino/issues/893)). Per `mihaela-agents/Rules/swift/gof-di-rules.md` rule 5 (standalone-portable packages) + the `mihaela-analytics/secret-life/Docs/protocol-seam-audit.md` "Lift-out checks (mechanical, repeatable)" template.

Recorded against develop @ commit 835b621 (PR #997 squash-merge of #900 sub-PR B: Search → SearchAPI rename).

## What this trace proves

Each of the 9 producer targets that came out of the Search dissection arc (#898 + #899 + #900) builds standalone against external SwiftPM dependencies alone, with only Foundation + the foundation-tier seams (Models targets + `SharedConstants` + `LoggingModels` + `CoreProtocols` + `SearchSchema` + `ASTIndexer` + `CorePackageIndexingModels` + `EnrichmentModels`) for company. Pull any of these targets into a fresh repo with that dep set and it compiles green.

The producer-backend-split principle (epic #893) holds for the Search arc: the orchestration target (`SearchAPI`) is backend-agnostic, the concrete (`SearchSQLite`) is the only target carrying `import SQLite3` in the arc, and the 6 source-indexing strategies + 1 strategy-helpers utility lift independently of both.

## Acceptance evidence

### 1. Per-target portability check

`bash scripts/check-target-portability.sh <Target>` runs `swift build --target <Target>` against the full workspace and exits 0 iff the target builds.

| Target | Build time | Result |
|---|---|---|
| `SearchAPI` | 3.43s | ✅ |
| `SearchModels` | 3.97s | ✅ |
| `AppleArchiveStrategy` | 4.69s | ✅ |
| `AppleDocsStrategy` | 4.10s | ✅ |
| `HIGStrategy` | 4.30s | ✅ |
| `SampleCodeStrategy` | 3.98s | ✅ |
| `SearchStrategyHelpers` | 4.06s | ✅ |
| `SwiftEvolutionStrategy` | 4.61s | ✅ |
| `SwiftOrgStrategy` | 4.67s | ✅ |

All 9 targets exit 0.

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

### 3. `docs/package-import-contract.md` rows all ✅

The Producers table in `docs/package-import-contract.md` shows every Search-arc target with a `✅` mark, meaning the actual production-truth dependencies match the foundation-only allowlist:

- `SearchAPI` — Foundation, EnrichmentModels, LoggingModels, SearchModels, SharedConstants
- `SearchSQLite` — Foundation, SQLite3, ASTIndexer, CorePackageIndexingModels, CoreProtocols, LoggingModels, SearchModels, SearchSchema, SharedConstants
- `SearchSchema` — Foundation, SearchModels
- `SearchStrategyHelpers` — Foundation, SearchModels, SharedConstants
- Each `<X>Strategy` — Foundation, CoreProtocols, LoggingModels, SearchModels, SearchStrategyHelpers, SharedConstants

The `SearchAPI` row's allowed-import list is foundation-only by definition: every entry is either Foundation or a Models-tier / constants-tier seam target. No producer target leaks into the SearchAPI deps.

## Sub-PR shapes recorded by this trace

### Sub-PR A — Whole-Search lift-out

Whole-Search dependency closure (per #901 spec):

```
SearchAPI + SearchModels + SharedConstants + LoggingModels + Resources +
ASTIndexer + EnrichmentModels + CorePackageIndexingModels + CoreProtocols
```

Build green via `bash scripts/check-target-portability.sh SearchAPI` (3.43s).

### Sub-PR B — Per-strategy lift-outs

Six strategy targets, one trace each. Per #901 spec each `<X>Strategy + SearchModels + SharedConstants + LoggingModels` builds green. Verified above for AppleArchive, AppleDocs, HIG, SampleCode, SwiftEvolution, SwiftOrg.

## What this PR ships

- This trace document (`docs/handoff/search-arc-liftout-2026-05-24.md`).
- No code changes. The acceptance criteria were already mechanically green when this trace was captured; the PR's role is to record the evidence + close #901.

## Cross-refs

- Epic [#893](https://github.com/mihaelamj/cupertino/issues/893): producer-backend split.
- Sibling close ceremony: [#907](https://github.com/mihaelamj/cupertino/issues/907) (full epic audit + plan-doc finalisation).
- Pluggability epic [#919](https://github.com/mihaelamj/cupertino/issues/919) (closed by #935 end-to-end TDD proof in PR #996).
- `mihaela-agents/Rules/swift/gof-di-rules.md` rule 5 (standalone-portable packages).
- `mihaela-agents/Rules/swift/per-package-import-contract.md` (the import-contract this trace verifies).
