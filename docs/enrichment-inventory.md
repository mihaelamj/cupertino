# Enrichment Inventory

Everything cupertino layers on top of the raw document and source bytes. Base SQLite stores text; this is the catalogue of derived structure, version metadata, full-text indexes, AST extraction, symbolgraph-derived data, and post-index enrichment passes that turn that text into a queryable knowledge base.

Companion to `docs/architecture/database.md` (the Methods-style per-table reference). This file is the flat checklist: name each add-on, say what it computes, where it lives. For the exhaustive DDL with every column type and index, read the architecture doc.

Schema versions at time of writing: **docs = 18, packages = 5, samples = 4.**

Per-source DB split (#1036): the docs schema is shared by `apple-documentation.db`, `hig.db`, `swift-org.db`, `swift-book.db`, `swift-evolution.db`, `apple-archive.db`. Samples live in `apple-sample-code.db`, packages in `packages.db`. The legacy monolithic `search.db` is no longer built.

---

## Named taxonomy

24 distinct enrichment types, each with its canonical name: 20 stored, 4 query-time. The detailed catalogue (sections A through J below) expands every one. Use these names when referring to an enrichment in code review, commits, or design docs.

| # | Name | What it is | Detail items |
|---|---|---|---|
| 1 | **Lexical Index** | FTS5 full-text tables with porter / unicode61 stemming across every DB | A1-A5 |
| 2 | **Symbol Field Boosting** | symbols denormalized into dedicated FTS fields (`symbols` / `symbol_components`) so they rank above prose; the BM25F weights (5.0 / 1.5) that do the boosting are applied at query time | A6, D19 |
| 3 | **Deployment Floors** | `min_<platform>` columns plus the `availability_source` provenance tag | B7-B8 |
| 4 | **Toolchain Stamping** | `implementation_swift_version` (evolution + swift-book) and `swift_tools_version` (packages) | C9-C10 |
| 5 | **AST Symbol Extraction** | SwiftSyntax walk to symbol rows: 16 kinds, async/throws/public/static flags, signature, attributes, conformances, generics | D11-D17 |
| 6 | **Import Capture** | `import X` statements plus the `@_exported` flag, per file (flat list, not a traversable graph) | D18 |
| 7 | **Identifier Splitting** | acronym-aware CamelCase tokenization (`URLSession` to `URL Session`) | D19 |
| 8 | **Availability Capture** | per-`@available` attribute extraction to `available_attrs_json` | D20 |
| 9 | **Constraint Resolution** | symbolgraph-derived Apple generic constraints (AppleConstraintsKit to `generic_constraints`) plus the constraint passes | E21, F24, F27-F28 |
| 10 | **Constraint Propagation** | parent-to-child generic-constraint inheritance walk (hierarchy pass) | F25 |
| 11 | **Framework Aliasing** | synonyms table routing `bluetooth` to CoreBluetooth, etc. | F23, G32 |
| 12 | **Platform Applicability** | HIG topic-aware NULLing of platforms that do not apply (subtractive, not inferred-positive) | F26 |
| 13 | **Apple-Framework Usage** | which Apple frameworks a package imports (`apple_imports_json`); distinct from #18, which is package-to-package deps | E22, F29 |
| 14 | **Structured Projection** | DocC JSON fields lifted into queryable columns (`docs_structured`) | G30 |
| 15 | **Inheritance Graph** | bidirectional class-inheritance edges (`inheritance` table); conformances live in #5, not here | G31 |
| 16 | **Code Example Extraction** | extracted runnable snippets plus their FTS index | G33 |
| 17 | **Availability Aggregation** | MAX-merge of per-file `@available` floors with the Package.swift / framework floor | G34 |
| 18 | **Dependency Closure** | transitive SwiftPM dependency graph per package (`parents_json`), walked from each seed's Package.swift | G35 |
| 19 | **Acquisition Provenance** | how a doc was fetched (`source_type`: appleJSON / appleWebKit / custom / swiftOrg) | H41 |
| 20 | **Row Bookkeeping** | per-row `content_hash`, `word_count`, `json_data`, plus DB-level schema-version stamps | H36-H40 |

Query-time layer (operates on the stored enrichments above; not stored data, so kept separate). Full detail in `docs/architecture/database.md`:

| # | Name | What it is | Detail items |
|---|---|---|---|
| 21 | **Rank Fusion** | reciprocal rank fusion (RRF, `1/(k+rank)`, k=60) merging per-source ranked lists into one top-N | J44 |
| 22 | **Intent Routing** | query-intent classification that prunes the fetcher set and applies per-source authority weights (apple-docs 3.0, etc.) (#254) | J45 |
| 23 | **Kind-Aware Reranking** | exact-title-peer tiebreak + context-aware kind boosting on the main FTS search path, on top of raw BM25 (#256, #610) | J46 |
| 24 | **AST Boilerplate Demotion** | a shared `ORDER BY` (the "signal-rank" clause) for the 4 AST symbol-query commands that deprioritizes synthesized conformance / operator boilerplate (#177) | J47 |

> **Verification note (2026-05-28).** The 20 stored types were checked against the live per-source DBs (the 4 query-time types are behaviors, not DB rows, and are verified in code). All 20 stored types are present and populated EXCEPT one corpus-dependent caveat: **Framework Aliasing (#11)** requires the `framework` column to carry real framework identifiers (`corebluetooth`, `foundation`). It is wired correctly in code (`registerFrameworkAlias(identifier: framework, …)` then `updateFrameworkSynonyms`), but synonyms only land when the apple-docs corpus is indexed with `--docs-dir` pointed at the `docs/` subdirectory (so `extractFrameworkFromPath` yields the real framework). If `--docs-dir` points one level too high, every row gets `framework = "docs"`, the alias rows degenerate, and the 22 synonyms never attach. Validate with `SELECT SUM(synonyms IS NOT NULL) FROM framework_aliases` after a rebuild.

## Generation & action matrix

For each enrichment: whether `cupertino save` produces it automatically, the prep action it needs (only two do), the **generated file** (the concrete `.db` / sidecar artifact written), the **input file** it reads (if any), and the **columns / tables** it adds. Only **Constraint Resolution** (#9, needs `apple-constraints.json`) and **package availability** (#3 / #4 / #17, need `--annotate-availability`) require a prep action; everything else is automatic in `save`. The query-time types (#21-24) generate no file and add no column (they run at search time over the stored enrichments). The docs `.db` set is `apple-documentation.db` / `hig.db` / `swift-org.db` / `swift-book.db` / `swift-evolution.db` / `apple-archive.db`; samples is `apple-sample-code.db`; packages is `packages.db`.

| # | Enrichment | Auto in `save`? | Prep action needed | Generated file | Reads (input file) | Columns / tables it adds |
|---|---|---|---|---|---|---|
| 1 | Lexical Index (FTS5) | Yes | none | all 8 `.db` | none | FTS tables `docs_fts`, `doc_code_fts`, `doc_symbols_fts`, `sample_code_fts`, `projects_fts`, `files_fts`, `file_symbols_fts`, `package_files_fts` |
| 2 | Symbol Field Boosting | Yes | none | docs `.db`, `apple-sample-code.db`, `packages.db` | none | FTS cols `symbols`, `symbol_components` (BM25F 5.0 / 1.5 applied at query) |
| 3 | Deployment Floors | docs: yes; packages: only once annotated | packages: `cupertino fetch --source packages --annotate-availability --skip-archives` | all 8 `.db` | packages: `availability.json` | `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos` + `availability_source` on `docs_metadata`, `sample_code_metadata`, `projects`, `package_metadata` |
| 4 | Toolchain Stamping | Yes (`Package.swift` fallback) | packages: `--annotate-availability` for an accurate value | `swift-evolution.db`, `swift-book.db`, `packages.db` | packages: `availability.json` (else `Package.swift` line 1) | `implementation_swift_version` (docs), `swift_tools_version` (packages) |
| 5 | AST Symbol Extraction | Yes | none | docs `.db`, `apple-sample-code.db`, `packages.db` | none | tables `doc_symbols` / `file_symbols` / `package_symbols`; cols: 16 `kind`s, `is_async`, `is_throws`, `is_public`, `is_static`, `signature`, `attributes`, `conformances`, `generic_params` |
| 6 | Import Capture | Yes | none | docs `.db`, `apple-sample-code.db`, `packages.db` | none | tables `doc_imports` / `file_imports` / `package_imports` (+ `is_exported`) |
| 7 | Identifier Splitting | Yes | none | docs `.db`, `apple-sample-code.db`, `packages.db` | none | col `symbol_components` |
| 8 | Availability Capture | Yes | none | `apple-sample-code.db`, `packages.db` | none | col `available_attrs_json` (samples `files`, packages `package_files`) |
| 9 | Constraint Resolution | pass is automatic; the **input is a prerequisite** | generate `apple-constraints.json` (AppleConstraintsKit from cupertino-symbolgraphs); #1072 guard hard-fails if absent (unless `--allow-degraded-enrichment`) | `apple-documentation.db`, `apple-sample-code.db`, `packages.db` | `apple-constraints.json` | col `generic_constraints` on `doc_symbols` (docs), `file_symbols` (samples), `package_symbols` (packages) |
| 10 | Constraint Propagation | Yes (rides on #9) | none | `apple-documentation.db` | none | `generic_constraints` (parent→child propagated rows) |
| 11 | Framework Aliasing | Yes (needs correct `--docs-dir`, see note above) | none | `apple-documentation.db` | none | table `framework_aliases` (`identifier`, `import_name`, `display_name`, `synonyms`) |
| 12 | Platform Applicability | Yes | none | `hig.db` | none | NULLs `min_<platform>` columns on HIG-topic rows (subtractive) |
| 13 | Apple-Framework Usage | Yes | none | `packages.db` | none | col `package_metadata.apple_imports_json` |
| 14 | Structured Projection | Yes | none | docs `.db` | none | table `docs_structured` (`declaration`, `abstract`, `overview`, `module`, `platforms`, `conforms_to`, `inherited_by`, `conforming_types`, `attributes`) |
| 15 | Inheritance Graph | Yes | none | `apple-documentation.db` | none | table `inheritance` (`parent_uri`, `child_uri`) |
| 16 | Code Example Extraction | Yes | none | docs `.db` | none | table `doc_code_examples` + FTS `doc_code_fts` |
| 17 | Availability Aggregation | Yes | packages / samples: `--annotate-availability` | `availability.json` sidecars (per-sample / per-package), then `apple-sample-code.db`, `packages.db` | per-file `@available` (in-DB) + `Package.swift` floor | MAX-merged `min_<platform>` + `availability_source` tagged `sample-available-aggregated` / `package-available-aggregated` |
| 18 | Dependency Closure | Yes (needs `Package.resolved` in corpus) | none | `packages.db` | `Package.swift` / `Package.resolved` (corpus) | col `package_metadata.parents_json` |
| 19 | Acquisition Provenance | Yes | none | all 8 `.db` | none | col `source_type` (`appleJSON` / `appleWebKit` / `custom` / `swiftOrg`) |
| 20 | Row Bookkeeping | Yes | none | all 8 `.db` | none | cols `content_hash`, `word_count`, `json_data`, `kind`; table `samples_schema_version`; `PRAGMA user_version` stamps |
| 21 | Rank Fusion (RRF) | Yes (query-time) | none | none | none | none, fuses stored per-source ranks |
| 22 | Intent Routing | Yes (query-time) | none | none | none | none, prunes fetchers, applies authority weights (#254) |
| 23 | Kind-Aware Reranking | Yes (query-time) | none | none | none | none, post-fusion reranking (#256 / #610) |
| 24 | AST Boilerplate Demotion | Yes (query-time) | none | none | none | none, signal-rank `ORDER BY` on 4 AST commands (#177) |

---

## A. Full-text search layer (FTS5)

Base SQLite has no full-text search. Cupertino adds FTS5 virtual tables per DB.

1. **`docs_fts`** (docs DBs): `porter unicode61` stemming over `uri, source, framework, language, title, content, summary, symbols, symbol_components`.
2. **`doc_code_fts`**: `unicode61` over extracted code snippets.
3. **`doc_symbols_fts`**: over `name, signature, attributes, conformances`.
4. **`sample_code_fts` / `projects_fts` / `files_fts` / `file_symbols_fts`** (samples DB).
5. **`package_files_fts`** (packages DB): with `UNINDEXED` projection columns so `owner / repo / module / relpath / kind` survive SELECT without inflating the index.
6. **BM25F weighting**: `symbols` column weighted 5.0, `symbol_components` weighted 1.5. Custom rank tuning so exact-symbol matches dominate.

## B. Platform-availability enrichment (version floors)

Per-row minimum-deployment-version stamping that the raw docs do not carry as queryable columns.

7. **`min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos`**: on `docs_metadata`, `sample_code_metadata`, `projects`, `package_metadata`, each with its own index.
8. **`availability_source`**: provenance tag for the stamp. Observed values: `api`, `swift-version`, `framework-inferred`, `hig-topic-inferred`, `universal-swift`, `swift-book-chapter`, `swift-org-universal`, `swift-org-linux-server`, `sample-swift`, `sample-available-aggregated`, `sample-framework-inferred`, `package-swift`, `package-available-aggregated`.

These are minimum-deployment floors. There is no separate max-version column. Deprecation/obsoletion is captured through `@available` attributes (see D), not a max-version field.

## C. Swift-toolchain version tracking

9. **`implementation_swift_version`** (docs): the Swift version a swift-evolution proposal landed in, parsed from the proposal markdown (#225 Part B). Extended to swift-book chapters (#1103): the concurrency chapter stamps 5.5, macros stamps 5.9.
10. **`swift_tools_version`** (packages): the `// swift-tools-version:` floor parsed from `Package.swift` line 1 (#225 Part A, SE-0152 contract).

## D. AST-extracted symbol data (SwiftSyntax)

Raw Swift source becomes structured symbol rows in `doc_symbols` / `file_symbols` / `package_symbols`, via a SwiftSyntax AST walk (not regex). Lives in `Packages/Sources/ASTIndexer/`.

11. **Symbol kinds (16)**: class, struct, enum, actor, protocol, extension, function, method, initializer, property, subscript, typealias, associatedtype, case, operator, macro.
12. **Per-symbol flags**: `is_async`, `is_throws`, `is_public`, `is_static`.
13. **`signature`**: the full declaration string.
14. **`attributes`**: Swift attributes such as `@MainActor`, `@Sendable`, `@Observable`, `@available`.
15. **`conformances`**: protocols and superclasses.
16. **`generic_params`**: type-parameter names.
17. **`generic_constraints`**: `T: Collection` form, including where-clause constraints parsed from the declaration (#755).
18. **`doc_imports` / `file_imports` / `package_imports`**: `import X` statements with an `is_exported` flag for `@_exported import`.
19. **`symbols`** (denormalized comma list onto the FTS row) plus **`symbol_components`**: acronym-aware CamelCase splitting (`URLSession` to `URL Session`, `LazyVGrid` to `Lazy VGrid Grid`) so Swift identifiers are recallable by token. Splitter at `Search.Index.CamelCaseSplitter.swift`; min length 3, short fragments merged forward, no stopword list.
20. **`@available` attribute extraction** (`AvailabilityParsers.extractAvailability`): every `@available(...)` occurrence with line, raw text, and platform list. Multi-line attributes captured correctly via the AST walk. Persisted per-file as `available_attrs_json` (samples `files`, packages `package_files`).

## E. Symbolgraph-derived constraints (cupertino-symbolgraphs)

> Input pipeline (how the corpus is generated, where `apple-constraints.json` comes from, and where each artifact lives): [symbolgraph-corpus.md](symbolgraph-corpus.md).

21. **`AppleConstraintsKit`**: parses `swift symbolgraph-extract` JSON from the **cupertino-symbolgraphs** corpus repo (for example the SwiftUI graph, hundreds of MB) into a filtered constraint table. Maps symbolgraph identity to an `apple-docs://` URI, keeps `conformance` and `superclass` constraints, drops `sameType` and layout requirements. Output is `apple-constraints.json`: measured at **61,040 entries, ~10.5 MB** on disk, consumed by the constraints enrichment pass. Verified landing real symbolgraph-only constraints into the DBs (e.g. SwiftUI `View` conformances that the DocC markdown never spells out).
22. **`AppleSymbolGraphsKit.FrameworkModuleMap`**: the set of valid Apple module names (per design notes, on the order of a couple hundred), used by the packages apple-imports pass to recognise which imports are Apple frameworks.

## F. Enrichment passes (post-index derivations)

`EnrichmentPass` protocol: each pass has a stable `identifier`, a `schemaVersion` tracked per-row in an `enrichment_version` column, a `dependsOn` list for topological ordering, and a `target` DB. Idempotent. The 3 docs passes register directly; the 4 source/DB-specific passes register through the pluggable `provider.makeSourceSpecificEnrichmentPasses` seam so adding a source does not edit the runner.

23. **`synonyms`** (docs): hand-curated framework alias table (22 pairs, for example `bluetooth` to CoreBluetooth, `nfc` to CoreNFC, `ml` to CoreML) so natural-language queries route to the right framework.
24. **`constraints`** (docs): writes the authoritative Apple-type `generic_constraints` to `doc_symbols`, matching both exact URIs and Apple's hash-disambiguated overload form (`init(_:content:)-7l1jb`). Source is the AppleConstraintsKit table.
25. **`hierarchy`** (docs, depends on `constraints`): propagates parent-symbol generic constraints down to child methods that reuse the same placeholder without re-declaring it.
26. **`hig-platforms`** (docs, via HIGSource): HIG topic-aware platform inference. For pages whose URI declares a platform (`designing-for-watchos`, `spatial-layout`, `carplay`, etc.) it NULLs the inapplicable `min_<platform>` columns so platform filters exclude them.
27. **`samples-apple-constraints`** (samples): writes the Apple-type constraint table into `file_symbols.generic_constraints`.
28. **`packages-apple-constraints`** (packages): writes the Apple-type constraint table into `package_symbols.generic_constraints`.
29. **`packages-apple-imports`** (packages): populates `package_metadata.apple_imports_json`, the set of Apple frameworks a package imports, by matching `package_imports.module_name` against the Apple module set.

## G. Structured-doc and relationship extraction

30. **`docs_structured`**: DocC JSON fields lifted into queryable columns: `declaration, abstract, overview, module, platforms, conforms_to, inherited_by, conforming_types, attributes`.
31. **`inheritance`** table (docs): class-inheritance edges (`parent_uri`, `child_uri`) extracted from DocC `relationshipsSections`, indexed in both directions for O(1) ancestor and descendant walks (#274).
32. **`framework_aliases`** table: identifier to import_name to display_name, plus a `synonyms` column.
33. **`doc_code_examples`** table: code snippets extracted per documentation page, plus the `doc_code_fts` index over them.
34. **Per-sample / per-package `availability.json` sidecars** plus **`@available` MAX-merge aggregation** (#1111, #1114): per-file `@available` floors aggregated to a project or package level and MAX-merged with the `Package.swift` deployment-target floor. The higher floor wins; the row is tagged `sample-available-aggregated` / `package-available-aggregated` when the aggregated value dominates.
35. **`parents_json`** (packages): the transitive SwiftPM dependency closure per package, walked from each seed's `Package.swift` by the dependency resolver. Stored as a Codable `[ResolvedPackage]` JSON array (e.g. `["apple/swift-homomorphic-encryption"]`). Populated for 184/184 priority packages in the current corpus.

## H. Bookkeeping and integrity

36. **`content_hash`**: change detection so re-indexing skips unchanged pages.
37. **`word_count`**: token count per page.
38. **`json_data`**: the full DocC JSON blob preserved, so undocumented fields survive for future extraction.
39. **`kind`**: page/symbol kind taxonomy used by kind-aware ranking.
40. **`samples_schema_version`** table: per-pipeline schema-version stamp so the Sample.Index and Search.Index pipelines can coexist in one SQLite file without trampling `PRAGMA user_version`.
41. **`source_type`**: acquisition-method provenance (`appleJSON` for JSON-API-fetched pages, `appleWebKit` for WebKit-crawled pages, `custom`, `swiftOrg`). Lets a query distinguish how a page entered the corpus. Measured distribution in apple-documentation.db: ~222k appleJSON, ~132k appleWebKit, ~580 custom, ~199 swiftOrg.
42. **Schema-version migrations**: versioned `ALTER TABLE` / rebuild ladders (docs at 18, packages at 5, samples at 4).

## I. Opt-in / dormant (present but not populated by default)

43. **`stars`** + **`is_apple_official`** (packages): GitHub popularity + Apple-maintained flag. Populated only when `cupertino fetch --source packages --refresh-metadata` runs the Swift Package Index metadata stage (off by default post-#1108). Zero-populated in a default archives-only fetch.

## J. Query-time ranking layer

Base SQLite FTS5 gives you a single BM25 score per table. Cupertino adds a ranking layer on top of that, at query time. These are not stored columns; they operate on the stored enrichments above. The Methods-level treatment is in `docs/architecture/database.md`; named here for completeness.

44. **Rank Fusion (RRF)**: `SmartQuery` runs each per-source fetcher concurrently and merges their ranked lists via reciprocal rank fusion, `1/(k + rank)` with `k = 60` (Cormack et al. default). Fetchers produce scores on incompatible scales (inverted BM25, normalized prose scores); ranking each locally then fusing on rank position gives a robust combined ordering.
45. **Intent Routing (#254)**: classifies the query's intent (for example a bare type-name like `URLSession` versus a prose phrase), prunes the fetcher set accordingly, and applies per-source authority weights so a prose-heavy source's rank-1 result does not fuse ahead of the canonical API page. Apple-docs carries the highest authority weight (3.0).
46. **Kind-Aware Reranking (#256, #610)**: post-fusion heuristics on the main FTS search path. Exact-title peers are tiebroken by symbol kind; context-aware kind boosting surfaces the canonical declaration over incidental mentions. Layered on top of the raw BM25 + RRF score.
47. **AST Boilerplate Demotion (#177)**: a separate query surface. The 4 AST symbol-query commands (`searchSymbols`, `searchPropertyWrappers`, `searchConcurrencyPatterns`, `searchConformances`) share a "signal-rank" `ORDER BY` clause that deprioritizes (does not exclude) auto-synthesized `Equatable` / `Hashable` / `Comparable` conformance members and operator overloads, which a flat `ORDER BY name` surfaced ahead of canonical type pages.

---

## Source map

| Area | Target / file |
|---|---|
| Schema DDL (docs) | `Packages/Sources/SearchSchema/Search.Schema.CreateAllTablesSQL.swift` |
| Schema version (docs) | `Packages/Sources/SearchSchema/Search.Schema.CurrentVersion.swift` (18) |
| Migrations (docs) | `Packages/Sources/SearchSQLite/Search.Index.Migrations.swift` |
| Schema + migrations (packages) | `Packages/Sources/SearchSQLite/PackageIndex.swift` (5) |
| Schema + migrations (samples) | `Packages/Sources/SampleIndexSQLite/Sample.Index.Database.swift` (4) |
| AST extraction | `Packages/Sources/ASTIndexer/ASTIndexer.Extractor.swift`, `ASTIndexer.AvailabilityParsers.swift` |
| CamelCase splitter | `Packages/Sources/SearchSQLite/Search.Index.CamelCaseSplitter.swift` |
| Symbolgraph constraints | `Packages/Sources/AppleConstraintsKit/` |
| Enrichment protocol + runner | `Packages/Sources/EnrichmentModels/`, `Packages/Sources/Enrichment/Enrichment.LiveRunner.swift` |
| Enrichment passes | `Packages/Sources/{Synonyms,AppleConstraints,Hierarchy,HIGPlatformInference,SamplesAppleConstraints,PackagesAppleConstraints,PackagesAppleImports}Pass/` |
| Pass registration | `Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift` (docs ~525, packages ~938, samples ~1142) |
