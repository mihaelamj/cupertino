# Epic #893 closing audit, 2026-05-24

Mechanical closing audit for [#893](https://github.com/mihaelamj/cupertino/issues/893) (producer-backend split epic). Per #907 acceptance criteria.

This audit records the end-state evidence so #893 can close with a documented baseline. The audit is paired with `docs/plans/2026-05-12-v1-1-package-split.md`'s closing markers (sub-PR B of #907) and the epic-close comment on #893 itself (sub-PR C of #907).

## Acceptance evidence

### 1. Every producer in `STRICT_PRODUCERS` passes `scripts/check-target-portability.sh`

`STRICT_PRODUCERS` array in `scripts/check-target-foundation-only.sh` enumerates 47 producer targets. Each was lifted into a generated minimal `Package.swift` containing only the target + its transitive closure, then `swift build` was run. All 47 exit 0.

| # | Target | Build time |
|---|---|---|
| 1 | `AppleArchiveStrategy` | 4.15s |
| 2 | `AppleConstraintsKit` | 4.25s |
| 3 | `AppleConstraintsPass` | 3.85s |
| 4 | `AppleDocsStrategy` | 4.37s |
| 5 | `Availability` | 3.61s |
| 6 | `Cleanup` | 2.84s |
| 7 | `CleanupModels` | 3.48s |
| 8 | `Core` | 12.26s |
| 9 | `CoreJSONParser` | 4.30s |
| 10 | `CorePackageIndexing` | 12.26s |
| 11 | `CorePackageIndexingModels` | 11.31s |
| 12 | `CoreProtocols` | 3.50s |
| 13 | `CoreSampleCode` | 5.58s |
| 14 | `CoreSampleCodeModels` | 3.99s |
| 15 | `Crawler` | 12.84s |
| 16 | `CrawlerModels` | 3.76s |
| 17 | `CrawlerWebKit` | 6.19s |
| 18 | `Distribution` | 4.41s |
| 19 | `DistributionModels` | 3.57s |
| 20 | `Enrichment` | 12.08s |
| 21 | `EnrichmentModels` | 2.14s |
| 22 | `HIGStrategy` | 4.13s |
| 23 | `HierarchyPass` | 3.83s |
| 24 | `Indexer` | 12.01s |
| 25 | `IndexerModels` | 2.24s |
| 26 | `Ingest` | 3.88s |
| 27 | `Logging` | 2.57s |
| 28 | `MCPSupport` | 4.25s |
| 29 | `PackagesAppleConstraintsPass` | 4.01s |
| 30 | `PackagesAppleImportsPass` | 3.71s |
| 31 | `RemoteSync` | 4.12s |
| 32 | `RemoteSyncModels` | 3.50s |
| 33 | `SampleCodeStrategy` | 4.29s |
| 34 | `SampleIndex` | 12.86s |
| 35 | `SampleIndexModels` | 12.05s |
| 36 | `SampleIndexSQLite` | 12.07s |
| 37 | `SamplesAppleConstraintsPass` | 13.50s |
| 38 | `SearchAPI` | 4.48s |
| 39 | `SearchModels` | 5.08s |
| 40 | `SearchSQLite` | 16.15s |
| 41 | `SearchSchema` | 4.02s |
| 42 | `SearchToolProvider` | 14.21s |
| 43 | `Services` | 12.56s |
| 44 | `ServicesModels` | 11.97s |
| 45 | `SwiftEvolutionStrategy` | 4.46s |
| 46 | `SwiftOrgStrategy` | 4.43s |
| 47 | `SynonymsPass` | 4.16s |

47/47 green. No producer in `STRICT_PRODUCERS` fails the standalone-portability lift-out.

### 2. `grep '^import SQLite3' Packages/Sources/`

```
Packages/Sources/SearchSQLite/*.swift           (19 files; the docs/packages index concrete)
Packages/Sources/SampleIndexSQLite/Sample.Index.Database.swift  (samples concrete)
Packages/Sources/Diagnostics/Diagnostics.Probes.swift           (read-only sqlite3 probes for `cupertino doctor`)
Packages/Sources/ReleaseTool/Release.Publishing.swift           (publishing-side release-DB writer)
```

4 distinct producer / tool targets. #907 spec originally expected the 4th holder to be `Shared.Utils.SQL`; in practice the SQLite3 import landed in `ReleaseTool` (an `executableTarget` for release-time bundle publishing) rather than `Shared/Utils/Shared.Utils.SQL.swift` (which contains only FTS-query helpers and does not import SQLite3). The spec drift is documented here so the next mechanical audit doesn't re-discover it as a new finding.

### 3. `grep '^import WebKit' Packages/Sources/`

```
Packages/Sources/CrawlerWebKit/Crawler.WebKit.Engine.swift
Packages/Sources/CrawlerWebKit/Crawler.WebKit.ContentFetcher.swift
Packages/Sources/CoreSampleCodeWebKit/Sample.Core.Downloader.swift
Packages/Sources/CoreJSONParserWebKit/Core.JSONParser.WKWebViewTitleFetcher.swift
```

3 distinct WebKit-companion siblings, matching the #895 / #903 / #904 decision (each WebKit-backed concrete lives in a `<Parent>WebKit` sibling carved out of its parent producer). Zero hits in any non-`*WebKit` target. Producer parents (`Crawler`, `CoreSampleCode`, `CoreJSONParser`, `Core`) are all WebKit-free post-extraction.

### 4. `grep '^import FoundationNetworking' Packages/Sources/`

```
Packages/Sources/AvailabilityFoundationNetworking/LiveAvailabilityNetworking.swift
```

1 sibling target. Matches the #905 decision (the FoundationNetworking-backed concrete for `Availability` lives in `AvailabilityFoundationNetworking`).

### 5. Final test suite cite

Run `swift test --package-path Packages` against develop @ commit 835b621 (post-#997 squash). The numbers below come from the most recent CI run on the merged PR.

- Tests: 2490 pass / 0 fail
- Suites: 373 pass / 0 fail
- All 3 #919 audit-invariant tests pass (`Issue919AuditInvariantTests`): STRICT_PRODUCERS=47, FORBIDDEN_MODULES contains SearchAPI + SearchSQLite, GRANDFATHERED_TARGETS=().
- `scripts/check-package-purity.sh` exit 0.
- `scripts/check-target-foundation-only.sh` exit 0.
- `scripts/check-docs-commands-drift.sh` exit 0.
- `scripts/check-canonical-literals.sh` exit 0.
- `scripts/check-issue-body-staleness.sh` exit 0 (97 issues scanned, no Search/SearchAPI false positives).

## Counts at epic close

| Metric | Pre-epic | End-state |
|---|---|---|
| Producer targets in `STRICT_PRODUCERS` | 31 (pre-#893) | 47 |
| `*Models` protocol-seam companions | 7 | 13 |
| Targets carrying `import SQLite3` | 2 (`Search`, `SampleIndex`) | 2 producers (`SearchSQLite`, `SampleIndexSQLite`) + 2 tools (`Diagnostics`, `ReleaseTool`) |
| Targets carrying `import WebKit` | 4 producer concretes embedded in their parent | 3 `*WebKit` siblings; zero hits in any producer parent |
| Targets carrying `import FoundationNetworking` | 1 embedded in `Availability` | 1 sibling (`AvailabilityFoundationNetworking`); `Availability` is foundation-only |
| Targets carrying `import Search` (pre-#900) / `import SearchAPI` (post-#900) | n/a | rename done; orchestration target name is `SearchAPI` |
| Search dissection sub-targets | 1 monolithic `Search` target | `SearchAPI` + `SearchSQLite` + `SearchSchema` + `SearchStrategyHelpers` + 6 `<X>Strategy` (10 total) |
| Search arc lift-out traces captured | 0 | 10 (`docs/handoff/search-arc-liftout-2026-05-24.md`) |

## Child-issue close trace

Every #893 child issue is closed (verified via `gh issue list --search 'parent:893'`):

- #895 (hygiene PR refresh): closed
- #896 (Search dissection plan refresh): closed
- #897 (SearchModels seam companion lift): closed
- #898 (Search dissection arc, sub-PRs A + E + F): closed
- #899 (per-strategy SearchStrategies split): closed
- #900 (SearchQuery extraction + rename residue → SearchAPI): closed (sub-PR B only; sub-PR A deferred)
- #901 (Search arc lift-out traces): closed by PR #999 (squash bed07ea, 2026-05-24)
- #902 (SampleIndex dissection): closed
- #903 (Crawler WebKit extraction): closed
- #904 (Core / CoreJSONParser / CoreSampleCode WebKit extraction): closed
- #905 (Availability FoundationNetworking extraction): closed
- #906 (per-pass Enrichment split): closed
- #907 (this closing audit): closes when the audit PR merges

## Cross-refs

- Epic [#893](https://github.com/mihaelamj/cupertino/issues/893): producer-backend split.
- Plan doc: `docs/plans/2026-05-12-v1-1-package-split.md` (closing markers landed in the same PR).
- Pluggability epic [#919](https://github.com/mihaelamj/cupertino/issues/919): closed by PR #941 (#935 end-to-end TDD proof).
- Search-arc lift-out trace: `docs/handoff/search-arc-liftout-2026-05-24.md`.
- Canonical roadmap [#183](https://github.com/mihaelamj/cupertino/issues/183): v1.3.x section updated when this PR merges (sub-PR C).
- `mihaela-agents/Rules/swift/gof-di-rules.md` rules 5 + 8.
- `mihaela-agents/Rules/swift/per-package-import-contract.md`.
