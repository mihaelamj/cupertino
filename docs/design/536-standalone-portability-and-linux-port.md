# Design: #536 producer-standalone refactor + Linux runtime port

## TL;DR

Eight SPM producer targets import peer producers / pass modules, violating the
`#536` foundation-only contract. The audit that should have caught them
(`scripts/check-target-foundation-only.sh`) was silently disabled by two stale
`STRICT_PRODUCERS` entries (`Crawler`, `Ingest`), so the drift went unnoticed.
This doc sequences (1) lifting those 8 imports behind foundation/`*Models`
seams, which is the prerequisite for (2) a Linux runtime for the CLI + MCP
read/serve surface against the shipped DB bundle, and (3) Linux-side indexing of
the cross-platform Swift sources plus a derived `linux` availability dimension.
Crawl + index (`save`) stay macOS-only for now (WebKit JS render has no Linux
equivalent). This reverses the #7 "no Linux planned" decision.

## 1. Context

`#536` ("foundation-only producers") requires every target listed in
`STRICT_PRODUCERS` to import only Foundation, a fixed set of external primitives,
and the foundation-tier `*Models` seams. Shared logic lives in a `*Models` seam
(Sendable protocols + value types); the composition root wires concretes;
producers depend on the seam, not on peer producers. This is what makes each
package standalone-portable (gof-di-rules Rule 5) and is the precondition for a
Linux build, where Apple-only peers must not be dragged into the dependency
graph.

Two facts surfaced on 2026-05-29:

1. The audit script `exit 2`'d on stale `STRICT_PRODUCERS` entries `Crawler` and
   `Ingest` (both absorbed into per-source modules: `Crawler.AppleDocs.swift` /
   `Ingest.Session.swift` now live in `AppleDocsSource`). The early exit ran
   *before* the import-audit, so the audit has been effectively disabled and
   `#536` drift accumulated.
2. Removing the stale entries re-enables the audit, which reports **8
   producer->peer/pass imports**.

Separately, the product direction now includes a Linux runtime for non-Apple
Swift content (Foundation, Swift stdlib, SwiftPM packages, swift.org / swift-book
/ swift-evolution), which the `#536` lifts unblock.

## 2. Goals

### P0
- Re-enable the import-audit (remove `Crawler`/`Ingest`) and lift the 8
  producer->peer imports behind foundation/`*Models` seams. No behaviour change.
