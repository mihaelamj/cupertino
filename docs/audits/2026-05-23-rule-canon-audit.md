# Rule-canon audit, 2026-05-23

Two passes ran against `develop @ 2607df6`:

- **Pass 1** (standard): grep-and-execute the documented acceptance checks in every `mihaela-agents/Rules/swift/*.md` + `Rules/universal/*.md` file.
- **Pass 2** (deep): re-run pass 1 from scratch + 12 original investigations beyond the documented checks (mutable static state, runtime concrete casts, Models-tier behaviour creep, TODO/FIXME census, producer reach-ins into the TaskLocal composition, single-file invariant on the new Strategy / Pass SPM siblings, contract-doc row coverage vs declared targets, cross-producer imports through STRICT_PRODUCERS that are not in the foundation-tier whitelist).

Today's context: 14 PRs merged to `develop` (bug fixes #955 #959 #960; CLI features for #948 phases 1-5 via #961 #963 #964; pluggability refactors for #905 via #966, for #899 strategy split via #967-972, for #906 sub-PR B via #973). Develop test baseline 2496 / 373 suites passing.

Cupertino DB stats at audit time: 420 frameworks, 352,712 documents, 108,536 sample symbols, schema v18 (above all configured floors).

## Mechanical checks: all green

| Check | Script / source | Result |
|---|---|---|
| Package purity | `scripts/check-package-purity.sh` | exit 0 |
| Foundation-only producers | `scripts/check-target-foundation-only.sh` | exit 0, 41 producers strict |
| Standalone portability for the just-extracted `AppleConstraintsPass` (#973) | `scripts/check-target-portability.sh AppleConstraintsPass` | exit 0 |
| `docs/commands/` vs binary `--help` | `scripts/check-docs-commands-drift.sh` | exit 0, 19 commands checked, 0 drift |
| Canonical literals exclusivity | `scripts/check-canonical-literals.sh` | exit 0 |
| Canonical DB shape | `scripts/check-canonical-db-shape.sh` | exit 0 |
| CHANGELOG touched on every code-touching PR | `scripts/check-changelog-touched.sh` | exit 0 |
| Build | `xcrun swift build --package-path Packages` | exit 0 |
| Tests | `xcrun swift test --package-path Packages` | exit 0, 2496 / 373 |
| No GitLab remote | `git remote -v` | only `github.com` |
| Pages config present | `docs/CNAME` + `docs/.nojekyll` | both present |
| Namespace migration complete (no `struct Shared {}` / `class Shared {}` per `namespacing.md`) | repo grep | empty |
| No closure typealiases at cross-target seams (Rule 4) | repo grep `public typealias.*= @Sendable.*->` | empty |
| No Singletons (`static let shared` outside `os.Logger` / Apple statics) (Rule 1) | repo grep | empty in producer targets (the historical `BinaryConfig.shared` ban holds) |
| No runtime concrete casts (Rule 3) | grep `as? Search\.Index\|as! Search\.Index` | empty |
| Models tier carries no `class` / `actor` (per-package-import-contract.md §29) | grep across all 13 `*Models` dirs | empty |
| `*Models` protocols are uniformly `Sendable` | grep | uniform |
| Each new strategy SPM sibling has exactly one Swift file (acceptance for #899) | `ls Packages/Sources/{AppleDocsStrategy,HIGStrategy,SampleCodeStrategy,SwiftEvolutionStrategy,SwiftOrgStrategy,AppleArchiveStrategy,AppleConstraintsPass}` | each contains exactly 1 file |
| Producer reach-ins into TaskLocal composition (Rule 1 "Service Locator") | grep `Cupertino.Context.composition` outside `Sources/CLI/` | empty |
| TODO / FIXME census | grep `// TODO\|// FIXME` | 1 entry (`SearchSQLite/Search.Index.QueryParsing.swift:23`, scoped to #81) |
| Em-dashes added in the queued 14-PR batch | `git log -p origin/main..origin/develop \| grep '^+' \| grep '—'` | 0 |

## Findings

### HIGH-1: three files violate one-non-private-type-per-file (code-style.md §352)

The acceptance block embedded in `code-style.md` states "Output MUST be empty" for the per-file type-count grep. Running it produces:

```
8 Packages/Sources/CLI/SearchModuleAlias.swift
3 Packages/Sources/EnrichmentModels/EnrichmentModels.swift
2 Packages/Sources/AvailabilityFoundationNetworking/LiveAvailabilityNetworking.swift
```

Details:

- `Packages/Sources/CLI/SearchModuleAlias.swift` (lines 53 / 81 / 102 / 118 / 142 / 155 / 181 / 212): 8 `Live*` factory / strategy structs in one file. CLI is the composition root and is the most legitimate place for multiple `Live*` concretes; even so, the rule is mechanical.
- `Packages/Sources/EnrichmentModels/EnrichmentModels.swift` (lines 14 / 58 / 72): namespace anchor `enum EnrichmentModels`, `protocol EnrichmentRunner`, `protocol EnrichmentPass` all in one file. Pre-existing.
- `Packages/Sources/AvailabilityFoundationNetworking/LiveAvailabilityNetworking.swift` (lines 17 / 43): `LiveAvailabilityNetworking` + `LiveAvailabilityNetworkingFactory`. Authored today as part of PR #966 for #905.

Fix shape: split each non-private declaration into its own file under the same target. The PR #966 file is the freshest mistake.

### HIGH-2: `docs/package-import-contract.md` is 9 rows behind the actual declared SPM targets (8 production + `TestSupport`)

The contract is described in `per-package-import-contract.md` as "the single source of truth a reviewer can grep against" but there is no CI script enforcing row coverage today, so drift is silent.

Cross-referencing declared targets in `Packages/Package.swift` against contract rows:

```
AppleArchiveStrategy
AppleConstraintsPass
HIGStrategy
MCPClient
SampleCodeStrategy
SampleIndexSQLite
SwiftEvolutionStrategy
SwiftOrgStrategy
```

Six of the eight production targets landed today (#967-#972 + #973). `MCPClient` + `SampleIndexSQLite` are older drift. A ninth target, `TestSupport`, is also missing from the contract but is defensibly out of scope as a test-only helper target; the contract should note the exclusion explicitly rather than letting it drop silently.

Fix shape: add 8 contract rows in one follow-up PR, then ship a `scripts/check-import-contract-coverage.sh` that diffs `Package.swift` target names against the contract doc and fails CI on missing rows. This drift class is a structural risk; adding the script forecloses it.

### MED-1: `RemoteSync.IndexState` (Models tier) performs filesystem IO

`per-package-import-contract.md §29` describes the Models tier as "DTO shape, no IO". `Packages/Sources/RemoteSyncModels/RemoteSync.IndexState.swift` has four static methods on the value type that perform direct filesystem IO:

- `load(from: URL) throws -> IndexState` (line 159 to 164): reads the file
- `exists(at: URL) -> Bool` (line 167 to 169): `FileManager.default.fileExists`
- `delete(at: URL) throws` (line 172 to 176): `FileManager.default.removeItem`
- `save(...)` (line 155): writes the file

`RemoteSyncModels` is in the foundation-only allow-list (no FileManager forbidden there because Foundation is always allowed), so `check-target-foundation-only.sh` passes; but the spirit of the rule is breached. Grandfathered in pre-strict-DI.

Fix shape: move `save` / `load` / `exists` / `delete` to a new `RemoteSync.IndexStateStore` actor in the `RemoteSync` producer target; the codable value stays in `RemoteSyncModels`. Tracking item for the #893 epic.

### MED-2: 11 open issues missing a `kind:` label (`github-discipline.md` five-axis taxonomy)

`scripts/check-issue-body-staleness.sh` exits 1 with section "Label drift (check 5)". Open issues without `enhancement` / `bug` / `epic`:

```
#965, #962, #957, #956, #954, #953, #952, #949, #948, #943, #930
```

Three of these (#952, #953, #956) close automatically when develop FF-pushes to main on the next release-promote because the closing PRs targeted develop, not main.

Fix shape: one-pass `gh issue edit <n> --add-label "kind:<X>"` sweep. Five-minute chore.

### LOW-1: `TUI/Models/AppState.swift` declares a `final class` inside a folder named `Models/`

`Packages/Sources/TUI/Models/AppState.swift:11` declares `final class AppState`. The TUI executable target is allowed reference types because it is a composition root, not a Models target. The naming is cosmetic friction: the `Models/` subfolder inside TUI invites confusion with the foundation-only `*Models` SPM targets (per `per-package-import-contract.md §29` "Models tier carries only protocols + value types").

Fix shape: rename `TUI/Models/` to `TUI/State/` or move `AppState.swift` to `TUI/Infrastructure/`. Cosmetic only; no behaviour change.

### LOW-2: `Logging` writer target imports `SearchSchema`

`SearchSchema` is in `STRICT_PRODUCERS` per `check-target-foundation-only.sh` line 184; it carries the search.db DDL constants + the `Search.Schema.currentVersion: Int32` integer. `Logging` imports it (via `grep -rh "^import " Packages/Sources/Logging/`). Two clean readings:

- (a) `SearchSchema` is purely declarative (SQL string constants + an Int32) and should be promoted to the foundation-tier whitelist in `per-package-import-contract.md §13`. That promotion would un-flag this import.
- (b) `Logging` shouldn't reach across to search-schema concerns; the cross-target import is a real coupling that should be inverted (the schema-version producer publishes a Sendable struct that `Logging` consumes via a typed dependency, not by importing the producer module).

Fix shape: decide (a) vs (b) in the closing audit for `#893` (`#907`).

### HIGH-3: `Services.Formatter.Config.shared` is a Service Locator violation (Rule 1)

Pass 1 flagged this and pass 2 second-guessed it via a "value-type default" carve-out. The critic on this doc forced a re-read of `gof-di-rules.md §1` and the source. Rule 1 carve-outs are exactly two: (a) Apple's `os.Logger` per-category statics; (b) `private static let cache = Cache()` memoization inside a static enum loader, not reachable from consumers. `Services.Formatter.Config.shared` matches neither. Rule 1 §11 says: "No 'but this case is GoF-sanctioned' soft framing. When tempted to document a Singleton as legitimate per p. 127, stop. Do the refactor." The "value-type default carve-out" pass 2 invoked is exactly the soft framing the rule forbids.

Source: `Packages/Sources/ServicesModels/Services.Formatter.Config.swift:32` declares `public static let shared = Config(...)` and lines 42 + 45 alias it as `cliDefault` / `mcpDefault`. Consumers reach into it as a Service Locator:

- `Packages/Sources/SearchToolProvider/CompositeToolProvider.swift:758,926,965,1037` (parameter defaults)
- `Packages/Sources/CLI/Commands/CLIImpl.Command.Search.SourceRunners.swift:86,244` (parameter defaults)

Six live consumer sites reach into the static as a default. That is exactly the `Shared.Constants.defaultBaseDirectory`-style accessor that Rule 1 §10 names as forbidden.

Fix shape: drop the static, thread `Config` through the call graph from `CLI/Cupertino.swift` (composition root) into every consumer. Trickle-down via init injection. Approximately 8 file edits.

### MED-3: 7 producer-tier types use `@unchecked Sendable` without the `concurrency.md §24` justification comment

`concurrency.md §24` requires every `@unchecked Sendable` or `nonisolated(unsafe)` use to carry a one-line comment explaining why it's safe. Today these producer files use the escape hatch without that justification:

- `Packages/Sources/Core/HTMLParser/Core.Parser.XML.swift`
- `Packages/Sources/Core/HTMLParser/Core.Parser.HTML.swift`
- `Packages/Sources/Core/JSONParser/Core.JSONParser.AppleJSONToMarkdown.swift`
- `Packages/Sources/Core/JSONParser/Core.JSONParser.Engine.swift`
- `Packages/Sources/Core/JSONParser/Core.JSONParser.ContentFetcher.swift`
- `Packages/Sources/Search/Search.ComposableResult.swift` (`ComposedResultBuilder`)
- `Packages/Sources/RemoteSync/RemoteSync.ProgressReporter.swift`

Each docstring describes the type's purpose, not the soundness of `unchecked Sendable`. Pre-existing debt, not introduced today.

Fix shape: add a one-line `// @unchecked Sendable: <reason>` comment above each declaration in a follow-up sweep. For types where mutable state is present, the better fix per `concurrency.md §44` is to convert to `actor`.

### MED-4: 7 new producer targets shipped today lack behavioural tests

`testing-discipline.md` says "Real tests, not smoke." Today's 14-PR batch added 7 producer targets (`AppleDocsStrategy`, `HIGStrategy`, `SampleCodeStrategy`, `SwiftEvolutionStrategy`, `SwiftOrgStrategy`, `AppleArchiveStrategy`, `AppleConstraintsPass`). The only test coverage for the strategy family is `Packages/Tests/SearchStrategiesTests/SearchStrategies.Smoke.swift`, a 26-line metatype-reachability smoke that asserts `_ = Search.AppleDocsStrategy.self` and `#expect(Bool(true))`. `AppleConstraintsPass` has zero test files (`find Packages/Tests -iname '*AppleConstraintsPass*'` returns empty).

The 2496-test count cited above does not discharge testing-discipline for these specific producers; the count is the total green suite, not coverage of the touched code.

Fix shape: per-strategy `match()` / `rank()` fixture tests against a small in-memory result set; for `AppleConstraintsPass`, a test that runs the pass against a fixture lookup and verifies a row mutation in search.db (and also verifies the metrics: see LOW-3 below).

### LOW-3: Enrichment passes hardcode `rowsAffected` / `rowsSkipped` / `durationMs` to 0 on the success path

The `EnrichmentModels.Result` value type advertises these fields as observability metrics. The actual passes return zero on success:

- `Packages/Sources/AppleConstraintsPass/Enrichment.AppleConstraintsPass.swift:46-51`, returned `rowsAffected: 0` after `try await searchIndex.applyAppleStaticConstraints(lookup:)` actually does the work
- `Packages/Sources/Enrichment/Enrichment.LiveRunner.swift:49,83`
- `Packages/Sources/Enrichment/Enrichment.HierarchyPass.swift:31`

The `EnrichmentModels.Result` contract is observably broken. Pre-existing pattern, also present in the just-merged #973. The audit doc's first writing didn't catch this because the auditor was the same person who landed #973.

Fix shape: propagate `rowsAffected` from the underlying writer call (e.g., `applyAppleStaticConstraints` returns the count). Track as a follow-up to the #893 epic.

## Apple / Swift terms looked up via cupertino

- `cupertino search "@MainActor attribute" --limit 2` returned `NSCollectionViewLayoutAttributes` as the top hit, signalling that `@MainActor` is treated by Apple's surface as a usage attribute on types (the canonical example is a UI class annotated with it). For the language definition surface, the SE proposal channel is correct.
- `cupertino search "Sendable proposal SE-0302" --source swift-evolution --limit 1` returned: "SE-0302 introduced the `Sendable` protocol, including `Sendable` requirements for various language constructs, conformances of various standard library types to `Sendable`, and inference rules for non-public types to implicitly conform to `Sendable`." `Sendable` is a nominal protocol with compiler-synthesised implicit conformances, not structural.
- `cupertino search "Sendable protocol structural" --limit 2` returned `UnsafeSendable` as the top hit, confirming the nominal-protocol design (an `Unsafe*` escape hatch only makes sense in a nominal regime).

## Summary tally

- 19 mechanical checks executed; 19 green.
- **9 findings** (revised after critic on this doc): 3 HIGH (one-type-per-file, contract-doc drift, `Services.Formatter.Config.shared` Service Locator), 2 MED (`@unchecked Sendable` justifications, behavioural tests for the 7 new producer targets), 3 LOW (`TUI/Models/AppState` naming, `Logging`→`SearchSchema` cross-import, enrichment passes hardcoding `rowsAffected: 0`).
- No reconciliation item: critic forced the Rule 1 reading. `Services.Formatter.Config.shared` is a Service Locator violation, surfaced as HIGH-3.
- None are gating; all are pre-existing debt or surfaced from today's strict-DI work.
