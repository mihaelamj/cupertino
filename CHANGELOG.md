## Unreleased: v1.0.3

_First v1.0.x release to ship a re-indexed bundle. `databaseVersion` jumps from `1.0.0` to `1.0.3`: `cupertino setup` from a v1.0.3 binary downloads a freshly-built `cupertino-databases-v1.0.3.zip` produced by running the post-#283 indexer against the full 404,729-page corpus (Studio v1.0.0 base + Claw fresh overlay). The previous v1.0.0 / v1.0.1 bundles carried 61,257 case-axis duplicate clusters covering 122,522 rows (~30% of `docs_metadata`); the v1.0.3 bundle has zero (`GROUP BY LOWER(url) HAVING COUNT > 1` returns empty across 277,640 documents). We skip the v1.0.2 tag entirely and ship v1.0.3 directly because the version bump is what triggers the new bundle download via `cupertino setup` / `cupertino doctor` stale-DB detection; v1.0.2's work (post-redirect canonicalization #277, HTML link augmentation #203) folds in here. Upgrade path for existing v1.0.0 / v1.0.1 installs: run `cupertino setup` to fetch the new clean bundle. v12 DBs on disk are rejected at open time with a "rebuild required" message pointing at `cupertino setup`; the in-place v12→v13 migration code remains in the source tree as a developer test tool (60+ min on a 405k-row corpus on M-series, vs seconds for a fresh-bundle download) and never auto-runs._

_On #199: empirical investigation against the post-merge corpus shows `id` is deterministic on 90.5 % of overlapping page pairs and `canonicalContentHash` is deterministic across the JSON save+load round trip (new test landed in 128b79b). The remaining ~10 % `id` mismatch correlates with cross-mode pairs where the two transformers populate different structural fields — by-design, not a bug. The "every re-fetch falsely reports as updated" symptom that motivated #199 is explained by stale metadata.json after `--start-clean` plus 0.9.1-binary-saved files using the older hash format, not by hash non-determinism. Detailed write-up in `mihaela-blog-ideas/cupertino/research/2026-05-09-dual-corpus-coverage-investigation.md`._

### Fixed

