## Unreleased (develop)

_Post-1.0 fixes accumulating on the `develop` branch, off `packages-overhaul`. Will roll into a future patch release after 1.0.0 ships. Out of scope for the 1.0.0 cut so the release theme stays clean._

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

## 1.0.0 "First Light" — unreleased

_The first release we'd call properly stable. Consolidates what was originally scoped as v0.11.0 (packages-overhaul) + v0.12.0 (docs-overhaul) into a single cut. Release plan: [#192](https://github.com/mihaelamj/cupertino/issues/192). Canonical roadmap: [#183](https://github.com/mihaelamj/cupertino/issues/183). **Code-side complete on `packages-overhaul` (final hardening: crawl resume model + cross-machine portability landed 2026-04-25); awaiting full re-crawl + companion-repo artifact publishing (#192 section I) before tag.**_

### Added

**Search quality — symbol-aware FTS (#192 sections C + D, subsumes #176)**
- `Search.DocKind` taxonomy: 10-case enum (`symbolPage`, `article`, `tutorial`, `sampleCode`, `evolutionProposal`, `swiftBook`, `swiftOrgDoc`, `hig`, `archive`, `unknown`) populated at index time by `Search.Classify.kind(source:structuredKind:uriPath:)` — a pure deterministic function. Stored in new `docs_metadata.kind` column.
- `docs_metadata.symbols` denormalized blob + `docs_fts.symbols` FTS column. Both populated by an AST pass (`SwiftSourceExtractor` over both code-block content AND declaration lines) so a query like `Task` ranks the Swift `Task` struct page above prose mentions of the word "task". `bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0)` — title dominates (10×), symbols next (5×), summary (3×), framework (2×).
- `idx_kind` index for per-kind routing queries.
- `Search.Index.extractCodeExampleSymbols` + `recomputeSymbolsBlob` (private) — a single source of truth that reads `doc_symbols` and writes both denormalized columns, so declaration-derived and code-block-derived symbols flow into ranking uniformly.

**Smart query wrapper — `cupertino ask` (#192 section E)**
- Public-facing CLI: `cupertino ask "<question>"` runs the question across every available source (apple-docs, apple-archive, hig, swift-evolution, swift-org, swift-book, packages) in parallel and returns a fused top-N. No `--source` flag needed.
- `Search.SmartCandidate` source-agnostic result struct. `Search.CandidateFetcher` protocol with one method, `fetch(question:limit:)`, per source. Concrete impls: `PackageFTSCandidateFetcher` (wraps `Search.PackageQuery.answer`), `DocsSourceCandidateFetcher` (wraps `Search.Index.search` for any apple-docs-style source).
- `Search.SmartQuery` fans fetchers out via `TaskGroup`, fuses per-source rankings via reciprocal rank fusion (k=60, the Cormack/Clarke/Büttcher default). Failing fetchers collapse to empty — one dead DB never takes the whole query down. Per-fetcher limit caps noisy sources before fusion so a verbose source can't drown out a strong single hit.
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
- `packages.db` row counts (packages, package_files) + bundled `packagesIndexVersion` for at-a-glance install verification.

**Distribution + packaging (#192 section B)**
- Companion repo [mihaelamj/cupertino-packages](https://github.com/mihaelamj/cupertino-packages) ships `packages.db` artifacts. First release lands with v1.0.0.
- `cupertino setup` is now the **single command** that owns every database. Downloads search.db + samples.db from `cupertino-docs`, then packages.db from `cupertino-packages`. No granularity flag — the previous `cupertino packages-setup` is removed; URL helpers preserved as `PackagesReleaseURL` for tests. Best-effort on the packages download: if the cupertino-packages release isn't tagged yet, setup logs a warning and still completes (cupertino can serve docs without packages.db).
- `Shared.Constants.App.packagesIndexVersion` + `packagesReleaseBaseURL` + `docsReleaseBaseURL` constants.

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
- **`cupertino fetch --type package-docs` hidden from public help**: still functional, but no longer advertised — typical users get package data via the curated `packages.db` from the cupertino-packages release. The full crawl is for re-building artifacts, not for end users.

### Fixed

- **Homebrew resource bundle lookup** (#161): now fundamentally solved because there is no bundle.
- **`fetch --type package-docs` honours user selections** (#107): `PriorityPackagesCatalog` first access copies the bundled `priority-packages.json` to `~/.cupertino/selected-packages.json` so TUI / manual edits take effect immediately.
- **Swift.org indexing drops valid pages** (#110): `metadata.json` was being decoded as a `StructuredDocumentationPage` and failing on the missing `url` key. `findDocFiles` now filters it out. Separately, `is404Page` was over-aggressive — only flips the verdict on short pages (<500 chars) for the ambiguous "page not found" phrase, so the Swift Book's "The Basics" pages discussing error handling are no longer misclassified.
- **Sample-code auth WebKit window** (#6, partial). Window now appears and navigates: `NSApp.setActivationPolicy(.regular)` nil-crash fixed (`NSApplication.shared` instead); delegate attached before `webView.load()`; spoofed Safari UA dropped (`idmsa.apple.com` was 403'ing it). `AuthFlowCoordinator` auto-detects sign-in via `myacinfo` cookie. Fresh interactive sign-in still has CoreAnimation quirks in a bare Swift CLI host; full replacement ([#193](https://github.com/mihaelamj/cupertino/issues/193), public JSON endpoints) is scoped to v1.1.
- **bm25 single-word capitalized type queries** (#181): title weight 10×, symbols weight 5× now make `Task` rank the Swift Task struct above Mach `task_info`, and `View` rank the SwiftUI View protocol above generic prose. Full case-sensitivity comes with the v1.0 re-crawl.
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