- Build + run the CLI + MCP **read/serve runtime** on Linux against the shipped
  bundle (`setup`, `search`, `read`, list/inheritance/AST-search, `doctor`,
  `serve`, all MCP read tools). (#1152)

### P1
- Linux-side indexing of the cross-platform Swift sources (swift-org /
  swift-book / swift-evolution / packages) + a derived `linux` availability
  dimension on `docs_metadata` + a search filter. (#1151)

### P2
- A Linux alternative for JS-rendered crawling (headless browser) so apple-docs
  / HIG can be crawled on Linux. Out of scope here; tracked separately.

## 3. Non-goals
- JS-rendered crawl on Linux (`save`/`fetch` for WebKit-backed sources stays
  macOS-only; Linux `save` errors gracefully with a "macOS-only" message).
- Any UI on Linux (cupertino core is CLI + MCP; AppKit/SwiftUI gate out).
- Changing macOS behaviour: every Linux change is `#if`/`condition:`-gated so
  macOS builds stay byte-for-byte identical.

## 4. The #536 lifts (detailed design)

The contract violation in each case is a `STRICT_PRODUCERS` target importing a
peer producer or a pass module. The fix moves the shared surface into a
foundation-only seam (or relocates concrete construction to the composition
root). Difficulty is set by what is actually used across the boundary.

| # | Importer | Peer | Symbols used | Lift | Difficulty |
|---|----------|------|--------------|------|------------|
| 1 | `SearchSQLite/Search.Index.HIGPlatformInference.swift` | `HIGPlatformInferencePass` | `HIGPlatformRules` (Foundation-only value type) | Move `HIGPlatformRules.swift` into a seam (new `HIGModels`, or fold into `SearchModels` which is already imported here) | Easy |
| 2a/2b | `HIGSource/Search.Strategies.HIG.swift`, `Crawler.HIG.swift` | `HIGPlatformInferencePass` | `HIGPlatformRules.minimumVersions/applicablePlatforms` | Same seam as #1 | Easy |
| 2c | `HIGSource/HIGSource.swift` | `HIGPlatformInferencePass` | constructs `Enrichment.HIGPlatformInferencePass(...)` | Relocate pass construction to the composition root, OR inject via the `EnrichmentModels.EnrichmentPass` protocol | Medium |
| 3 | `SampleCodeSource/SampleCodeSource.FetchStrategy.swift` | `CoreSampleCode` | `Sample.Core.GitHubFetcher` concrete (Observer + Progress already in `CoreSampleCodeModels`) | Move the strategy to the composition root, OR add a `Sample.Core.Fetching` Strategy protocol to `CoreSampleCodeModels` and inject the concrete | Medium |
| 4 | `SwiftOrgSource/SwiftOrgSource.swift` | `AppleDocsSource` | `WebCrawlFetchStrategy(...)` | Extract shared crawl infra (see below) | Hard |
| 5 | `SwiftBookSource/SwiftBookSource.swift` | `AppleDocsSource` | `WebCrawlFetchStrategy(...)` | Same shared crawl target as #4 | Hard |
| 6 | `PackagesSource/PackagesSource.FetchStrategy.swift` | `CorePackageIndexing` | whole 3-stage pipeline (`PackageFetcher`, resolver, extractor, annotator, ...) | Move pipeline orchestration to the composition root, OR inject a `PackageFetchPipeline` Strategy from `CorePackageIndexingModels` | Hard |

**Shared crawl infra (#4/#5).** `WebCrawlFetchStrategy`, `Crawler.AppleDocs`, and
`Ingest.Session` (all in `AppleDocsSource`) are the de-facto web-crawl engine for
the three web-crawl-tier sources (apple-docs / swift-org / swift-book). They
should become a `WebCrawlSource` (a.k.a. `CrawlerCore`) producer that all three
import. `WebCrawlFetchStrategy.run` already takes its inputs via
`Search.FetchEnvironment`, so the extraction looks clean; verify the
`Crawler.AppleDocs` ctor params (htmlParser / appleJSONParser /
priorityPackageStrategy) are all seam types so the shared target leaks no
apple-docs-specific concept.

**Worked example (#1, the trivial one).** `HIGPlatformRules` is a
`struct`/`enum` of static platform-inference rules importing only `Foundation`.
Today it lives in the `HIGPlatformInferencePass` producer. Moving the file into
`SearchModels` (or a new `HIGModels`) makes both `SearchSQLite` and `HIGSource`
import the seam instead of the pass; the pass itself keeps consuming the rules
from the seam. Zero behaviour change; the audit goes from 4 violations to 0 for
the HIG cluster.

**Open design question.** For #2c/#3/#6, the composition-root move is simplest,
but the `*Source` providers expose `makeFetchStrategy()` /
`makeSourceSpecificEnrichmentPasses()`, implying the provider owns its wiring. If
providers must stay self-wiring, the lift must be a real Strategy protocol in the
seam, not a composition-root relocation. Decide per-producer in its PR.

## 5. Linux runtime layer (#1152)

Goal: the CLI + MCP read/serve surface builds and runs on Linux against the
shipped bundle. Real-usage analysis (separating constructors from comment
mentions) gives a small minimum change set; everything else is crawl/index-only
and is simply excluded from the Linux build.

| Dep | Real usages | Runtime vs crawl | Strategy |
|-----|-------------|------------------|----------|
| WebKit | 5 files (isolated `*WebKit` sibling targets behind protocol seams) | 100% crawl/index | Exclude the `*WebKit` targets from the Linux product set (`#if os(macOS)`). No runtime impact. |
| AppKit | 1 (`CLIImpl.Command.ResolveRefs.swift`) | runtime, already `#if canImport(AppKit)`-gated | none |
| SwiftUI | 0 real (grep false-positive in SQL comments) | n/a | none |
| OSLog | 5 real imports; only `Logging` is runtime (behind the `LoggingModels.Logging.Recording` seam) | `SampleIndex.Builder` + `Crawler.AppleDocs` are index/crawl-only | Ship a swift-log Linux concrete behind the existing `Recording` seam; `#if canImport(OSLog)`-gate the 2 leaks |
| CryptoKit | 3 files in the `SharedConstants` target (`Sources/Shared`) | **structural** (foundation-tier, in every runtime graph) though SHA256 callers are crawl-only | `#if canImport(CryptoKit) import CryptoKit #else import Crypto #endif` (swift-crypto `Crypto.SHA256` is API-compatible) + `.when(platforms:[.linux])` dep. Cannot gate out. |
| URLSession | 16 real constructors; **exactly 1 runtime**: `Distribution.Artifact.Downloader.swift` (`setup` bundle download) | the other 15 are crawl/fetch or the `cupertino-rel` binary | A `Distribution` download Strategy protocol + Linux concrete, mirroring the existing `AvailabilityModels.Networking` + `AvailabilityFoundationNetworking` precedent. Gate the 15 crawl files out. |
| Darwin | 4 runtime CLI files (`Serve`, `ServeReaper`, `SaveSiblingGate`, `Cupertino.swift`) use `kill`/SIGTERM/SIGKILL | runtime (`serve`) | `#if canImport(Glibc)` gating (Glibc/Musl provide signals) |

Also: `Distribution.Artifact.Extractor.swift` shells `/usr/bin/unzip` for the
~833 MB bundle (setup runtime path): `Foundation.Process` works on Linux but the
host/CI container must have `unzip` (or swap to a Swift-native unzip).

**Minimum runtime change set:** (1) `SharedConstants` CryptoKit -> swift-crypto;
(2) `Distribution` download Linux path; (3) `Distribution` unzip host check; (4)
`Logging` swift-log concrete + gate 2 leaks; (5) `Darwin` -> `Glibc` signal
gating; (6) manifest: Linux runtime product/target subset + conditional deps.

**Manifest.** `Package.swift` is `platforms: [.macOS(.v13)]` and already splits
`baseProducts` (just `MCPCore`, cross-platform) + `macOSOnlyProducts`
(`#if os(macOS)`); `cupertinoTargets` is `#if os(macOS)`-only. Add a Linux
runtime product/target subset (the read/serve closure: `SearchSQLite`,
`SearchAPI`, `SearchModels`, `SearchSchema`, `MCPCore`/`MCPSupport`,
`SearchToolProvider`, `Distribution`(+Models), `Logging`(+Models),
`SharedConstants`, `Services`(+Models), the read-side `*Source` targets, the
`CLI` executable) and the three external deps (`swift-crypto`, `swift-log`,
`async-http-client`) via `.product(..., condition: .when(platforms: [.linux]))`
so macOS builds are untouched. Source still needs `#if canImport(...)` to pick
the right import; both layers are required.

**CI.** `.github/workflows/ci.yml` has no Linux build job (build/portability/
query-smoke are `macos-15`; the ubuntu jobs run bash audits only). Add a
`build-linux` job (swift container) running `swift build` of the Linux subset +
a `setup` + `search`/`read` + MCP smoke. The existing `query-batteries-smoke` is
the template.

## 6. Data model: the `linux` availability dimension (#1151)

`@available` has no Linux axis, so `linux` availability is **derived, not
parsed**: a doc/symbol is Linux-available when it comes from a cross-platform
source (swift-org / swift-book / swift-evolution / packages) or a known
cross-platform module (Foundation, Swift stdlib), and Apple-only when it comes
from apple-docs / HIG / an Apple SDK framework. Stored as a marker on
`docs_metadata` alongside the existing platform floors (`min_ios` ... ),
schema-versioned, and exposed through the same search/filter path as those
floors. A Linux `cupertino save` builds only the cross-platform sources.

## 7. Rollout / phasing

**Phase 1: #536 lifts (macOS-side, pure refactor).** Each is gated by the
re-enabled `check-target-foundation-only.sh`.
- PR 1.1: `HIGPlatformRules.swift` -> seam (fixes 1, 2a, 2b). Trivial.
- PR 1.2: HIG pass construction -> composition root / `EnrichmentPass` (2c).
- PR 1.3: SampleCode fetch lift (3).
- PR 1.4: extract `WebCrawlSource` (4, 5). Largest.
- PR 1.5: Packages pipeline lift (6).
- PR 1.6: re-enable the audit (the parked `Crawler`/`Ingest` removal) + add it as
  a pre-commit hook so drift can't recur.

**Phase 2: Linux read/serve runtime (#1152).** Independent of the producer
lifts; the CryptoKit/Logging/Distribution work can proceed in parallel.
- PR 2.1: `SharedConstants` CryptoKit -> swift-crypto (do first; everything links it).
- PR 2.2: `Logging` swift-log Linux concrete + gate the 2 OSLog leaks.
- PR 2.3: `Distribution` setup-download Linux path + unzip host check.
- PR 2.4: `Darwin` -> `Glibc` signal gating (4 CLI files).
- PR 2.5: manifest Linux subset + conditional deps + `build-linux` CI job + smoke.

**Phase 3: Linux indexing (#1151).** Depends on PR 1.4 (`WebCrawlSource`). The
`linux` availability dimension + the cross-platform-source save scope + the
search filter. JS-render crawl stays macOS-only (or a headless-browser
alternative, P2).

## 8. Reliability & failure modes
- **Audit re-enable exposes more than the known 8.** The dir-fix runs the audit
  for the first time in a while; cross-check `STRICT_PRODUCERS` against actual
  targets before landing PR 1.6 (already done: only `Crawler`/`Ingest` are
  stale). Run the script after each Phase-1 PR.
- **`WebCrawlSource` leakage.** If the extracted target re-exports apple-docs
  concepts, the seam is impure. Mitigation: verify all ctor params are seam types.
- **swift-crypto parity.** Only `SHA256.hash` is used; verify no `Insecure.*`.
- **Linux download UX regression.** `FoundationNetworking` has no download-progress
  delegate; the `setup` progress bar would degrade. `AsyncHTTPClient` preserves it
  at the cost of a new dep. See Alternatives.
- **`/usr/bin/unzip` absent on Linux host.** CI container must install it, or swap
  to a Swift unzip.

## 9. Testing strategy
- Phase 1: `check-target-foundation-only.sh` exit 0 after each lift; full
  `swift test` green (no behaviour change).
- Phase 2: `build-linux` CI job (Docker swift image) builds the Linux subset and
  runs a `setup` + `search`/`read` + MCP-smoke; macOS CI unchanged.
- Phase 3: a derivation test for `linux` availability per source/module + a
  Linux-availability filter test (parity with the existing platform-floor tests).

## 10. Alternatives considered
- **Allow-list the 8 imports instead of refactoring.** Fast (the check goes green
  immediately) but formally relaxes the `#536` standalone-portable contract and
  blocks Linux (the peers still drag Apple-only code into the graph). Rejected in
  favour of the refactor.
- **`FoundationNetworking` vs `AsyncHTTPClient` for the Linux `setup` download.**
  FoundationNetworking adds no dependency but loses the download-progress delegate
  (degraded `SetupRenderer` progress bar). AsyncHTTPClient adds a dependency but
  preserves streaming + progress. Leaning AsyncHTTPClient for UX parity; decide in
  PR 2.3.
- **Headless-browser crawl on Linux (P2).** Would let apple-docs / HIG crawl on
  Linux, but it is a large addition and orthogonal to the runtime goal. Deferred.

## 11. Status / references
- Issues: #536 (refactor/audit), #1152 (Linux runtime), #1151 (Linux indexing +
  `linux` availability). Reverses #7.
- The parked `Crawler`/`Ingest` `STRICT_PRODUCERS` dir-fix lands in PR 1.6.