- **URL case canonicalization: case-variant URLs no longer produce two distinct URIs in the index** ([#283](https://github.com/mihaelamj/cupertino/issues/283), reopens [#200](https://github.com/mihaelamj/cupertino/issues/200)): the v1.0.1 closure of #200 claimed the shipped v1.0.0 `search.db` had "zero case-axis duplicate pairs" based on `GROUP BY LOWER(uri) HAVING variants > 1` returning empty against `docs_metadata`. That query was structurally incapable of finding the bug. `URLUtilities.filename(from:)` builds the URI's 8-hex disambiguator hash from the URL passed in *before* lowercasing (line 895, `originalCleaned`), so two URLs differing only in case (e.g. `documentation/Swift/withTaskGroup(of:returning:isolation:body:)` vs the all-lowercase variant) produce two distinct hash suffixes, two distinct filenames, two distinct URIs in `docs_metadata`. The lowered URIs are also distinct, so `LOWER(uri)` cannot see the duplicate; the correct query is `GROUP BY LOWER(url)` against `docs_structured`, which against the shipped v1.0.0 corpus reports `61,257 clusters / 122,522 rows` (~30% of the corpus). Live-reproduced in v1.0.1 binary on `cupertino search --source apple-docs "withTaskGroup"` and `"Observable() macro"`: top results show capital + lowercase URL variants of the same Apple page. Fix: `URLUtilities.filename(from:)` now calls `URLUtilities.normalize(_:)` on the input URL before computing both the lowercased body and the disambiguator hash, so case-variant inputs collapse to identical filenames. One-line behavioral change inside the function; all callers continue to pass raw URLs unchanged. Three new regression tests in `URLUtilitiesFilenameTests` (`caseVariantWithTaskGroupCollapses`, `caseVariantObservableMacroCollapses`, `caseVariantPlainURLCollapses`); the existing 10 truncation + determinism tests continue to pass. The fix is preventive going forward; existing v1.0.0 / v1.0.1 bundle DBs still carry the duplicate rows. Same release ships a freshly-reindexed bundle (`cupertino-databases-v1.0.3.zip`): 277,640 documents across 402 frameworks, 2.41 GB, `user_version = 13`, zero case-axis duplicate clusters by the correct query. The reindex took 12h 36m wall-clock on M4 Max against the merged 404,729-page corpus and committed cleanly. Live `cupertino search "withTaskGroup"` and `"Observable() macro"` against the new bundle return ONE canonical lowercase result each, not the case-variant pairs the v1.0.0 bundle returned. v12 DBs hit `checkAndMigrateSchema` and throw "rebuild required" (matches the existing v5 / v12 breaking-migration pattern), pointing users at `cupertino setup` to download the new pre-built bundle. No in-place migration ships: a fresh-bundle download takes seconds vs the 60+ minutes a 405k-row in-place rewrite needed in testing. An earlier draft of this work shipped a full v12→v13 in-place migration with prepared-statement reuse and journal-mode tuning; that code was deleted before v1.0.3 tag because it was dead weight given the bundle download path.
- **`cupertino serve --help` OVERVIEW listed the wrong tool surface** (branch `refactor/searchindex-split-by-concern`): the `discussion:` string in `ServeCommand.swift` rendered for `cupertino serve --help` listed `search_docs` and `search_samples` as MCP tools, both of which were removed in #239 (unified into the single `search` tool). It also omitted the unified `search` tool itself plus the four semantic-search tools added in #81 (`search_symbols`, `search_property_wrappers`, `search_concurrency`, `search_conformances`). So the binary's own help text described a tool surface that hadn't existed for two releases. Spotted while verifying that `docs/tools/` matches `CompositeToolProvider`'s actual `Tool()` registrations — the docs side was correct (10 tool subdirectories matching the 10 registered tools), the binary's `serve --help` text was the part lying. Rewrote the `discussion:` block to match what `CompositeToolProvider` actually registers, organized by the same conditional groups the provider uses (Unified Search / Documentation Tools / Sample Code Tools / Semantic Search Tools). No registration or behavior change; static help-text fix only.
- **Crawler stores pages under post-redirect canonical URL** ([#277](https://github.com/mihaelamj/cupertino/issues/277), [PR #278](https://github.com/mihaelamj/cupertino/pull/278) by [@Vignesh-Thangamariappan](https://github.com/Vignesh-Thangamariappan)): `Crawler.swift` derived on-disk storage paths (`framework`, `filename`) from the *request* URL. When Apple issues a 301/302 — e.g. `professional_video_applications` → `professional-video-applications` — `URLSession` followed it silently, so the content body arrived under the new slug but was filed under the old. After the fix, `ContentFetcher.fetch` returns `FetchResult<RawContent>` carrying the post-redirect `response.url`; both `JSONContentFetcher` (capturing `response.url` from `URLSession.data(from:)`) and `WKWebContentFetcher` (capturing `webView.url` after navigation completes) expose it. `Crawler.loadPageViaJSON` reverses the JSON API URL back to a documentation URL via the new `AppleJSONToMarkdown.documentationURL(from:)` helper and uses that canonical URL for `framework` / `filename` derivation, `shouldRecrawl` keying, and metadata page-key updates. `AppleJSONCrawlerEngine`, `WKWebCrawlerEngine`, and `HIGCrawler` all updated to consume the new `FetchResult.url` field. 5 regression tests cover the helper (round-trip with `jsonAPIURL(from:)`, nil for non-API URLs, the underscore→dash slug migration) plus a `RedirectMockURLProtocol`-driven integration test confirming `JSONContentFetcher` captures the post-redirect URL when a 301 is in the response chain.

### Added

- **`--discovery-mode auto` augments JSON-extracted links with HTML anchor tags on sparse-references pages** ([#203](https://github.com/mihaelamj/cupertino/issues/203), [PR #281](https://github.com/mihaelamj/cupertino/pull/281), supersedes [PR #279](https://github.com/mihaelamj/cupertino/pull/279) which had matching design intent but lacked the heuristic): in `--discovery-mode auto`, after a successful JSON API fetch, the crawler additionally fetches the rendered HTML and unions its `<a href>` links with the JSON `references`-walker output. Catches URL patterns Apple's DocC JSON omits — operator overloads (`Int.&` slugified as `int_amp_<hash>`), legacy numeric-ID symbols (`NSDictionary 1418511-iskindofclass`), `data.dictionary` REST sub-paths. The cost of the extra WebView render is bounded by a sparse-references skip heuristic: augmentation only runs when the JSON-extracted link count is below `htmlLinkAugmentationMaxRefs` (default `10`). Pages with rich JSON references already cover the URL graph; HTML adds nothing for them. This puts roughly the sparse third of Apple's corpus through augmentation, matching the issue's stated performance budget ("Performance budget: HTML fetch already happens for ~11 % of pages... extending to ~30-50 % would slow per-page rate ~1.5-2x. Acceptable for completeness."). The augmentation HTML fetch uses the post-redirect canonical URL captured by #277's `storageURL` plumbing, so a redirected slug doesn't double-fetch. Two new `CrawlerConfiguration` config-file fields (no CLI flags yet — set in your config JSON):
  - `htmlLinkAugmentation: Bool` — master switch (default `true`).
  - `htmlLinkAugmentationMaxRefs: Int` — heuristic threshold (default `10`). Set to `Int.max` to disable the heuristic and augment every page; set `htmlLinkAugmentation: false` to skip entirely.
  
  When augmentation runs and adds at least one link, the crawler logs `🔗 HTML augmentation: +N links (page had M JSON refs)`. Backwards-compatible JSON config decoding via `decodeIfPresent` for both fields. 7 new tests cover default values, explicit overrides, legacy-JSON decode without the new fields, encode + decode round-trip. Integration testing of the augmentation path itself needs fetcher-mock infrastructure that doesn't exist in the test suite today — deferred to a follow-up.

### Internal

- **Empirical comparison of webview-only vs json-only crawl corpora** (write-up at `mihaela-blog-ideas/cupertino/research/2026-05-09-dual-corpus-coverage-investigation.md`): two-round investigation against a partial webview-only run + a complete json-only run on the same Apple corpus. Confirmed at scale: webview catches 307 pages JSON misses entirely + 7 frameworks Apple has no JSON endpoint for (`apple_pay_on_the_web`, `applepencil`, `docc`, `passkit_apple_pay_and_wallet`, `root`, `samplecode`, `sign_in_with_apple`). Webview's `rawMarkdown` is on average 1.91× longer per page with 0 / 1000 unresolved `doc://` markers in the sample — vs JSON's 298 / 1000 (29.8 %). New: JSON has a 38 % orphan-reference rate (URLs cited in `references` that don't exist as crawlable pages); webview's URLs resolve to actual files at 81 % vs JSON's 62 %. Field population: webview drops `platforms`, `language`, `module`, `conformsTo`, `inheritedBy`, `conformingTypes`, `codeExamples` entirely; JSON populates them. Page kind classification: webview is 84.8 % `unknown` vs JSON's 33.6 %. Per-framework asymmetry is enormous (Accelerate JSON has 12.5× more pages than partial webview; Contacts is near parity). The right v1.x design merges fields from both rather than picks one mode. Investigation tools at `/tmp/coverage-investigation/`, `/tmp/coverage-investigation-2/` on Studio + Claw.
- **Regression test for canonicalContentHash JSON save+load round-trip** (commit `128b79b` on `fix/199-content-hash-roundtrip-test`): the existing `canonicalContentHashIgnoresVolatileFields` test only covers an in-memory `Page`. The new `canonicalContentHashRoundTripStable` test catches `JSONEncoder` / `JSONDecoder` asymmetry, `Date` precision drift, optional-field encoding inconsistency that would silently break `shouldRecrawl` after a process restart. Both tests pass at v1.0.2.
- **Search package single-file decomposition** (branch `refactor/searchindex-split-by-concern`): `Packages/Sources/Search/SearchIndex.swift` was a 4598-line `Search.Index` actor handling schema + migrations + indexing + search + ranking + counts + helpers in a single file. Split mechanically into a 97-line core file (actor declaration, properties, `init`, `disconnect`, `openDatabase`) plus 12 `SearchIndex+<Concern>.swift` extension files: `+Schema.swift` (createTables, full v12 SQL), `+Migrations.swift` (getSchemaVersion / setSchemaVersion / checkAndMigrateSchema / migrateToVersion3..11), `+Indexing.swift` (indexPackage, indexSampleCode, getFrameworkAvailability, indexCodeExamples, clearDoc{Symbols,Imports}, recomputeSymbolsBlob), `+IndexingDocs.swift` (indexDocument, indexItem(s), extractOptimizedContent, indexStructuredDocument, indexDocSymbols / indexDocSymbolFTS / indexDocImports), `+CodeExamples.swift` (searchCodeExamples / codeExamplesCount / searchSampleCode), `+SearchByAttribute.swift` (searchByKind / searchConformsTo / searchByModule / searchInheritedBy / searchConformingTypes / searchByDeclaration / searchByPlatform / getDocumentJSON), `+QueryParsing.swift` (extractSourcePrefix / extractAttributeFilters / sanitizeFTS5Query), `+Search.swift` (the 730-line `search()` with its multi-pass ranker — BM25F + intent routing + heuristics 1/1.5 + force-include canonical pages + RRF — plus `fetchCanonicalTypePages` / `fetchFrameworkRoot` / `fetchMatchingSymbols` / `searchSymbolsForURIs`), `+SemanticSearch.swift` (searchSymbols / searchPropertyWrappers / searchConcurrencyPatterns / searchConformances), `+CountsAndAliases.swift` (symbolCount / listFrameworks / register-update-resolveFrameworkAlias / listFrameworksWithAliases / documentCount / sampleCodeCount / packageCount), `+ContentAndPackages.swift` (searchPackages / getDocumentContent / getContentFromFTS / clearIndex), `+Helpers.swift` (detectLanguage / extractAvailabilityFromJSON + `ExtractedAvailability` struct / isVersionGreater / bindOptionalText / extractSummary). Function bodies, signatures, schema version, SQL strings, BM25 weights, migration logic — all byte-for-byte unchanged. Public API surface unchanged. 40 declarations widened from `private` to package-internal (3 instance properties, 4 static lets, 2 static funcs, 30 instance methods, 1 helper struct) so cross-file extension methods can share state without exposing anything outside the Search package. Naming follows Swift idiom (`SearchIndex+<Concern>.swift`, matches Foundation's `URL+FilePath.swift`); each file imports only what its concern needs. Verified: 27/27 test targets pass (1258 tests, 143 suites, 0 failures); build clean; swiftlint serious-error count strictly better than `main` on this scope (2 vs 4); swiftformat error count strictly better than `main` on this scope (32 vs 36).
- **Test refactor: `@Suite` normalization across `SearchTests`** (same branch): 7 of 16 `SearchTests` files were inconsistent with the pattern the other 9 used. Three (`CupertinoSearchTests.swift` 26 tests, `PackageIndexTests.swift` 12, `PackageQueryTests.swift` 24) had top-level `@Test` funcs at file scope with no enclosing `struct` — wrapped in `@Suite("...") struct <Name> { ... }` matching the dominant pattern (`BM25TitleWeightingTests`, `VersionFilterTests`, `DocKindTests`, etc.). Four (`CanonicalTypeRankingTests.swift`, `SmartQueryTests.swift`, `ExactTitlePeerTiebreakTests.swift`, `SmartQueryIntentRoutingTests.swift`) already had a `struct` but no `@Suite` annotation — Swift Testing infers the struct as a suite, but the test listing showed the bare struct name; added `@Suite("Description (#issue)")` so the listing carries human-readable names citing the issue numbers being verified. Helpers (`tempDB`, `createTestSearchIndex`, `indexPage`, …) stay at file scope as private free functions, matching every other struct-using file in this target. `@Test` annotation count unchanged at 180 across the target (180 on `main`, 180 post-wrap); SearchTests target reports `184 tests in 22 suites passed` (was 19 suites; +3 from the wraps).
- **Lint cleanup post-refactor** (same branch): the original 4598-line `SearchIndex.swift` had a file-level `// swiftlint:disable type_body_length function_body_length function_parameter_count file_length` directive justified by the file's monolithic size. The mechanical split copied that directive into every extension file, but most of the smaller post-split files don't trigger every disabled rule — swiftlint flagged 60 unused entries as `superfluous_disable_command`. Each extension file's directive trimmed to only the rules that actually fire (computed by re-linting each file with the directive stripped): five files had no firing rules and lost their directive entirely (`+CountsAndAliases`, `+Helpers`, `+Migrations`, `+QueryParsing`, `+SearchByAttribute`); seven files trimmed to a single rule (`+CodeExamples`, `+ContentAndPackages`, `+Schema`, `+SemanticSearch`: `function_body_length`; `+Indexing`: `function_parameter_count`); `+IndexingDocs` kept two rules; `+Search` kept two file-level rules plus the inline `// swiftlint:disable:next cyclomatic_complexity` directive that previously sat above `public func search(` and got stranded in `+QueryParsing.swift` during extraction (it now sits where it belongs, immediately above `search()`). The wrapped `CupertinoSearchTests` struct (555-line body) got a `// swiftlint:disable:next type_body_length` matching the pattern already accepted on `CanonicalTypeRankingTests` (591-line body) and `VersionFilterTests` (340-line body) on `main`. Drive-by: `SearchIndexBuilder.swift` had four pre-existing `redundantInternal` swiftformat errors (`internal func deduplicateDocFilesByCanonicalURL`, `loadStructuredPage`, `canonicalDocumentationURL`, `documentationCrawledAt` — `internal` is the Swift default keyword) that fail `swiftformat --lint` on `main` as well; closed.
- **MCPIntegrationTests fixed (was hanging since 2025-12)** (same branch): `cupertinoServerInitialize` had been the lone test in `MockAIAgentTests` that "started but never finished" — the swift-test bundle exited mid-test with `signal code 13` (SIGPIPE), so no per-test pass / fail line was emitted and the target reported 19 of 20 tests passed with no top-level summary. Three independent root causes diagnosed and fixed. **(1) Path mismatch**: the debug binary at `.build/debug/cupertino` ships with a sibling `cupertino.config.json` that overrides `Shared.BinaryConfig.shared.resolvedBaseDirectory` to `~/.cupertino-dev/` — keeps day-to-day development data away from production `~/.cupertino/`. Integration tests run inside a test bundle where `Bundle.main.executableURL` is the test runner (not cupertino), so `Shared.BinaryConfig.shared` resolves to `~/.cupertino/`. The path mismatch made the test create `samples.db` at `~/.cupertino/samples.db` while the spawned cupertino looked under `~/.cupertino-dev/samples.db`; `ServeCommand.checkForData()` then exited with the welcome-guide message and the test's subsequent stdin write SIGPIPE'd. Fix: new `CupertinoServerFixture` helper saves the dev config aside on init, restores it on cleanup (called via `defer`); also creates an empty samples.db at the production path (matching the schema-init code path `cupertino save --samples` uses) so `checkForData()` returns true. **(2) SIGPIPE on broken pipe**: the test wrote with the non-throwing `fileHandleForWriting.write(_:)`. When cupertino had already exited, that write raised SIGPIPE on the test bundle process and killed it. Fix: switched to `try fileHandleForWriting.write(contentsOf:)` (throwing form, surfaces broken-pipe as a Swift error) plus a `process.isRunning` guard before writing, with stderr capture for the failure record if the server died during startup. **(3) `withThrowingTaskGroup` couldn't actually time out**: the initialize test raced two child tasks — a 5-second sleep that throws `TimeoutError`, and a synchronous `stdoutPipe.fileHandleForReading.availableData` read. `availableData` is a synchronous blocking call with no Swift Concurrency suspension point, so it ignores Task cancellation; if the timeout sleep wins the race, the read task can't be cancelled, and the implicit "wait for child tasks" at the end of `withThrowingTaskGroup` hangs forever. Fix: extracted a `readUntil(stdout:stderr:until:deadline:)` helper that polls `availableData` with 50 ms sleeps in between (every iteration is a real suspension point). The sibling `cupertinoServerListTools` test (which already used a comparable polling pattern inline) also moved to the shared helper. Deadline raised from 5 s to 30 s on the initialize test to match listTools — process fork + DB open can eat several seconds on a busy box. Both tests now pass in under a second; `MockAIAgentTests` reports `Test run with 29 tests in 6 suites passed after 1.309 seconds` (was: 19 passed + 1 hung, no top-level summary). The full 27-target sweep moved from 26 ✅ + 1 unmeasurable / 1229 tests / 137 suites to 27 ✅ / 1258 tests / 143 suites, 0 failures.
- **`docs/commands/` structural drift fix** (same branch, four follow-up commits): a per-command diff of every visible + hidden subcommand's `--help` OPTIONS section against the matching `docs/commands/<cmd>/option (--)/*.md` set found 16 CLI flags with no doc, 2 doc files for flags removed from the binary, 3 enum values missing per-value docs, and 1 enum value with a stale filename. **Authored** 16 new option docs (`fetch/--no-only-accepted`, `save/--remote`, `list-frameworks/--format` + `--search-db`, `list-samples/--format/--framework/--limit/--sample-db`, `read-sample/--format/--sample-db`, `read-sample-file/--format/--sample-db`, `package-search/--db/--limit/--platform/--min-version`) and 3 new enum-value docs (`fetch --type samples`, `search --source samples`, `search --source all`); each new file matches the existing format convention (H1 = flag name, Synopsis, Description, Values table for enums, Default, Examples, Notes). **Deleted** the orphan `fetch/option (--)/recurse.md` and `fetch/option (--)/refresh.md` (flags removed from the binary). **Renamed** `search/option (--)/source (=value)/apple-sample-code.md` → `samples.md` and rewrote the body to describe the samples.db-backed source rather than the prior bundled-catalog story (the CLI's `--source` enum was renamed `apple-sample-code` → `samples` at some earlier point; the doc filename had been left behind). After the pass, the structural-drift detector (`scripts/check-docs-commands-drift.sh`, see below) reports `0 / 0 / 0` across the 14-command, 91-flag CLI surface.
- **`docs/commands/` content audit against `--help` (top-three commands)** (same branch): three parallel agents read every body line of every option `.md` under `fetch` / `search` / `save` (32 + 33 + 22 files) against the current binary's `--help` output. They surfaced **41 concrete drift items across 13 files** — ranging from numeric staleness (`fetch/type/docs.md` and `swift.md` claimed `Max Pages 13,000` while the binary default is `1,000,000`; `setup/README.md` claimed search.db has `22,000+ documentation pages` while the v1.0 corpus has 405,782) to a phantom `--verbose` flag referenced in 4 search docs (the flag isn't in `--help` and never has been), a fabricated `-l` short alias for `search --limit` (`-l` is the short alias for `--language`), `search/option (--)/source.md` listing `apple-sample-code` as a valid value (renamed to `samples`) and missing `samples` + `all` entries, `save/option (--)/clear.md` documenting the default as `true` (it's `false`; `--clear` is opt-in) plus referencing a `--no-clear` flag that doesn't exist (no inversion pair → ArgumentParser doesn't synthesize one), `save/option (--)/default.md` carrying a pre-#231 docs-only worldview (no mention of the `--docs/--packages/--samples/--remote` scope flags or the `--yes` preflight prompt), `save/option (--)/remote/README.md` listing a `packages` phase under `--remote` (which only feeds the docs scope), and `fetch/type/packages.md` referencing a removed `--no-recurse` flag. Every item fixed in commit `c6ab1dd` against the current `--help`. Drive-by: `setup/README.md` "What Gets Downloaded" table updated from the fictional `22k pages / 606 projects / varies` to the v1.0 bundle reality (`~405k pages / ~150-200 MB samples / ~9.7k packages`).
- **`docs/commands/` content audit (small commands + top-level)** (same branch): spot-check pass over `doctor` / `cleanup` / `resolve-refs` / `read` / `setup` / `serve` / `list-frameworks` / `list-samples` / `read-sample` / `read-sample-file` / `package-search` and the top-level `docs/commands/README.md`. Found 4 stale db-filename references — `list-frameworks/README.md` / `list-samples/README.md` / `read-sample/README.md` / `read-sample-file/README.md` documented the database default as `~/.cupertino/search-index.sqlite` or `~/.cupertino/sample-index.sqlite`; neither filename has ever matched the binary's actual default. `Shared.Constants.FileName` uses `search.db` / `samples.db` / `packages.db`. Plus `serve/README.md` had `~/.cupertino/sample-code/samples.db` (wrong path; samples.db lives directly under `~/.cupertino/`). Plus `list-frameworks/README.md` sample output showed `Total: 156 frameworks, 23456 documents` (factor-of-3 and 17× off vs the v1.0 corpus's 261 frameworks / 405k docs). Plus the top-level `docs/commands/README.md` 'Manual Setup' workflow described full-docs crawl as `~50–80k pages, hours` (~5× off; current corpus is ~400k+ pages, multi-hour crawl). All five corrected. Verified clean: no remaining occurrences of `cupertino index` / `cupertino ask` / `--recurse` / `--refresh` / `--verbose` as active references (every mention is correctly framed as historical, e.g. "replaces the removed `cupertino index` command").
- **`docs/commands/` deep audit (verified against source code, not just `--help`)** (same branch): three parallel agents read every body line of the 36 remaining option `.md` files top-to-bottom and cross-checked claims against actual binary output and Swift source code (the JSON formatters in `Services/Formatters/` and `CLI/Commands/`). They surfaced **24 issues across 11 files** — most damning, **my own Phase 1 authorings of 4 `format.md` files invented JSON shapes from `--help` text alone** rather than reading source. `read-sample-file/format.md` claimed JSON fields `{project id, file path, language, byte length, content}` but `FileJSONOutput` actually emits `{projectId, path, filename, content}` (no `language`, no `byteLength`); `read-sample/format.md` claimed YAML front-matter for the markdown format but `outputMarkdown` writes H1 + `## Metadata` bullet block; `list-samples/format.md` claimed JSON top-level was a bare array but `ListSamplesCommand.outputJSON` wraps it as `{totalProjects, totalFiles, framework?, projects}` with `framework` conditional on `--framework` filter; `list-frameworks/format.md` claimed a `count` JSON field but `FrameworksJSONFormatter` emits `documentCount`. jq filter examples in 3 files were broken (would have returned nothing or null on real output). Plus `serve/README.md` documented an MCP tool `search_hig` that's not in `--help` (the binary advertises 7 tools, `search_hig` isn't one), `cleanup/README.md` listed `__MACOSX` as a removed pattern but `SampleCodeCleaner.cleanupPatterns` is the 7-entry list `.git / .DS_Store / DerivedData / build / .build / xcuserdata / *.xcuserstate` (no `__MACOSX`), `doctor/option (--)/search-db.md` was off by **factor of 50** on corpus-size claims (`13,000 pages → ~50 MB` vs actual `~405k pages → ~2.5 GB`), and `doctor/option (--)/default.md` had stale protocol version `2025-06-18` (current `2025-11-25`) plus omitted four sections of the live `doctor` output. Every issue fixed in commit `12cd5fb` and verified live by running `cupertino <cmd> --format json` and reading the actual output shape.
- **`docs/ARCHITECTURE.md` mermaid diagrams + `Search.Index` post-split layout entry**: added one bullet to the existing 'Recent architectural changes (1.0)' list documenting the v1.0.2 SearchIndex decomposition, plus two mermaid diagrams that the doc now hosts (it had one before — the Services package flowchart). First diagram is a `flowchart LR` of `Search.Index` showing the actor at root with the 12 `+<Concern>.swift` extension files as children, each labeled with its top-level methods. Second is a `flowchart TD` of the 730-line `search()` ranker pipeline — query string in, `Search.Result` array out, with stages `extractSourcePrefix → extractAttributeFilters → sanitizeFTS5Query` branching into `searchSymbolsForURIs` (AST fast path) and the FTS5 `bm25(docs_fts, 1, 1, 2, 1, 10, 1, 3, 5)` MATCH (per-column weight vector annotated), merging at `HEURISTIC 1` (exact-title 50× / 20×), `HEURISTIC 1.5` (URI-simplicity + frameworkAuthority tiebreak), `fetchCanonicalTypePages` force-include, `RRF` k=60 weighted by source. Each stage cross-referenced to its issue number (#254 / #256 / #181 / #192 E4) so a reader landing on the diagram can jump to the originating motivation. Companion update: `docs/artifacts/folders/search.db.md` had three references to the monolithic `SearchIndex.swift` for schema definition / heuristic ranker / canonical-type-page boost; redirected each to the new specific extension file (`SearchIndex+Schema.swift` / `SearchIndex+Migrations.swift` / `SearchIndex+Search.swift`). Plus `README.md` package count fixed: pre-existing inconsistency on `main` where `README.md` claimed `9 consolidated packages` while `ARCHITECTURE.md` correctly described `~24 single-responsibility SPM targets` — counting `Package.swift` confirms 24, so README updated to match with a pointer to ARCHITECTURE.md for the full breakdown. README's stale 11-package listing replaced with a 13-line accurate grouping.
- **`scripts/check-docs-commands-drift.sh` added as a forcing function** (same branch): codifies the structural-drift pass as a runnable check so future flag / subcommand / enum-value additions can't silently drift against `docs/commands/`. The script parses `cupertino <cmd> --help`'s OPTIONS section per command (only OPTIONS, not OVERVIEW prose, so flag-shaped strings inside descriptions don't false-positive), enumerates the matching `docs/commands/<cmd>/option (--)/*.md` files, and diffs the two sets per command. Plus enum-value checks for the two enum-valued options that have per-value subdirectories (`fetch --type` and `search --source`) using a hardcoded expected-values list in the script header (parsing ArgumentParser's invalid-enum error message proved too fragile — it intermixes value names with parenthetical descriptions and shredded into single-letter false positives). Exit codes: `0` clean, `1` drift detected, `2` invocation error (binary not built or not on the expected path). Smoke-tested by deleting a known-good doc and confirming the script catches it (`MISSING DOC fetch --force`) and exits 1, then restores cleanly. `CONTRIBUTING.md` gained a 'Documentation' section documenting the doc-update obligation when changing the CLI surface, with an explicit pre-PR checklist invocation of the script. The script catches structural drift only; prose-level claims (default values, JSON output shapes, sample output formatting) still need a human read on changes — the deep-audit pass found that source-code-verified content drift was the bigger category and a script can't substitute for a code-aware audit there.

---

## 1.0.1 — 2026-05-08

_Binary-only bug-fix release on top of v1.0.0 "First Light". `databaseVersion` stays at `1.0.0`: `cupertino setup` from a v1.0.1 binary downloads the same `cupertino-databases-v1.0.0.zip` bundle. The #200 fix is preventive going forward — verified that the shipped v1.0.0 `search.db` has zero case-axis duplicate pairs (a `GROUP BY LOWER(uri) HAVING variants > 1` returned empty across 405,782 docs); Apple's JSON references during the v1.0.0 crawl happened to be uniformly lowercase, so the bug was dodged. Re-index would be ~12 h locally with no observable benefit on the existing corpus; future crawls would have hit the bug and v1.0.1 prevents that going forward. If a refreshed bundle is wanted later, ship as v1.0.1.1._

_Carried over: #199 (contentHash + id non-determinism) deferred to v1.0.2; needs a design pass and is not a bundle-DB concern._

### Fixed

- **`cupertino serve`: stale sibling processes reaped at startup** ([#242](https://github.com/mihaelamj/cupertino/issues/242)): MCP hosts (Claude Desktop, Cursor) launch a fresh server on every config reload but don't always reap the previous one when the host crashes or restarts. On a real dev machine: four orphan `cupertino serve` processes alive simultaneously, the oldest 4+ hours, all holding SQLite read connections, file descriptors, and ~hundreds of MB of warm AST cache each, plus making `cupertino save` more likely to fail with `database is locked`. `ServeCommand.run()` now calls `ServeReaper.reapSiblings()` before binding stdio: resolves own binary via `_NSGetExecutablePath` + `realpath`, lists processes via `ps -ax`, and for each candidate verifies the real binary path matches (so `brew` + dev installs coexist) and that the actual `argv[1]` is exactly `serve` (so a concurrent `cupertino save` is never reaped). argv parsing reads `KERN_PROCARGS2` directly via `sysctl` rather than splitting the joined `ps -o command=` line, because string heuristics anchored on the last `cupertino` substring kept regressing on realistic invocations like `cupertino serve --search-db /tmp/cupertino.db` (the heuristic landed inside the argument value, not on the binary basename). One stderr log line per reap; SIGTERM, 2s grace, SIGKILL fallback. 13 unit tests cover ps-line parsing and `KERN_PROCARGS2` argv parsing, including binary paths with spaces (`/Applications/My Tools/cupertino serve`), directories named `cupertino-*` (`/Volumes/cupertino-build/...`), and arguments containing `cupertino` (`--base-dir ~/.cupertino-dev`).
  - **Pre-release fix in v1.0.1**: `ServeReaper.listProcesses()` was deadlocking on busy machines. The original code called `task.waitUntilExit()` before `pipe.fileHandleForReading.readToEnd()`; on any system where `ps -ax` writes more than the ~64 KB pipe buffer, `ps` blocked on `write()`, the parent blocked on `ps` exiting, and `cupertino serve` hung indefinitely at startup, never binding stdio (so MCP hosts would time out). Caught by the v1.0.1 pre-flight on a machine with five live serve siblings: `MCPIntegrationTests.cupertinoServerInitialize` froze, the spawned `cupertino serve` subprocess sat at 0 % CPU with the main thread parked in `ServeReaper.listProcesses() → -[NSConcreteTask waitUntilExit]`. Fix: drain stdout via `readToEnd()` first (which blocks on EOF, i.e. `ps` closing stdout = `ps` exiting), then `waitUntilExit()` returns immediately as a status confirmation. Verified: the rebuilt binary starts up cleanly with five sibling serves alive on the system.
- **URL canonicalization: case-axis duplicates collapse at index time** ([#200](https://github.com/mihaelamj/cupertino/issues/200), supersedes [#201](https://github.com/mihaelamj/cupertino/pull/201)): the crawler queue, the on-disk corpus, and the search-index save layer now collapse case-axis URL variants. `Crawler` normalizes URLs on session restore, on technology-index seed, and on the start-URL fallback; the in-flight queue check additionally compares against any normalized form of an enqueued URL so case-flip duplicates don't re-enter. `SearchIndexBuilder` gained a `deduplicateDocFilesByCanonicalURL` step that reads each doc's canonical URL out of the saved JSON (decoder configured with `.iso8601`, mirroring `indexStructuredDocument`) and keeps the file with the newest `crawledAt` when two files share a canonical URL after normalization. URI generation prefers the page's own URL (post-normalize) over the file path. Underscore→dash collapse was deliberately **not** added at the URLUtilities layer because at least one Apple framework (`installer_js`) requires the underscore. Verified that `documentation/installer-js` returns 404 from Apple. Locked in by a regression test (`URLUtilities normalize keeps underscores intact`). New test suite `IndexBuilderDeduplicationTests` covers the dedup helper directly: keep-newest-by-`crawledAt`-not-mtime, single-file pass-through, distinct-URLs-both-survive, and `loadStructuredPage` `.iso8601` round-trip. Co-authored with [@imwyvern](https://github.com/imwyvern) (Wesley), whose [#201](https://github.com/mihaelamj/cupertino/pull/201) supplied the crawler queue dedup, dedup helper, URI alignment, and case-axis tests. The fix runs at index time. v1.0.1 ships without a re-index (see release header above): the bundled v1.0.0 `search.db` happened to dodge the bug entirely (zero observable case-axis duplicate pairs), so re-indexing would have no measurable effect on the existing corpus. The fix is preventive for future crawls. No re-crawl needed regardless.
- **`cupertino search --source packages` returns 0 results** ([#261](https://github.com/mihaelamj/cupertino/issues/261)): the `--source` dispatch in `SearchCommand.run()` lumped `packages` together with the doc-shaped sources (`apple-docs`, `apple-archive`, `swift-evolution`, `swift-org`, `swift-book`) and routed them all to `runDocsSearch`, which queries `search.db` only. Packages live in their own DB (`packages.db`) with their own fetcher (`PackageFTSCandidateFetcher`); querying `search.db` for `source = 'packages'` rows always returned empty. The unified fan-out path correctly opened `packages.db` via `openPackagesFetcher`, so default search returned package results, masking the bug. `--source packages` now routes to a new `runPackageSearch` runner that wraps `Search.PackageFTSCandidateFetcher` in a single-fetcher `Search.SmartQuery` and renders through the same `printSmartReport` formatter as the default fan-out. Output JSON shape is `{candidates, contributingSources: ["packages"], question}`, consistent with the unified search rather than the per-source list views. Honors `--platform` / `--min-version` filters and `--packages-db` override. Verified: `cupertino search "alamofire" --source packages` was returning 5 bytes (`[]\n`); now returns SourceKitten / SWXMLHash / package-collection results.

### Changed

- **Cupertino skill (`skills/cupertino/SKILL.md`) gained query-strategy + verification guidance** ([#260](https://github.com/mihaelamj/cupertino/pull/260)): the previous version was a thin command reference. The new version teaches the LLM to translate descriptive queries to canonical Apple terms before searching (translation table for SwiftUI / UIKit / AppKit primitives), handle typos itself (cupertino does exact lexical matching, not fuzzy), infer framework from context, prefer current API over deprecated, recover when results are weak (paradigm bridge / conceptual phrasing / samples corpus), and surface what was tried instead of silently rewriting. Added a citation-and-verification section: cite-as-you-go for every API mention (~5% token overhead, prevents most API-knowledge hallucinations), re-search uncertain claims as needed, never fabricate parameters / return types / availability. Also corrects the example JSON shapes to match cupertino's actual response (`candidates` / `identifier` / `question`, not the previously-claimed `results` / `uri` / `count` / `query` keys), documents per-source view shapes, and refreshes doc count from 300k to 405k pages.

### Internal

- **`CLAUDE.md` refreshed for v1.0.1** ([#263](https://github.com/mihaelamj/cupertino/pull/263)): post-First-Light state (closed the v1.0.0 phase framing, listed the v1.0.1 milestone bugs, replaced the dead `fix/all-open-bugs-2026-04` branch reference with the trunk-based per-bug workflow). v1.1+ research notes now point at `mihaela-blog-ideas/cupertino/research/`.

---

## 1.0.0 "First Light" — 2026-05-05

_The first release we'd call properly stable. Consolidates what was originally scoped as v0.11.0 (packages-overhaul) + v0.12.0 (docs-overhaul) into a single cut. Release plan: [#192](https://github.com/mihaelamj/cupertino/issues/192). Canonical roadmap: [#183](https://github.com/mihaelamj/cupertino/issues/183)._

### Search ranking — canonical type queries land their canonical answer

A multi-pass ranker rewrite for the smart-query fan-out + the apple-docs source. Pre-1.0 the default `cupertino search Task` returned a Mach kernel C-function essay; post-1.0 it returns the Swift `Task` struct, and the same shape holds for every common single-token type query (Task, View, URLSession, Color, String, Result, Array, Optional, Image, Text, URL, Data, Date, Sequence, AsyncSequence, Hashable, Codable, Comparable, Equatable, Sendable, Identifiable, …). 34 of 35 canonical queries land their canonical apple-docs page at fused #1 against the v1.0 corpus (the holdout, `Stack`, has no canonical Swift / SwiftUI / Foundation type and resolves to `tvml/Stack` correctly).

- **Intent-routed fan-out** ([#254](https://github.com/mihaelamj/cupertino/issues/254)): `Search.SmartQuery` detects symbol-shaped queries (single token, ≥2 chars, ASCII identifier, leading uppercase) and prunes the fetcher set to apple-docs + swift-evolution + packages before fan-out. Prose queries keep the all-source path. Stops apple-archive's "Common Tasks in OS X" essay from tying with Swift's `Task` struct on the fused rank.
- **Authority-weighted RRF** ([#254](https://github.com/mihaelamj/cupertino/issues/254)): replaces plain RRF's `1/(k+r)` with `weight[source]/(k+r)`. apple-docs 3.0, swift-evolution / packages 1.5, swift-book / swift-org 1.0, apple-archive / hig 0.5. Cross-source rank-1 ties resolve without per-query intent routing carrying the whole load.
- **HEURISTIC 1 split** ([#254](https://github.com/mihaelamj/cupertino/issues/254)): the suffixed " | Apple Developer Documentation" title marks Apple's parent landing page for a type. Suffixed pages get a 50× exact-title boost; clean-titled siblings keep the previous 20×. Flips canonical-vs-sub-symbol order on the apple-docs side without touching BM25F weights.
- **HEURISTIC 1.5 — exact-title peer tiebreak** ([#256](https://github.com/mihaelamj/cupertino/issues/256)): when multiple apple-docs pages all hit the exact-title boost (e.g. `Result` matches Swift's enum, Vision's associated type, Installer JS's runtime type), URI-simplicity (top-level type page vs sub-symbol) and a narrow framework-authority map (`Search.Index.frameworkAuthority`) break the tie. Fires only inside the exact-title branch — does not crowd out framework-specific symbol queries (`VisionRequest` still resolves to `vision/VisionRequest`).
- **Force-include canonical type pages past fetchLimit** ([#256](https://github.com/mihaelamj/cupertino/issues/256) follow-on): for top-tier frameworks (swift, swiftui, foundation), `Search.Index.fetchCanonicalTypePages` hand-fetches `apple-docs://FRAMEWORK/documentation_FRAMEWORK_QUERY` directly by URI. Probes by docs_metadata PK (5 ms), not an FTS5 scan. Catches canonicals BM25 buries past the candidate cutoff (Foundation `URL` at raw rank 1017, Swift `Identifiable` at 2577, Foundation `Data` past 3000).
- **`doc_symbols_fts` post-rank sign error** ([#254](https://github.com/mihaelamj/cupertino/issues/254)): `result.rank * 0.3` on a negative BM25 rank was a *demotion*, not the documented "3x boost". Changed to `* 3.0`. Canonical Swift types have AST symbols indexed; kernel C functions don't, so the sign error was silently letting kernel C functions outrank Swift types.
- **`fetchLimit` floor at 1000** ([#254](https://github.com/mihaelamj/cupertino/issues/254)): smart-query fan-out used to over-fetch only 200 rows; canonical Swift `Task` struct sits at raw BM25 position 241, never made the candidate set. Floor at 1000, ceiling 2000.
- **packages.db canonical-repo force-include**: when query tokens (or their dash-joined form) match an indexed `repo` name exactly, `Search.PackageQuery` fetches that repo's top BM25 file as a force-included candidate. Catches `vapor middleware` → vapor/vapor (was swift-openapi-generator), `swift testing` → swiftlang/swift-testing, `swift dependencies` → pointfreeco/swift-dependencies. Two-tier match: dashed forms (`swift-testing`) outrank single-token forms (`swift`) so `swift testing` doesn't pull in swiftlang/swift via the bare token.
- **Search.Index DB lock fix**: every `Search.Index.init` used to issue an unconditional `PRAGMA user_version = N` write — two parallel `cupertino search` invocations contended on the open-time write lock and one would fail with `database is locked` (SQLite's default `busy_timeout` is 0). `setSchemaVersion` now read-then-write (skips the PRAGMA when version already matches) and `sqlite3_busy_timeout(db, 5000)` is set right after open so any future contention degrades to a wait-then-succeed.
- **Search perf — canonical/framework-root probes use docs_metadata PK**: the `fetchCanonicalTypePages` and `fetchFrameworkRoot` helpers used to query `docs_fts` with `WHERE f.uri = ?`, which forced a full FTS5 scan (3.2 s per probe on the v1.0 corpus). Now query `docs_metadata` only, with title/summary read via `json_extract(json_data, '$.title' / '$.abstract')`. 5 ms per probe — single-process search wall time on the 3.4 GB corpus dropped from ~18 s to ~4 s.
- **Field-weighted BM25 (BM25F) on apple-docs** ([#181](https://github.com/mihaelamj/cupertino/issues/181), subsumes earlier title-weight work): per-column weights `bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0)` — title 10×, AST-derived symbols 5×, summary 3×, framework 2×. The retrieval foundation the heuristics above sit on top of.

### Distribution — single-bundle release

- **All three databases ship in one bundle** on `mihaelamj/cupertino-docs`: `cupertino-databases-vX.zip` contains `search.db` + `samples.db` + `packages.db`. The earlier scoping had a separate `mihaelamj/cupertino-packages` companion repo for `packages.db`; that repo proved to be needless complexity (same crawl, same schedule, two release tags) and is gone. `cupertino setup` is one download + one extract.
- **`cupertino-rel databases`** ([#259](https://github.com/mihaelamj/cupertino/issues/259)): the release tool bundles all three DBs into a single zip and uploads to the docs repo. Hard-fails if `packages.db` is missing under `--base-dir` unless `--allow-missing-packages` is passed (lets a release runner publish a partial bundle in time-sensitive cases without making it the default). Generic publishing primitives (zip, sha256, GitHub API, upload progress, token resolution) factored into a shared `ReleasePublishing` helper.
- **`cupertino setup` rewrites the pipeline** to a single download + extract + version stamp. Removes the previous "docs zip → extract → packages zip → extract → soft-fail-if-missing" path. All three DBs are now required post-extract; any missing DB is a hard fail rather than a warning. (#246 lifted SetupCommand's logic into a `Distribution` package; this release simplifies the pipeline that lift exposed.)
- **`cupertino setup` backs up existing DBs** before overwrite ([#249](https://github.com/mihaelamj/cupertino/issues/249)): each pre-existing DB renames to a `.backup-<version>-<iso8601>` sibling before extraction would clobber it. User can roll back by renaming the backup over the new file if v1.0 misbehaves.

### Changed

- **Four-package CLI lift: `Distribution`, `Diagnostics`, `Indexer`, `Ingest`** ([#244](https://github.com/mihaelamj/cupertino/issues/244), [#245](https://github.com/mihaelamj/cupertino/issues/245), [#246](https://github.com/mihaelamj/cupertino/issues/246), [#247](https://github.com/mihaelamj/cupertino/issues/247)): logic that powered four CLI commands — `setup`, `doctor`, `save`, `fetch` — moved out of `Sources/CLI/Commands/*` into four new SPM packages so MCP tooling, future agent-shell adapters, and tests can drive the pipelines without depending on `ArgumentParser`. CLI files become thin front-doors that parse flags + render progress.
  - **`Distribution`** (#246): download + extract + version-stamp pipeline. `SetupService` orchestrator emits `Event` callbacks (download progress / extract ticks / status changes); `ArtifactDownloader` (URLSession + progress callback), `ArtifactExtractor` (`/usr/bin/unzip` wrapper), `InstalledVersion` (status classification + stamp file r/w), `PackagesReleaseURL` (relocated from CLI). Drive-by fix: `InstalledVersion.classify` now requires all three DBs (search, samples, packages) to be present for non-`.missing` states — pre-#246 it ignored packages.db, so a partial install reported `.current` and skipped the redownload. `SetupCommand.swift` 478 → 177 LoC.
  - **`Diagnostics`** (#245): pure-data probes for SQLite + filesystem corpus. `Probes.userVersion` / `perSourceCounts` / `rowCount` / `countCorpusFiles` / `packageREADMEKeys` / `userSelectedPackageURLs` / `ownerRepoKey`, plus `SchemaVersion.format`. Zero external deps; opens DBs via `SQLITE_OPEN_READONLY`. `DoctorCommand.swift` 596 → 400 LoC. Foundation for a follow-up `HealthReport` + `DoctorService` so MCP can expose the same diagnostic data as a tool.
  - **`Indexer`** (#244): write-side counterpart to `Search`. Three indexer services (`DocsService` wraps `Search.IndexBuilder`, `PackagesService` wraps `Search.PackageIndexer`, `SamplesService` wraps `SampleIndex.Builder`) each emit per-stage `Event` callbacks. `Preflight` namespace hosts the #232 preflight pipeline (`preflightLines`, `checkDocsHaveAvailability`, `sampleDocsAvailability`, `countPackagesAndSidecars`) — used by both `cupertino save` (write-time prompt) and `cupertino doctor --save` (read-only health check). `SaveCommand.swift` 828 → 312 LoC + 229 LoC in `SaveCommand+Indexers.swift` (split to fit `type_body_length` 300-line ceiling). `--remote` mode stays in CLI for now; lifting it needs the underlying `RemoteIndexer` pipeline to grow a callback shape.
  - **`Ingest`** (#247 sub-PR 4a): package skeleton + `Session` helpers — five static lifted from `FetchCommand` (`clearSavedSession`, `requeueErroredURLs`, `requeueFromBaseline`, `enqueueURLsFromFile`, `checkForSession`) plus internals (`collectBaselineURLs`, `lowercaseDocPath`) and `FetchURLsError`. `FetchCommand.swift` 1279 → 1022 LoC. The seven `<Type>Pipeline` services (docs / packages / samples / evolution / archive / hig / availability) stay in CLI for now — those need a callback-based shape before they can lift cleanly. Tracked as follow-up sub-PRs 4b–4f in #247.
  - All four packages: `swift build` clean, full suite passes (1163 tests / 126 suites — 5 new tests added per package).
- **`cupertino read` unified across docs / samples / packages** ([#239](https://github.com/mihaelamj/cupertino/issues/239) follow-up): a single command now dispatches to all three backends. URI scheme (`apple-docs://...`, `hig://...`, etc.) → docs (search.db). Slugified id with no `/` → sample project. `<projectId>/<path>` → sample file. `<owner>/<repo>/<path>` → package (read from `package_files_fts.content`, no on-disk corpus needed). `--source <name>` disambiguates sample-file vs. package paths. Logic lives in `Services/Commands/ReadService.swift`. `Search.PackageQuery.fileContent(owner:repo:relpath:)` added so `cupertino setup`-only installs (no `~/.cupertino/packages/` tree) work for package reads.
- **`cupertino search` emits read-full hints + `--brief` mode** ([#239](https://github.com/mihaelamj/cupertino/issues/239) follow-up): every fan-out result now prints `▶ Read full: cupertino read <id> --source <name>` after the chunk (text), `- **Read full:** ...` (markdown), `readFullCommand` field (json) — uniform, source-aware. `--brief` flag truncates each chunk to 12 non-blank lines for triage; default stays full chunks. Footer adds `See also` (per-source drill-in commands) + tips (narrow with `--source`, platform-filter hint).

### Removed

- **`cupertino ask` subcommand removed; absorbed into `cupertino search`** ([#239](https://github.com/mihaelamj/cupertino/issues/239)): two CLI commands serving overlapping needs collapsed into one. `cupertino search "<question>"` (no `--source`) now runs the SmartQuery fan-out across every available DB with reciprocal-rank-fusion ranking and chunked excerpt output — exactly what `ask` did. `cupertino search --source <name>` keeps its existing list-style output unchanged. The `--platform` / `--min-version` / `--per-source` / `--skip-docs` / `--skip-packages` / `--skip-samples` / `--packages-db` flags carried over from `ask`. JSON / markdown output formats also produce SmartQuery-shaped chunks now — the previous `UnifiedSearchService` path is gone. Pre-1.0 clean break, no alias — `cupertino ask` errors with `unknown command`. Subcommand count drops 15 → 14. `package-search` (hidden) stays as the packages-only shortcut. `SearchCommand.swift` was split alongside the merge: per-source runners moved to `SearchCommand+SourceRunners.swift`, fan-out plumbing + chunked printers to `SearchCommand+SmartReport.swift` (lint type-body-length compliance). CHANGELOG, docs (`docs/commands/ask/` deleted, `docs/commands/search/` expanded), and `CommandRegistrationTests` updated.

### Fixed

- **Sample search FTS5 query OR-joins instead of AND-joining every token** ([#238](https://github.com/mihaelamj/cupertino/issues/238)): `SampleIndex.Database.searchFiles` and `searchProjects` were space-AND'ing every quoted token from the input, so a natural-language query like `"how do I animate a swiftui list"` resolved to `"how" "do" "I" "animate" "a" "swiftui" "list"` — implicit AND across seven phrases, no sample file matched all seven, samples returned zero. Lifted the tokenization helpers from `Search.PackageQuery` into a new `Shared.FTSQuery` namespace (`tokens(from:stopwords:)` + `build(question:)`) that strips stopwords and OR-joins. Both `SampleIndex.Database` paths now share that builder with `PackageQuery`. Drive-by on `Services.SampleCandidateFetcher`: emit project-level matches in addition to file matches — natural-language queries frequently score a project's title/README without lighting any single file's content. Smoke run: `cupertino ask "how do I animate a swiftui list" --skip-docs` now returns the SwiftUI-animation sample at position 1, with `Searched: packages, samples`.
- **`cupertino search --source samples` no longer fails when search.db is locked** ([#237](https://github.com/mihaelamj/cupertino/issues/237)): the command was unconditionally fetching teaser previews from search.db even when scoped to samples-only. When another process held an EXCLUSIVE write lock (typically a long-running `cupertino save --docs`), the teaser fetch threw and the whole command aborted before samples results were rendered. Wrapped the teaser fetch in do/catch — on failure logs a one-line info note and falls back to empty `TeaserResults`. Samples results display unchanged. `ask --skip-docs` already had similar resilience via fetcher-failure-collapses-to-empty (#220).

### Added

- **Date-based schema-version helpers + doctor surfacing** ([#234](https://github.com/mihaelamj/cupertino/issues/234)): new `Shared.SchemaVersion` namespace produces fixed-width 12-char `YYYYMMDDhhmm` strings (`make`, `now`, `components`, plus a `dateOnlyInt32` fallback for `PRAGMA user_version` and `iso8601Now` for human-readable audit fields). Each DB will switch over on its next real schema bump — keeps the `if currentVersion < N` migration ladder intact since old sequential ints sort below any reasonable date-style value. `cupertino doctor` gained a Schema-versions section that prints `PRAGMA user_version` from search.db, packages.db, and samples.db and labels each as date-style or sequential, so a stale machine in the multi-Mac sync setup is one command away from being obvious. 12 new tests cover fixed-width, round-trip, range validation, lex-ordering. Convention is custom — most SQLite ecosystems use sequential ints — but documented.
- **`--platform` / `--min-version` now scope `ask` results from samples + docs too** ([#233](https://github.com/mihaelamj/cupertino/issues/233)): the filter is no longer packages-only. `SampleCandidateFetcher` accepts `availability:` and JOINs `projects` on `min_<platform>` in the SQL. `DocsSourceCandidateFetcher` accepts `availability:` and forwards to `Search.Index.search`'s existing `minIOS` / `minMacOS` / `minTvOS` / `minWatchOS` / `minVisionOS` params (which already do proper semver compare in memory). Swift-language-version sources (`swift-evolution`, `swift-org`, `swift-book`) silently drop the filter — their pages don't carry OS-version columns; that axis lives under #225. The unfiltered-source notice in `ask` now lists only those three sources, since apple-docs / apple-archive / hig / packages / samples all honour the filter.
- **samples.db now persists per-sample availability** ([#228](https://github.com/mihaelamj/cupertino/issues/228) phase 2): schema bumped 2→3 (no migration; `save --samples` always wipes and rebuilds). `projects` table gains `min_ios` / `min_macos` / `min_tvos` / `min_watchos` / `min_visionos` / `availability_source` columns plus indexes; `files` gains `available_attrs_json` carrying the per-file `@available(...)` occurrences as a JSON array. `SampleIndexBuilder` now passes the parsed `Package.swift` deployment targets into the `Project` row and the per-file attribute list into each `File` row, so the same data the sidecar JSON writes is also queryable from SQL. `availability_source = "sample-swift"` when populated; `NULL` when the sample shipped no `platforms: [...]` block (typical of Apple's Xcode-project samples). Round-trip tests cover both columns.
- **`cupertino save` preflight + `cupertino doctor --save`** ([#232](https://github.com/mihaelamj/cupertino/issues/232)): `save` now prints a per-scope summary before any DB write — which source dirs are present, how many packages have `availability.json` sidecars, whether the docs corpus has been annotated by `fetch --type availability` — then prompts `Continue? [Y/n]` and lets the user bail. Auto-skips the prompt when stdin isn't a TTY (CI / pipes) and via `--yes`. The same summary is reachable read-only as `cupertino doctor --save` for users who want to know "is save ready?" without committing to a run. `checkDocsHaveAvailability` was refactored into pure helpers (`sampleDocsAvailability`, `firstJSONFile`, `jsonContainsAvailability`) with named-constant tunables so tests can pin behavior.

### Changed

- **`cupertino save` now builds all three databases by default; `cupertino index` removed** ([#231](https://github.com/mihaelamj/cupertino/issues/231)): scope flags `--docs` / `--packages` / `--samples` select a subset; with no scope flag passed `save` builds search.db, packages.db, and samples.db in that order, skipping any source directory that's missing with an info log. The standalone `cupertino index` command is gone — its body lives under `save --samples` (with `--samples-dir`, `--samples-db`, `--force` options renamed for symmetry). Pre-1.0 clean break, no alias. Subcommand count drops 16 → 15.

### Added

- **`cupertino ask` now includes the samples corpus** ([#230](https://github.com/mihaelamj/cupertino/issues/230)): new `Services.SampleCandidateFetcher` adapts `SampleSearchService` to the `Search.CandidateFetcher` protocol so `Search.SmartQuery`'s reciprocal-rank fusion fans out across `apple-docs`, `apple-archive`, `hig`, `swift-evolution`, `swift-org`, `swift-book`, **packages**, and **samples** in one call. New `--skip-samples` flag and `--samples-db <path>` override mirror the existing `--skip-packages` / `--packages-db` shape. Default behaviour: samples included whenever `samples.db` exists. Smoke run: `ask "swiftui list animation" --skip-docs` returns sample matches with FTS5-extracted snippets alongside package hits.
- **`--platform` / `--min-version` filters on `package-search` and `ask`** ([#220](https://github.com/mihaelamj/cupertino/issues/220)): two new options that restrict packages results to those whose declared deployment target is compatible with the named platform. Values: `iOS`, `macOS`, `tvOS`, `watchOS`, `visionOS` (case-insensitive). Both flags are required together; one without the other errors out. Filter pushes through `PackageFTSCandidateFetcher` → `Search.PackageQuery.AvailabilityFilter` → SQL JOIN on `package_metadata.min_<x>` with a lexicographic compare. Lex compare is correct for current Apple platform versions (iOS 13+, macOS 11+, tvOS 13+, watchOS 6+, visionOS 1+); old macOS 10.x with multi-digit minors would mis-order but no priority package currently targets that. Packages with NULL annotation source are dropped (no annotation = unknown = excluded). `ask` only filters its packages source — apple-docs / hig / archive / evolution remain unfiltered.
- **packages.db now persists availability data** ([#219](https://github.com/mihaelamj/cupertino/issues/219) follow-up): `save --packages` reads each package's `availability.json` (produced by `fetch --type packages --annotate-availability`) and writes flat columns into `package_metadata` (`min_ios`, `min_macos`, `min_tvos`, `min_watchos`, `min_visionos`, `availability_source`) plus a `available_attrs_json` column on `package_files` carrying the per-file `@available(...)` occurrences as a JSON array. Mirrors the `docs_metadata` availability shape from #192 sec. C, so callers can filter packages by minimum platform without parsing JSON. Schema bump 1→2 with idempotent ALTER-TABLE migration; existing v1 DBs pick up the columns on next open. Verified on the May 2026 priority closure: all 183 packages have `availability_source = 'package-swift'` populated. The `available_attrs_json` column is NULL when no annotation file was present, so callers can distinguish "not annotated" from "annotated with no attrs".
- **`fetch --type packages --annotate-availability`** ([#219](https://github.com/mihaelamj/cupertino/issues/219)): new opt-in stage 3 of the merged packages fetch. Walks every `<owner>/<repo>/` subdir under `~/.cupertino/packages/` and writes a per-package `availability.json` capturing the `Package.swift` `platforms: [...]` deployment-target block plus every `@available(...)` attribute occurrence in `Sources/` and `Tests/` (file path + line + parsed platform list). Pure on-disk pass — no network. Idempotent. Runs whether or not stage 2 just downloaded fresh archives, so you can re-annotate an existing corpus by combining `--skip-metadata --skip-archives --annotate-availability`. Smoke run on the May 2026 priority closure: 183 packages annotated, 13.5k `@available` attrs in 12s. Regex-based scanner — multi-line attrs aren't handled and hits aren't tied to specific declarations; the AST upgrade (extending `ASTIndexer.SwiftSourceExtractor`) is a follow-up.

### Fixed

- **Dev binary now writes to `~/.cupertino-dev/` automatically** ([#218](https://github.com/mihaelamj/cupertino/issues/218)): `make build-debug` and `make build-release` now drop a `cupertino.config.json` next to the produced binary with `{ "baseDirectory": "~/.cupertino-dev" }`. Previously a locally-built dev binary silently fell through to brew's `~/.cupertino/`, clobbering the installed user's data mid-flight (hit on the 2026-05-03 packages-overhaul rebuild). Brew bottles still ship only the binary — released installs continue to resolve to the standard `~/.cupertino/`. Override at invocation: `make build-debug DEV_BASE_DIR=~/some-other-dir`.
- **`PriorityPackagesCatalog` additively merges new embedded entries into existing user files** ([#218](https://github.com/mihaelamj/cupertino/issues/218)): `ensureUserSelectionsFileExists` used to no-op once `~/.cupertino/selected-packages.json` existed, so adding new seeds to `PriorityPackagesEmbedded.swift` never propagated to existing installs. A Dec 2025 user file frozen at the priority list from then was missing the April 2026 `mihaelamj/*` additions despite the embedded JSON having them. Fix: on every load, set-diff against the user file (matched on `owner.lowercased()/repo.lowercased()`) and append any embedded entries the user file is missing. Idempotent, never removes, prints a one-line `📥 selected-packages.json: added N new priority entries…` summary on the run that adds anything. User deletions don't stick — that's a deliberate trade-off (separate "removed" list would be needed; called out in the #218 comment).
- **FetchCommand "Next:" hint now points at the real save flag** (`save --packages`, not the non-existent `save --type packages`).

### Changed

- **Merged `fetch --type packages` and `fetch --type package-docs`** ([#217](https://github.com/mihaelamj/cupertino/issues/217)): a single `--type packages` now runs the Swift Package Index metadata refresh and the priority-package GitHub archive download back-to-back. New `--skip-metadata` / `--skip-archives` flags gate either stage individually; passing both is an error. The two were already adjacent in every workflow, shared the `~/.cupertino/packages/` output dir, and the `package-docs` name was misleading (it pulled whole archives, not READMEs). The `package-docs` raw value is gone — invocations using it now error with the help text. `directFetchTypes` count dropped 7→6, `allTypes` 10→9. `--type all` still covers both stages because the merged command is what runs.

### Added

- **Binary-co-located config file** ([#211](https://github.com/mihaelamj/cupertino/issues/211)): new `Shared.BinaryConfig` reads an optional `cupertino.config.json` from the directory of the running executable (symlinks resolved). One key supported today: `baseDirectory` (tilde-expanded). When present, every default path in `Shared.Constants.default*` plus `SampleIndex.defaultDatabasePath` and `SampleIndex.defaultSampleCodeDirectory` redirects under that base, so `fetch`, `save`, `serve`, `ask`, `doctor`, and the samples DB all follow uniformly without env vars or per-command flags. Missing file or any decode error falls through to the existing `~/.cupertino/` default, so installs without the file behave identically to before. Use case: run a dev build alongside an installed brew binary against separate corpora. Contract test (`BasePathDerivationTests`, `SampleIndexBasePathDerivationTests`) asserts every default path derives from `defaultBaseDirectory`, so a future getter that bypasses it fails at test time.
- **`cupertino resolve-refs` subcommand** ([#208](https://github.com/mihaelamj/cupertino/issues/208)): post-process pass that walks a directory of saved `StructuredDocumentationPage` JSON files (typically from a `--discovery-mode json-only` crawl), harvests a global `identifier → title` map from each page's `sections[].items[]`, and rewrites every `doc://com.apple.<bundle>/...` marker in `rawMarkdown` to the readable title. Pure post-process by default: no network, no recrawl. Markers pointing to pages no other page references are left intact and surfaced via `--print-unresolved`.
- **`resolve-refs --use-network` and `--use-webview` flags** ([#208](https://github.com/mihaelamj/cupertino/issues/208)): opt into a second pass that fetches titles for the still-unresolved markers via Apple's JSON API (`--use-network`), or also falls back to WKWebView when the JSON API can't serve a marker (`--use-webview`, slow, macOS only).
- **`fetch --urls <path>` flag** ([#210](https://github.com/mihaelamj/cupertino/issues/210)): read URLs from a text file (one per line) and enqueue each at depth 0, with the crawler following links from each up to `--max-depth`. Set `--max-depth 0` to fetch only the listed URLs with no descent. Useful for fetching a fixed list of URLs another corpus has but this one is missing, without re-spidering. `#`-prefixed and blank lines are ignored.
- **Crawl depth stamped on every saved page**: each `StructuredDocumentationPage` JSON now carries the depth at which it was discovered, so corpus auditing and per-depth analysis no longer need to recompute from link graphs.

### Fixed

- **Exponential retry backoff for crawler page failures** ([#209](https://github.com/mihaelamj/cupertino/issues/209)): a transient page failure used to retry immediately, hammering the same URL on the same network blip. Backoff is now 1s / 3s / 9s / capped at `Shared.Constants.Delay.retryBackoffMax` for attempts 1+. Capped, so a hard-failing page can't stall the crawl indefinitely.
- **Hardcoded `~/.cupertino/` paths in user-facing strings** (#211 follow-up): four offenders that would print the wrong path under a `BinaryConfig` override now interpolate the resolved path. `SearchIndex.swift` schema-mismatch errors (versions 5 and 12 migration thresholds) now suggest `rm <actual-search-db-path> && cupertino save`. `FetchCommand` priority-packages "not found" message now prints `Shared.Constants.defaultPackagesDirectory.appendingPathComponent("priority-packages.json").path`. `IndexCommand` discussion text and `--sample-code-dir`/`--database` help defaults, plus `CleanupCommand` `--sample-code-dir` help default, all interpolate `SampleIndex.default*` and `Shared.Constants.defaultSampleCodeDirectory` so `--help` reflects the actually-configured paths.
- **URL canonicalization — case axis** ([#200](https://github.com/mihaelamj/cupertino/issues/200)): `URLUtilities.normalize` now lowercases the URL path. Apple's docs server is case-insensitive on the path, so `/documentation/Cinematic/CNAssetInfo-2ata2` and `/documentation/cinematic/cnassetinfo-2ata2` return the same content. The crawler previously treated each casing as a distinct URL — visited set held both, queue was inflated ~3× with case duplicates (62 % of queue entries on the April 2026 in-flight crawl), ETA estimates were correspondingly off. Fragment and query stripping unchanged. Path-segment dash-vs-underscore variants are NOT collapsed: at least one Apple framework (`installer_js`) legitimately uses underscore in its canonical path, and observed dash/underscore "duplicates" (e.g. `professional-video-applications` vs `professional_video_applications`) turned out to be Apple serving distinct documentation sets at similar slugs, not URL aliases. That axis will be handled at the search-index save layer if and when real duplicates are observed; the canonicalization patch alone is conservative.

### Added

**Search quality — field-weighted BM25 with AST-extracted symbols (#192 sections C + D, subsumes #176)**

The retrieval technique is **BM25F** (field-weighted BM25, Robertson/Zaragoza/Taylor 2004) over a structured 8-column FTS5 index (`uri`, `source`, `framework`, `language`, `title`, `content`, `summary`, `symbols`), augmented with a Swift AST symbol extractor. Public API surface: `Search.SmartQuery` (see "smart-query wrapper" below). Underneath:

- `Search.DocKind` taxonomy: 10-case enum (`symbolPage`, `article`, `tutorial`, `sampleCode`, `evolutionProposal`, `swiftBook`, `swiftOrgDoc`, `hig`, `archive`, `unknown`) populated at index time by `Search.Classify.kind(source:structuredKind:uriPath:)` — a pure deterministic function. Stored in new `docs_metadata.kind` column.
- `docs_metadata.symbols` denormalized blob + `docs_fts.symbols` FTS column. Both populated by an AST pass (`SwiftSourceExtractor` over both code-block content AND declaration lines) so a query like `Task` ranks the Swift `Task` struct page above prose mentions of the word "task". The BM25F weight vector is `bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0)` — title dominates (10×), symbols next (5×), summary (3×), framework (2×).
- `idx_kind` index for per-kind routing queries.
- `Search.Index.extractCodeExampleSymbols` + `recomputeSymbolsBlob` (private) — a single source of truth that reads `doc_symbols` and writes both denormalized columns, so declaration-derived and code-block-derived symbols flow into ranking uniformly.

**smart-query wrapper — `Search.SmartQuery`, exposed as `cupertino search` (#192 section E, #239)**

The user-facing label is **smart-query** (lowercase prose). The technique is **reciprocal rank fusion (RRF)** of per-source BM25F rankings — Cormack, Clarke, Büttcher 2009. Originally shipped as `cupertino ask`; merged into the default `cupertino search` fan-out per #239 before tag.

- Public-facing CLI: `cupertino search "<question>"` runs the question across every available source (apple-docs, apple-archive, hig, swift-evolution, swift-org, swift-book, packages) in parallel and returns a fused top-N. No `--source` flag needed.
- `Search.SmartCandidate` source-agnostic result struct. `Search.CandidateFetcher` protocol with one method, `fetch(question:limit:)`, per source. Concrete impls: `PackageFTSCandidateFetcher` (wraps `Search.PackageQuery.answer`), `DocsSourceCandidateFetcher` (wraps `Search.Index.search` for any apple-docs-style source).
- `Search.SmartQuery` fans fetchers out via `TaskGroup`, fuses per-source rankings via RRF (k=60, the standard default). Failing fetchers collapse to empty — one dead DB never takes the whole query down. Per-fetcher limit caps noisy sources before fusion so a verbose source can't drown out a strong single hit.
- `cupertino package-search` (hidden) is now a thin wrapper on `SmartQuery` with a single `PackageFTSCandidateFetcher`, so ranking tweaks land in one place.

**MCP protocol bump — 2025-11-25 (#192 section G, subsumes #139)**
- `MCPProtocolVersion` 2025-06-18 → **2025-11-25**. `MCPProtocolVersionsSupported` widened to `[2025-11-25, 2025-06-18, 2024-11-05]` for backward-compat across three negotiation hops.
- New `Icon` struct (`src` / `mimeType` / `sizes`) Codable + Hashable + Sendable.
- `Implementation` gains optional `icons: [Icon]?`. Nil by default; legacy 2025-06-18 / 2024-11-05 handshakes decode legacy payloads unchanged.
- `MCPServer.init(name:version:icons:)` accepts an optional icons array. `cupertino serve` now advertises a 64×64 PNG via `data:image/png;base64,...` URI, embedded in `CupertinoIconEmbedded.swift` following the same Swift-literal pattern as #161 (no asset bundle, no symlink resolution).
- `assets/cupertino-icon-64.png` ships in the repo as the source-of-truth (1671 bytes, systemBlue rounded square with a white "C"). Placeholder; a designer can replace.

**Doctor diagnostics (#192 section F)**
- `cupertino doctor` reports both `search.db` and `packages.db` presence, file size, row counts. Reads `PRAGMA user_version` directly (without going through `Search.Index`, whose init throws on incompatible versions) so the user sees the actual on-disk version even when it's incompatible.
- Schema-mismatch path: `older` → "rm + cupertino save" hint, `newer` → "brew upgrade cupertino" hint. Exits non-zero so CI / smoke tests fail loudly.
- `packages.db` row counts (packages, package_files) + bundled `databaseVersion` for at-a-glance install verification.

**Distribution + packaging (#192 section B)**
- All three databases ship in a **single bundle** — `cupertino-databases-vX.zip` on `mihaelamj/cupertino-docs`. v1.0.0 is the first release where `packages.db` is included alongside `search.db` and `samples.db`. (Earlier scoping had a separate `mihaelamj/cupertino-packages` companion repo for `packages.db`; that proved to be needless complexity. Setup is one download, one extract.)
- `cupertino setup` is the **single command** that owns every database. Downloads + extracts the bundle from `cupertino-docs` and stamps the version file on success. No granularity flag — the previous `cupertino packages-setup` is removed.
- `cupertino-rel databases` (the release tool) bundles all three DBs together. Hard-fails if `packages.db` is missing under `--base-dir` unless `--allow-missing-packages` is passed; lets a release runner publish a partial bundle in genuinely time-sensitive cases without making it the default. (#259)
- `Shared.Constants.App.docsReleaseBaseURL` is the only release URL constant.

**Per-URL JSON-then-WebView fallback (`fetch --type docs`)**
- `cupertino fetch --type docs` does a single pass through the queue, trying Apple's JSON API for each URL and falling back to WKWebView when a page has no JSON endpoint. **One of cupertino's coverage advantages over single-pass JSON-only MCPs** — every URL gets a chance at both transports without doubling the queue. (The fallback was already implemented in `Crawler.swift`; the previous "two-pass" orchestration in `FetchCommand` was redundant — it ran the same crawler twice — and is now removed along with the dead `--use-json-api` flag.)
- **Auto-resume by default**: if `metadata.json` has an active session matching the start URL, `cupertino fetch` picks it up without any flag. The previous `--resume` flag was just a log-message switch and is removed.
- **`--start-clean`**: new flag. Wipes `metadata.json`'s `crawlState` (queue + visited set) before running so the crawl starts fresh from the seed URL. Page-level state on disk is preserved — combine with `--force` to also re-fetch unchanged pages.
- **Crash-safe metadata save**: `JSONCoding.encode(_:to:)` now writes with `.atomic` (temp + rename), so a kill mid-save can never leave `metadata.json` corrupt. Mid-save corruption was the one failure mode that could make a multi-day crawl unresumable.
- `defaultMaxPages` constant raised 15,000 → **1,000,000**. Effectively uncapped for full Apple-corpus crawls (~50–80k pages); previous 15k default would silently truncate at ~15–30% coverage.

**Reproducible re-crawl pipeline (#192 section I scaffolding)**
- `scripts/recrawl.sh` orchestrates the full v1.0 re-crawl: wipes stale DBs + crawl manifests + per-source raw output dirs (true clean slate for schema bumps), then runs phases 1–10 sequentially with named markers (`=== Phase N/10: <name> — START HH:MM:SS ===`) so a tail-following watcher can spot stage transitions and per-phase wall clock at a glance.
- Phase order: docs → evolution → swift → hig → archive → packages → package-docs → code → save → doctor. `code` (sample-code with WKWebView sign-in) is intentionally last so the long automated phases run unattended.
- `make test-clean` Makefile target wraps `clean + test` for the SwiftPM stale-build SIGTRAP escape hatch.

**Crawler quality + steerability**
- **`fetch --discovery-mode <auto|json-only|webview-only>`**: `auto` (default) preserves the existing JSON-primary + WKWebView-fallback behaviour. `json-only` runs the JSON API and skips the fallback (fastest, narrowest discovery). `webview-only` runs WKWebView for everything (slowest, broadest discovery, matches pre-2025-11-30 behaviour). Lets the user trade coverage for speed without code changes.
- **`fetch --baseline <path>`**: on startup, URLs present in a known-good baseline corpus directory (e.g. a prior `cupertino-docs/docs` snapshot) but missing from the current crawl's known set are prepended to the queue, so a resumed crawl recovers gaps without a full recrawl. Path comparison is case-insensitive (mirrors #200 normalisation).
- **`fetch --retry-errors`**: re-queues URLs that errored before save (visited but missing from the pages dict). Use after a filename or save bug is fixed to retry only the affected pages without re-crawling the whole corpus. Prepended so retries go first.
- **Filename-length cap**: extremely long Apple framework paths used to produce filenames that exceeded the OS limit and silently dropped pages on save. Filenames now cap with a content-derived suffix so the URL stays the unique key while the on-disk filename stays valid.
- **DocC link discovery walks the full `references` dict**: previous crawler followed only direct identifiers in `topicSections`/`seeAlsoSections`, missing references reachable through nested item dicts. The walk now recurses through every value in `references` so frameworks with deep cross-linking (e.g. Foundation) discover the full transitive set in one pass.
- **Queue dedup at enqueue time**: visited-set + queue-set membership check moved to the enqueue path so the same URL isn't pushed multiple times. Combined with #200 case normalisation, the April 2026 in-flight crawl's queue dropped from 518k entries to 198k unique URLs without losing coverage.
- **Per-page sync work wrapped in `autoreleasepool`**: long crawls used to leak Foundation autoreleased objects across thousands of pages, growing RSS until the OS killed the process around hour 12 of a multi-day run. Each page's parse + transform + save block is now its own autorelease scope, so RSS stays flat across an indefinite crawl.

**From the original v0.11.0 scope (pre-consolidation)**
- **Transitive dependency resolution for `fetch --type package-docs`** (#184): each seed is walked through its `Package.swift` (libraries commit this; most lockfiles are `.gitignored`), then `Package.resolved` as a fallback for apps. Dependencies on `github.com` are added to the fetch queue. Non-GitHub URLs, missing manifests, and malformed manifests are counted and skipped. Opt out with `--no-recurse`. Terminates via canonical-name dedupe.
- **GitHub redirect canonicalisation**: aliases like `apple/swift-docc` and `swiftlang/swift-docc` collapse into one entry instead of double-indexing. Cached at `~/.cupertino/.cache/canonical-owners.json`; one API call per unique repo, lifetime.
- **Persisted resolved closure** at `~/.cupertino/resolved-packages.json` with parentage + checksum. Re-fetch reuses the cache unless seeds changed or `--refresh` is passed. Answers "why is this package in my index?".
- **User exclusion list** at `~/.cupertino/excluded-packages.json`. Hand-edit to drop discovered-via-dep packages from future closures.
- **Parallel resolver** dispatches manifest fetches in batches of 10. A 200-package closure shrinks from ~3 min wall time to a few tens of seconds.
- **Per-branch manifest cache** at `~/.cupertino/.cache/manifests/<owner>/<repo>/<branch>/Package.swift` with 24h TTL. 404s cached as zero-byte sentinels.
- **SPM registry id counting** (`.package(id: …)`, SPM 5.8+) — surfaces in the resolver summary as `Skipped (SPM registry id)` rather than silently dropped.
- **TUI promote / exclude actions** (`x` toggle exclusion, `p` promote discovered-via-dep to seed). Visual indicators: `[*]` seed, `[X]` excluded, `[+]` discovered, `[ ]` none.
- **Expanded bundled `priority-packages.json`** from 36 to 135 seeds: 43 Apple (incl. `swift-syntax` swiftlang move, `swift-foundation`, `swift-markdown`, `swift-http-types`, `swift-nio-extras`, `swift-configuration`, `swift-distributed-tracing`); 92 ecosystem covering full Vapor + Hummingbird, expanded Point-Free, swiftlang, SSWG, tooling (SwiftFormat, SwiftLint, XcodeGen), Soto, SwiftUI Introspect, Tuist, plus project-specific seeds.

**Swift Testing proposals indexed alongside Swift Evolution (#178, contributed by @farkasseb)**
- `cupertino fetch --type evolution` now also crawls `proposals/testing/` from `swiftlang/swift-evolution`, so ST-prefixed proposals (Swift Testing) are first-class alongside SE-prefixed ones. Status regex updated to handle both prefix conventions; 404s on the testing subdir are handled gracefully (an empty testing/ dir is valid for older snapshots).
- `Search.SearchIndexBuilder` indexes ST proposals into the same `evolution` source so they're searchable via `cupertino search` and `cupertino ask`.
- New tests: `SwiftEvolutionCrawlerTests` (149 lines) + ST coverage in `CupertinoSearchTests` + `ServeTests`.

### Changed

- **`cupertino setup` default now re-downloads** (#168). The previous short-circuit-if-databases-present behaviour is opt-in via `--keep-existing`. Each successful download stamps `~/.cupertino/.setup-version` so subsequent runs report `current` / `stale` / `unknown` / `missing`. Motivation: users were stranded on stale DBs after `brew upgrade cupertino`.
- **Resource catalogs compiled into the binary** (#161): the four JSON catalogs are embedded as Swift raw-string literals under `Packages/Sources/Resources/Embedded/` instead of shipped as a `Cupertino_Resources.bundle`. The bundle-missing-on-Homebrew failure mode is fundamentally gone — there is no bundle. Obsoletes the `b9bc70a` symlink-resolution fix.
- **`swift-packages-catalog` slimmed to URL list only**: the embedded catalog carries just the 9,699 package URLs (~530 KB), not the previous metadata blob (~3.4 MB). Metadata returns via `packages.db` distribution. Tracked in [#194](https://github.com/mihaelamj/cupertino/issues/194) for full removal in v1.1.0 once `packages.db` is the canonical source.
- **Schema bump 10 → 12** (single user-visible jump, but two intermediate steps internally). v11 added `kind` + `symbols` to docs_metadata via ALTER TABLE. v12 added `symbols` to `docs_fts` (BREAKING — FTS5 can't ALTER columns). Existing v10/v11 DBs throw on open with a clear `rm + cupertino save` rebuild hint. Aligned with the v1.0 full re-crawl plan, so end users only see one transition.
- **`make test-clean` Makefile target** — `clean + test` in one command. Escape hatch for the Swift 6.2 / macOS 26 SwiftPM incremental-build bug where adding a method to an actor leaves stale `.o` files and async dispatch lands in the wrong slot. Documented in `CONTRIBUTING.md` Troubleshooting + `mihaela-agents/Rules/ai-agent-rules/testing.md`.
- **stdout line-buffered when piped**: `Cupertino.main()` calls `setvbuf(stdout, nil, _IOLBF, 0)` so `cupertino fetch ... | tee` flushes per-line instead of every 4–8 KB. No more "appears hung for 5 minutes then dumps a chunk" surprise on long crawls.
- **`fetch --type package-docs` now extracts a filtered tarball, not a single README**: `PackageArchiveExtractor` (Core actor) pulls `https://codeload.github.com/<owner>/<repo>/tar.gz/<ref>` (HEAD → main → master fallback) and extracts README, CHANGELOG, LICENSE, `Package.swift`, all of `Sources/` + `Tests/`, every `.docc` article and tutorial, `Examples/` / `Demo/` directories, plus a per-package `manifest.json`. Same on-disk layout as before (`~/.cupertino/packages/<owner>/<repo>/`), but materially richer payload. Drives this shift: 5-line stub READMEs (vapor/leaf, etc.) made the prior README-only index nearly worthless for AI-agent "how do I use X?" queries — the source itself is now the last-resort fallback.
- **`cupertino fetch --type package-docs` hidden from public help**: still functional, but no longer advertised — typical users get package data via the curated `packages.db` bundled in the `cupertino-docs` release zip. The full crawl is for re-building artifacts, not for end users.

### Fixed

- **Homebrew resource bundle lookup** (#161): now fundamentally solved because there is no bundle.
- **`fetch --type package-docs` honours user selections** (#107): `PriorityPackagesCatalog` first access copies the bundled `priority-packages.json` to `~/.cupertino/selected-packages.json` so TUI / manual edits take effect immediately.
- **Swift.org indexing drops valid pages** (#110): `metadata.json` was being decoded as a `StructuredDocumentationPage` and failing on the missing `url` key. `findDocFiles` now filters it out. Separately, `is404Page` was over-aggressive — only flips the verdict on short pages (<500 chars) for the ambiguous "page not found" phrase, so the Swift Book's "The Basics" pages discussing error handling are no longer misclassified.
- **Sample-code auth WebKit window** (#6, partial). Window now appears and navigates: `NSApp.setActivationPolicy(.regular)` nil-crash fixed (`NSApplication.shared` instead); delegate attached before `webView.load()`; spoofed Safari UA dropped (`idmsa.apple.com` was 403'ing it). `AuthFlowCoordinator` auto-detects sign-in via `myacinfo` cookie. Fresh interactive sign-in still has CoreAnimation quirks in a bare Swift CLI host; full replacement ([#193](https://github.com/mihaelamj/cupertino/issues/193), public JSON endpoints) is scoped to v1.1.
- **BM25F single-word capitalized type queries** (#181): the FTS5 index was previously column-uniform (every column weight 1.0), so Mach kernel `task_*` docs outranked the Swift `Task` struct page on a literal `Task` query. Switching to **field-weighted BM25 (BM25F)** with title 10× and AST-extracted symbols 5× now makes `Task` rank the Swift Task struct above Mach `task_info`, and `View` rank the SwiftUI View protocol above generic prose. Full case-sensitivity comes with the v1.0 re-crawl.
- **Cross-machine resume path resolution**: `FetchCommand.checkForSession()` was returning `metadata.crawlState.outputDirectory` — an absolute path captured on the machine that originally ran the crawl. After rsyncing `~/.cupertino/docs/` to a second host (different home dir, mounted volume), that saved path pointed at nothing, so `cupertino fetch` would silently start writing to a phantom directory under the wrong home. Now returns the directory where `metadata.json` was actually located — by definition the live output dir. Means a multi-day crawl can be migrated mid-run between machines via plain rsync + a `git pull` of the cupertino binary.
- **Claude Code plugin install command** (PR #173 by @gpambrozio): `marketplace.json` source corrected from `"."` to `"./"` to match working-marketplace convention; README plugin install instructions updated to use the slash-command + `owner/repo` form instead of a CLI command with a full git URL.
- **Deterministic id and contentHash for `StructuredDocumentationPage`** ([#199](https://github.com/mihaelamj/cupertino/issues/199)): `id` was a fresh `UUID()` per fetch and `contentHash` was `sha256(of: rawSourceBytes)` (Apple JSON, HTML, or markdown frontmatter — all carrying volatile cache / build / timestamp metadata that didn't reach our parsed output). Two crawls of the same Apple-side content produced different hashes, `Crawler.shouldRecrawl` always returned true, and every re-fetched page falsely registered as ♻️ Updated. Spot-checked Rotation3D and CGContext against the prior corpus — content was byte-identical after stripping volatile fields. Fix: `id` now derives from SHA-256 of the URL string (`StructuredDocumentationPage.deterministicID(for:)`); `contentHash` now hashes a canonical structured payload (`canonicalContentHash`) excluding `id`, `crawledAt`, `contentHash` itself, and `rawMarkdown` (which embeds `crawledAt`). Three transformers updated (`AppleJSONToMarkdown`, `HTMLToMarkdown`, `MarkdownToStructuredPage`). Five new regression tests in `SharedTests/ModelsTests`. Verified end-to-end: three back-to-back live fetches of `documentation/spatial/rotation3d` produced byte-identical id and contentHash, third fetch was correctly skipped. **Migration:** existing on-disk corpus carries pre-#199 hashes; the next crawl re-saves each existing page once with the canonical hash, then becomes idempotent. Subsequent ♻️ Updated counts will then map to actual Apple-side documentation edits.

**Test coverage added for v1.0 fetch / resume behavior**
- `Packages/Tests/SharedTests/JSONCodingTests.swift::concurrentWritesAreAtomic` — race a writer against 8 concurrent readers on a 256 KB file. Without `.atomic`, readers observe `Unexpected end of file` decode errors; with `.atomic`, 1,600 reads × 200 writes are all clean. Verified to fail when `.atomic` is removed.
- `Packages/Tests/CLICommandTests/FetchTests/ResumeTests.swift` — 11 tests covering: `--start-clean` no-op when no metadata exists; `--start-clean` wipes `crawlState` while preserving stats; `--start-clean` leaves valid JSON and is idempotent; fresh `CrawlerState` auto-loads an active session; fresh `CrawlerState` reports no session when `crawlState` is absent; `--start-clean` + reload produces no active session; save → reload via fresh instance round-trips; `checkForSession` returns the *found* directory not the saved path (cross-machine portability); `checkForSession` rejects start-URL mismatch / inactive sessions / missing metadata; `checkForSession` ignores even a coincidentally-existing foreign path. Two of these were proven to fail under deliberate sabotage of the corresponding code path.

### Removed

- `cupertino setup --force` flag — use `--keep-existing` or the new default-downloads behaviour.
- `cupertino packages-setup` (hidden) subcommand — collapsed into the unified `cupertino setup`.
- `cupertino fetch --use-json-api` flag — was never read by the Crawler (per-URL JSON-then-WebView fallback was always unconditional). Dead config; removing it deletes the `useJSONAPI` field from `Shared.CrawlerConfiguration`.
- `cupertino fetch --resume` flag — auto-resume is the default now. The flag was a log-message switch only, doing nothing functional.
- `FetchCommand.runDocsTwoPassCrawl()` — ran the same crawler twice (force-fresh, then resume-and-find-nothing). The "two-pass" branding was misleading; the per-URL fallback already gave full coverage in one pass.
- `Cupertino_Resources.bundle` shipped artifact — no longer generated, no longer copied by `install.sh` / `release.yml` / the Homebrew formula.
- `SwiftPackagesCatalog.topPackages(limit:)`, `.activePackages(minStars:)`, `.packages(license:)` — relied on metadata fields no longer present on the slimmed URL-only catalog. Metadata-driven queries will come back via `packages.db`.

### Internal

- `Search.DocKind`, `Search.Classify`, `Search.SmartCandidate`, `Search.CandidateFetcher`, `Search.SmartQuery`, `Search.PackageFTSCandidateFetcher`, `Search.DocsSourceCandidateFetcher`, `Search.FusedCandidate`, `Search.SmartResult` — new public surfaces under `Packages/Sources/Search/`.
- `MCP.Icon` + `Implementation.icons` — protocol-level additions for 2025-11-25.
- `CupertinoIconEmbedded.dataURI` for serverInfo advertising.
- `CLI.Commands.AskCommand`, `CLI.Commands.PackagesReleaseURL`, `CLI.Commands.SetupCommand.SetupStatus` — new CLI internals.
- **Test count: 961** in 96 suites, 0 failures, ~40s on clean build. New suites added during this release cycle: `DocKindTests` (19), `DocKindIntegrationTests` (13), `BM25TitleWeightingTests`, `CodeExampleSymbolsTests`, `IndexBuilderSymbolsIntegrationTests`, `SmartQueryTests`, `DocsSourceCandidateFetcherTests`, `CupertinoResourcesTests`, `PackagesReleaseURLTests`, `SwiftEvolutionCrawlerTests` (#178), `ResumeAndStartCleanTests` (11 cases covering auto-resume, `--start-clean`, and cross-machine `checkForSession` portability). Updated: MCP protocol tests for 2025-11-25 + Icon + Implementation icons + legacy decode, schema-version assertions to 12, BM25 tests to 8-weight vector, doctor schema-version helpers, CLI subcommand count, `JSONCodingTests.concurrentWritesAreAtomic` (regression test for atomic metadata save).
- `scripts/generate-embedded-catalogs.sh` — regenerates embedded catalog Swift files.
- `scripts/recrawl.sh` — full re-crawl orchestration, named phases, idempotent wipe.
- `scripts/demo.sh` — single-run live presentation script for demo recordings (no slides, just the binary).
- **`mock-ai-agent` polish**: stdout now streams via `bytes.lines` for ordered delivery (previously buffered, so AI-like back-and-forth printed out of sequence on slow stdin), UTF-8 chunk truncation that could split a multi-byte glyph mid-character is fixed, and a new `--quiet` mode hides protocol noise for clean demo recordings.
- 6 GitHub issues closed (`#18` colors, `#20` E2E MCP tests, `#109` search-all/search-hig — all already done or superseded). 3 v1.0-deliverable labels (`v1.0: distribution`, `v1.0: symbols`, `v1.0: mcp`) + `wishlist` label applied to ~20 speculative pre-v1.0 issues.

### Known issues / deferred

- **Sample-code auth WebKit** (#6 partial; full replacement #193) — fresh interactive sign-in still has CA rendering quirks in the bare Swift CLI host. v1.1 swaps to public JSON endpoints; for v1.0 use the existing macOS user session if it has signed in via Safari recently.
- **MCP `search` tool sectioned-vs-blended split** — MCP clients still get the per-source `UnifiedSearchService` shape (good for human-readable chat); only the new `cupertino ask` CLI uses cross-source rank fusion. Unifying these two presentations behind `SmartQuery` is a v1.1 polish.
- **G6 Tasks abstraction** for long-running operations not wired — re-crawl + full-index run synchronously without MCP Tasks-protocol progress reporting. Defaults are fine; v1.1 polish.
- **#177 low-signal AST symbol filtering** — operators, boilerplate names show up in symbol search. Quality-of-life cleanup post-1.0.

---

## 0.9.1 (2026-01-25)

### Added
- **MCP client configuration docs** - Added setup guides for multiple AI tools (#134, #137)
  - OpenAI Codex (CLI and ~/.codex/config.toml)
  - Cursor (.cursor/mcp.json)
  - VS Code with GitHub Copilot (.vscode/mcp.json)
  - Zed (settings.json)
  - Windsurf (~/.codeium/windsurf/mcp_config.json)
  - opencode (opencode.jsonc)
- **Binary documentation** - Full docs for additional executables (#137)
  - cupertino-tui: Terminal UI with 5 views documented
  - mock-ai-agent: MCP testing tool with arguments documented
  - cupertino-rel: Release tool with 6 subcommands and all options
  - 48 new documentation files in docs/binaries/
- **mock-ai-agent --version** - Added version flag support (#137)

---

## 0.10.0 (2026-03-13)

### Added
- Framework synonyms: search using common alternate names (e.g., "nfc" → CoreNFC, "bluetooth" → CoreBluetooth, "shareplay" → GroupActivities)
- Seed framework discovery from Apple's technologies.json for complete coverage
- Agent skill for stateless CLI usage (#167, thanks @tijs)
- Database v0.9.0: 320,771 documents across 443 frameworks (+18k docs, +136 frameworks)

### Changed
- Case-insensitive framework matching across all search functions
- Reduced default request delay from 0.5s to 0.05s for faster crawling

### Fixed
- Crawler session resume now validates startURL before resuming
- Case-insensitive URL prefix matching in shouldVisit
- Link enqueue before skip check — incremental re-crawls now discover new child pages
- Case-insensitive framework queries in searchByKind and searchSampleCode

## 0.9.0 (2025-12-31)

### Changed
- **MCP Protocol Upgrade** - Support 2025-06-18 with backward compatibility (#130)
  - Upgraded default protocol version from 2024-11-05 to 2025-06-18
  - Server negotiates compatible version with clients
  - MCPClient and MockAIAgent support version fallback
  - Thanks to @erikmackinnon for the contribution

---

## 0.8.3 (2025-12-31)

### Changed
- **Swift-only MCP integration tests** - Rewrote tests and removed Node.js dependency (#131)
  - New integration tests use `cupertino serve` instead of npm packages
  - Tests verify MCP initialize handshake and tools/list responses
  - Validates protocol version, server info, and tool registration
  - Added Language Policy to AGENTS.md: no Node.js/npm in codebase

---

## 0.8.2 (2025-12-31)

### Fixed
- **Setup progress animation** - Show download and extraction progress (#96)
  - Added `DownloadProgressDelegate` for real-time download progress
  - Added `ExtractionSpinner` for extraction feedback
  - Extended download timeout to 10 minutes for large database files

---

## 0.8.1 (2025-12-28)

### Fixed
- **Installer ANSI escape sequences** - Fix raw `\033[...]` text in summary (#124)
  - Two `echo` statements missing `-e` flag for color output
  - Affects `bash <(curl ...)` install method

---

## 0.8.0 (2025-12-20)

### Added
- **Doctor Command Enhanced** - Package diagnostics (#81)
  - Shows user selections file status and package count
  - Shows downloaded README count
  - Warns about orphaned READMEs (packages no longer selected)
  - Displays priority package breakdown (Apple vs ecosystem)
- **String Formatter Tests** - 34 unit tests for display formatting (#81)
  - `StringFormatterTests.swift` covers truncation, markdown escaping, camelCase splitting

### Changed
- **Code Quality Improvements** (#81)
  - Consolidated magic numbers into `Shared.Constants` (timeouts, delays, limits, intervals)
  - Added `Timeout`, `Delay`, `Limit`, `Interval` namespaces for better organization
  - Replaced hardcoded values across WKWebCrawler, HIGCrawler, and other modules
- **PriorityPackagesCatalog** - Made fields optional for TUI compatibility
  - `appleOfficial` tier now optional (TUI only saves ecosystem tier)
  - Stats fields `totalCriticalApplePackages` and `totalEcosystemPackages` now optional
- **Search Result Formatting** (#81)
  - Hierarchical result numbering (1.1, 1.2, 2.1, etc.)
  - Source counts in headers: `## 1. Apple Documentation (20) 📚`
  - Renamed `md` variable to `output` in formatters for clarity

### Fixed
- **Package-docs fetch now reads user selections** (#107)
  - `cupertino fetch --type package-docs` now loads from `~/.cupertino/selected-packages.json`
  - Falls back to bundled `priority-packages.json` if user file doesn't exist
  - TUI package selections are now respected by fetch command
- **Display Formatting Bugs** (#81)
  - Double space artifacts ("Tab  bars" → "Tab bars")
  - Smart title-casing (only lowercase first letters get uppercased)
  - SwiftLint violations (line length, identifier names)

### Related Issues
- Closes #81, #107

---

## 0.7.0 (2025-12-15)

### Added
- **Unified Search with Source Parameter**
  - New `--source` parameter: `apple-docs`, `samples`, `hig`, `apple-archive`, `swift-evolution`, `swift-org`, `swift-book`, `packages`, `all`
  - Teasers show results from alternate sources in every search response
  - Source-aware messaging tells AI exactly what was searched
- **Documentation Database Expanded** - 302,424 docs across 307 frameworks (up from 234k/287)

### Changed
- Consolidated multiple search tools into one unified search tool
- Shared formatters between MCP and CLI for consistent output
- Shared TeaserFormatter and constants eliminate hardcoding

---

## 0.6.0 (2025-12-12)

### Added
- **Platform Availability Support** (#99)
  - `cupertino fetch --type availability` - Fetch platform version data for all docs
  - Availability tracked for all sources: apple-docs, sample-code, archive, swift-evolution, swift-book, hig
  - Search filtering by `--min-ios`, `--min-macos`, `--min-tvos`, `--min-watchos`, `--min-visionos` (CLI and MCP `search_docs` tool)
  - `save` command now warns if docs don't have availability data
  - Schema v7: availability columns in docs_metadata and sample_code_metadata

### Availability Sources
| Source | Strategy |
|--------|----------|
| apple-docs | API fetch + fallbacks |
| sample-code | Derives from framework |
| apple-archive | Derives from framework |
| swift-evolution | Swift version mapping |
| swift-book/hig | Universal (all platforms) |

### Documentation
- Added `docs/commands/search/option (--)/min-ios.md`
- Added `docs/commands/search/option (--)/min-macos.md`
- Added `docs/commands/search/option (--)/min-tvos.md`
- Added `docs/commands/search/option (--)/min-watchos.md`
- Added `docs/commands/search/option (--)/min-visionos.md`
- Updated search command docs with availability filtering options

### Related Issues
- Closes #99

---

## 0.5.0 (2025-12-11)

**Why minor bump?** The `cupertino release` command was removed from the public CLI. Users who had scripts calling `cupertino release` will need to update them. This is a breaking change for maintainer workflows.

### Added
- **Documentation Database Expanded** - 234,331 pages across 287 frameworks (up from 138k/263)
  - Kernel: 24,747 docs
  - Matter: 22,013 docs
  - Swift: 17,466 docs
  - Full deep crawl of Apple Developer Documentation
- **New ReleaseTool Package** - Maintainer-only release automation (#98)
  - `cupertino-rel bump` - Update version in all files
  - `cupertino-rel tag` - Create and push git tags
  - `cupertino-rel databases` - Upload databases to cupertino-docs
  - `cupertino-rel homebrew` - Update Homebrew formula
  - `cupertino-rel docs-update` - Documentation-only releases
  - `cupertino-rel full` - Complete release workflow

### Changed
- **Breaking:** `cupertino release` removed from CLI - maintainers now use separate `cupertino-rel` executable
- README now shows accurate documentation counts

### Fixed
- Flaky ArchiveGuideCatalog tests (#101)

### Documentation
- Updated `docs/DEPLOYMENT.md` with automated release instructions
- Added `Packages/Sources/ReleaseTool/README.md`

### Related Issues
- Closes #98, #101

---

## 0.4.0 (2025-12-09)

### Added
- **HIG Support** - Human Interface Guidelines documentation (#95)
  - `cupertino fetch --type hig` - Fetch HIG documentation
  - New HIG source for search results

### Fixed
- Swift.org indexer now handles JSON files correctly

### Documentation
- Added video demo
- Added MIT License
- Added Homebrew tap info to README

### Related Issues
- Closes #95

---

## 0.3.4

### Added
- **One-Command Install** - Single curl command installs everything (#82)
  - `bash <(curl -sSL .../install.sh)` - Downloads binary and databases
  - Pre-built universal binary (arm64 + x86_64)
  - Code signed with Developer ID Application certificate
  - Notarized with Apple for Gatekeeper approval
  - GitHub Actions workflow for automated releases
- Closes #79, #82

---

## 0.3.0

### Added
- **Setup Command** - Instant database download from GitHub Releases (#65)
  - `cupertino setup` - Download pre-built databases in ~30 seconds
  - Version parity - CLI version matches release tag for schema compatibility
  - Progress bar with percentage and download size
  - `--base-dir` option for custom location
  - `--force` flag to re-download
- **Release Command** - Automated database publishing for maintainers (#66)
  - `cupertino release` - Package and upload databases to GitHub Releases
  - Creates versioned zip with SHA256 checksum
  - `--dry-run` for local testing
  - Handles existing releases (deletes and recreates)
- **Remote Sync** - New `--remote` flag for `cupertino save` command (#52)
  - Stream documentation directly from GitHub without local crawling
  - Build database locally in ~45 minutes instead of 20+ hours
  - Resumable - if interrupted, continue from where you left off
  - No disk bloat - streams directly to SQLite
  - Uses raw.githubusercontent.com (no API rate limits)
- **RemoteSync Package** - New standalone Swift 6 package with strict concurrency
  - `RemoteIndexer` actor for orchestrating remote sync
  - `GitHubFetcher` actor for HTTP operations
  - `RemoteIndexState` Sendable struct for state persistence
  - `AnimatedProgress` for terminal progress display

### Documentation
- Updated README with "Instant Setup" quick start using `cupertino setup`
- Added `docs/commands/setup/README.md` documentation
- Added `docs/commands/release/README.md` documentation
- Added `docs/commands/save/option (--)/remote/` documentation
- Updated `docs/commands/README.md` with new commands

### Related Issues
- Closes #52, #65, #66

---

## 0.2.7

### Fixed
- **Search Ranking** - Penalize release notes in search results (2.5x multiplier) to prevent them polluting unrelated queries (#57)
- **Swift Evolution Indexing** - Fix filename pattern to match `SE-0001.md` format (#61)
- **Database Re-indexing** - Delete database before re-index to prevent FTS5 duplicate rows doubling db size (#62)
- **Serve Output** - Simplified startup messages to show only DB paths; server now requires at least one database to start (#60)

---

## 0.2.6

### Fixed
- **MCP Server Tool Registration** - Fixed bug where only sample code tools were exposed (#55)
  - Created `CompositeToolProvider` that delegates to both `DocumentationToolProvider` and `SampleCodeToolProvider`
  - All 7 MCP tools now properly exposed: `search_docs`, `list_frameworks`, `read_document`, `search_samples`, `list_samples`, `read_sample`, `read_sample_file`
  - Follows composite pattern with proper separation of concerns

### Related Issues
- Fixes #55

---

## 0.2.5

### Added
- **CLI Sample Code Commands** - Full parity with MCP sample code tools (#51)
  - `cupertino list-samples` - List indexed sample projects
  - `cupertino search-samples <query>` - Search sample code projects and files
  - `cupertino read-sample <project-id>` - Read project README and metadata
  - `cupertino read-sample-file <project-id> <path>` - Read source file content
- **CLI Framework List Command**
  - `cupertino list-frameworks` - List available frameworks with document counts
- All new commands support `--format text|json|markdown` output

### Related Issues
- Closes #51

---

## 0.2.4

### Added
- **GitHub Sample Code Fetcher** - Fast alternative to Apple website scraping
  - `cupertino fetch --type samples` - Clone/pull from public GitHub repository
  - 606 projects, ~10GB with Git LFS
  - Much faster than `--type code` (~4 minutes vs hours)
- **Sample Code Directory Indexing** - Index extracted project directories (not just ZIPs)
  - `SampleIndexBuilder` now scans both ZIP files and extracted folders
  - Supports GitHub-cloned projects in `cupertino-sample-code/` subdirectory
  - 18,000+ source files indexed for full-text search

### Changed
- Sample code can now be fetched from two sources:
  - `--type samples` - GitHub (recommended, faster)
  - `--type code` - Apple website (requires authentication)

---

## 0.2.3

### Added
- **Apple Archive Documentation Crawler** - Crawl legacy Apple programming guides (Core Animation, Core Graphics, Core Text, etc.) (#41)
- `cupertino fetch --type archive` - Fetch archived Apple programming guides
- `--include-archive` flag for search command - Include legacy guides in results
- `include_archive` parameter for MCP `search_docs` tool
- Framework synonyms for better search (QuartzCore↔CoreAnimation, CoreGraphics↔Quartz2D)
- Source-based search ranking (modern docs rank higher, archive docs have slight penalty)
- TUI Archive view for browsing and selecting archive guides

### Changed
- Archive documentation excluded from search by default (use `--include-archive` or `--source apple-archive`)
- Updated MCP tool description to document archive features

### Related Issues
- Closes #41

---

## 0.2.2

### Added
- Intelligent kind inference for unknown document types using URL depth, title patterns, and word count signals
- Improved search ranking for core types when `kind=unknown`

### Fixed
- Fixed URL scheme error when resuming crawl session (#47)

### Related Issues
- Closes #47
- Related to #28 (Search Ranking Improvements)

---

## 0.2.1

### Fixed
- Fixed crawler filename collision causing parent documentation pages to be overwritten by operators/methods (#45)
- Crawler now generates unique filenames for URLs with special characters using hash suffixes
- Parent types (Text, Color, Date, String structs) will be restored on next crawl

### Related Issues
- Closes #45
- Related to #28 (Search Ranking Improvements)

---

## 0.2.0

### Fixed
- **CRITICAL**: Fixed cleanup bug that deleted source code instead of .git folders (#40)
- Simplified `compressDirectory()` to preserve Apple's flat ZIP structure
- Reduced cleanup patterns to only safe items: .git, .DS_Store, DerivedData, build, .build, xcuserdata, *.xcuserstate
- Verified all 606/607 sample ZIPs contain intact source code (1 corrupted in original download)
- Cleanup now achieves 44% space reduction (27GB → 15GB) while preserving all code

---

## 0.1.9

### Added
- `--language` filter for search (swift, objc) - CLI and MCP (#34)
- `source` parameter to MCP `search_docs` tool (#38)

### Changed
- Database schema v5 - added `language` column to docs_fts and docs_metadata
- **BREAKING**: Requires database rebuild (`rm ~/.cupertino/search.db && cupertino save`)

---

## 0.1.8

### Added
- `cupertino cleanup` - Clean up sample code archives by removing .git, .DS_Store, xcuserdata, etc. (#31)
- Dry run mode (`--dry-run`) to preview cleanup without modifying files
- Keep originals mode (`--keep-originals`) to preserve original ZIPs

### Changed
- Reorganized docs folder structure to be self-illustrating (folders show command syntax)
- Removed unused serve command options (`--docs-dir`, `--evolution-dir`, `--search-db`)

### Fixed
- Dry run now correctly detects nested junk files (e.g., `.git/hooks/*`)

---

## 0.1.7

### Added
- Unified logging system with categories and log levels (#26, #30)
- Search tests for swift-book URIs

### Fixed
- `read_document` returning empty content for swift-book URIs
- Consolidated logging across all modules

---

## 0.1.6

### Added
- `cupertino search` - CLI command for searching documentation without MCP server (#23)
- `cupertino read` - CLI command for reading full documents by URI
- `summaryTruncated` field in search results for AI agents
- Truncation indicator with word count in text output
- Comprehensive command documentation in `docs/commands/`

### Changed
- Increased summary limit from 500 to 1500 characters
- JSON-first crawling to reduce WKWebView memory usage (#25)

### Fixed
- Memory spike on large index pages by using JSON API first (#25)

---

## 0.1.0 — Pre-release

- Initial crawler prototype (`Crawler`)
- Local MCP server implemented (`Serve`)
- Admin TUI added (`AdminUI`)
- Documentation system connected
- Pre-release versioning strategy established
- Internal architecture stabilized enough for developer preview

