import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SampleIndex
import Search
import SearchModels
import Services
import ServicesModels
import SharedConstants

// MARK: - SmartQuery fan-out helpers (#239)

/// Helpers for `CLIImpl.Command.Search`'s default (no `--source`) path: building the
/// per-DB `CandidateFetcher` list, then printing the fused result in
/// text / markdown / json. Lifted out of `CLIImpl.Command.Search.swift` so the
/// struct body stays under SwiftLint's `type_body_length` ceiling and so
/// the printers don't need access to instance-level CLI options.
extension CLIImpl.Command.Search {
    /// Bundle returned by `buildFetchers`. The `searchIndex` and
    /// `sampleService` references are kept so the caller can disconnect
    /// them once the SmartQuery has run — the fetchers don't own those
    /// connections.
    struct FetcherPlan {
        let fetchers: [any Search.CandidateFetcher]
        let searchIndex: SearchModule.Index?
        let sampleService: Sample.Search.Service?
        /// Set when `search.db` exists on disk but couldn't be opened
        /// (schema mismatch, corrupt file, "not a database"). Mirrors
        /// `CompositeToolProvider.searchIndexDisabledReason` from #645 /
        /// PR #649 on the MCP side. When non-nil, `runUnifiedSearch`
        /// synthesises `Search.DegradedSource` entries for the 6 search.
        /// db-backed sources (apple-docs, apple-archive, hig,
        /// swift-evolution, swift-org, swift-book) and merges them into
        /// the `SmartResult.degradedSources` array, so CLI `--format json`
        /// consumers see the same `degradedSources` payload MCP markdown
        /// already shows via #650 / PR #652. Nil for "search.db not
        /// found" (legitimate file-missing path) and the happy case.
        let searchDBDisabledReason: String?
    }

    /// Docs-backed sources in a consistent order. `apple-archive` is included
    /// with `includeArchive: true` so the base search path doesn't exclude it.
    static let docsSources: [(prefix: String, includeArchive: Bool)] = [
        (Shared.Constants.SourcePrefix.appleDocs, false),
        (Shared.Constants.SourcePrefix.appleArchive, true),
        (Shared.Constants.SourcePrefix.hig, false),
        (Shared.Constants.SourcePrefix.swiftEvolution, false),
        (Shared.Constants.SourcePrefix.swiftOrg, false),
        (Shared.Constants.SourcePrefix.swiftBook, false),
    ]

    /// Sources whose results aren't scoped by `--platform`/`--min-version`.
    /// Only the Swift-language-version-axis sources remain unfiltered (their
    /// pages don't carry `min_<platform>` columns at all — see #225 for the
    /// matching `--swift` flag).
    static let unfilteredSourcesUnderPlatformFlag: [String] = [
        Shared.Constants.SourcePrefix.swiftEvolution,
        Shared.Constants.SourcePrefix.swiftOrg,
        Shared.Constants.SourcePrefix.swiftBook,
    ]

    /// Validate the `--platform` / `--min-version` pair into an
    /// `AvailabilityFilter`. Either both flags or neither — anything else
    /// errors out with `ExitCode.failure` so the user sees a clean message.
    func resolveAvailabilityFilter() throws -> SearchModels.Search.AvailabilityFilter? {
        switch (platform, minVersion) {
        case let (platform?, minVersion?):
            return SearchModels.Search.AvailabilityFilter(
                platform: platform,
                minVersion: minVersion
            )
        case (.some, nil), (nil, .some):
            Cupertino.Context.composition.logging.recording.error(
                "❌ --platform and --min-version must be used together."
            )
            throw ExitCode.failure
        case (nil, nil):
            return nil
        }
    }

    /// Open every available DB and produce a fetcher per source. Missing
    /// or unopenable DBs log a one-line info note and are silently dropped
    /// from the fan-out (mirrors the resilience that `cupertino ask` had).
    func buildFetchers(
        availabilityFilter: SearchModels.Search.AvailabilityFilter?
    ) async -> FetcherPlan {
        var fetchers: [any Search.CandidateFetcher] = []

        // #628: thread `--framework` into the docs fetchers so the unified
        // (no `--source`) path honours it. Other fetchers (packages,
        // samples) don't partition by Apple framework at the row level.
        let docsResult = await Self.openDocsFetchers(
            override: searchDb,
            skip: skipDocs,
            availability: availabilityFilter,
            framework: framework,
            into: &fetchers
        )

        Self.openPackagesFetcher(
            override: packagesDb,
            skip: skipPackages,
            availability: availabilityFilter,
            into: &fetchers
        )

        let sampleService = await Self.openSamplesFetcher(
            override: sampleDb,
            skip: skipSamples,
            availability: availabilityFilter,
            into: &fetchers
        )

        return FetcherPlan(
            fetchers: fetchers,
            searchIndex: docsResult.index,
            sampleService: sampleService,
            searchDBDisabledReason: docsResult.disabledReason
        )
    }

    /// #648 (CLI JSON path) — pair of `(SearchModule.Index?, String?)`
    /// returned by `openDocsFetchers`. Distinguishes the three states a
    /// search.db open can land in:
    ///   - `(index, nil)`     — happy path, fetchers wired
    ///   - `(nil, nil)`       — file legitimately missing (skip / samples-only)
    ///   - `(nil, "<reason>")` — file present but unopenable (schema mismatch,
    ///     corrupt file, "not a database"); fetchers can't be wired but
    ///     the CLI should surface the failure to `--format json` consumers
    ///     via `SmartResult.degradedSources` instead of silently dropping
    ///     to "no apple-docs match" semantics.
    struct DocsFetchersResult {
        let index: SearchModule.Index?
        let disabledReason: String?
    }

    private static func openDocsFetchers(
        override: String?,
        skip: Bool,
        availability: SearchModels.Search.AvailabilityFilter?,
        framework: String?,
        into fetchers: inout [any Search.CandidateFetcher]
    ) async -> DocsFetchersResult {
        guard !skip else { return DocsFetchersResult(index: nil, disabledReason: nil) }
        let url = override.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Paths.live().searchDatabase
        guard FileManager.default.fileExists(atPath: url.path) else {
            // #654 — route the missing-file diagnostic to stderr (.warning
            // in Logging.Unified.logToConsole, not .info) so it doesn't
            // pollute stdout when `--format json` is set. Same reasoning
            // as the schema-mismatch path at the catch-block below
            // (already `.error()` → stderr). Text + markdown CLI users
            // still see the line on the same terminal stream interleaved
            // with the report.
            Cupertino.Context.composition.logging.recording.warning(
                "ℹ️  search.db not found at \(url.path) — skipping doc sources."
            )
            // File legitimately missing isn't a configuration error —
            // it's the samples-only path. Mirror #645's distinction:
            // disabledReason stays nil so the CLI doesn't synthesise
            // fake degradedSources for users who never set up the
            // bundle in the first place.
            return DocsFetchersResult(index: nil, disabledReason: nil)
        }
        do {
            let index = try await SearchModule.Index(dbPath: url, logger: Cupertino.Context.composition.logging.recording)
            for source in docsSources {
                fetchers.append(Search.DocsSourceCandidateFetcher(
                    searchIndex: index,
                    source: source.prefix,
                    includeArchive: source.includeArchive,
                    availability: availability,
                    framework: framework
                ))
            }
            return DocsFetchersResult(index: index, disabledReason: nil)
        } catch {
            Cupertino.Context.composition.logging.recording.error(
                "⚠️  Could not open search.db: \(error.localizedDescription)"
            )
            // #648 (CLI JSON path) — file present + open failed
            // is a configuration error. Pre-fix the catch returned nil
            // alongside the file-missing path and the downstream
            // SmartQuery saw zero docs fetchers in the fan-out, which
            // its `classifyDegradation` plumbing couldn't pin to a
            // schema-mismatch (no per-fetcher throw fired — they
            // never ran). Result: `SmartResult.degradedSources` stayed
            // empty + the CLI `--format json` payload had an empty
            // `degradedSources` array even though 6 sources had
            // actually failed to open. Classify with the same patterns
            // SmartQuery / UnifiedSearchService use (#640 / #642) and
            // return the reason so the caller can synthesise the
            // open-time `DegradedSource` entries — mirrors #648 (open-
            // time) / PR #652 on the MCP side.
            let reason = SearchModule.SmartQuery.classifyDegradation(error)
                ?? "search index initialisation failed: \(error.localizedDescription)"
            return DocsFetchersResult(index: nil, disabledReason: reason)
        }
    }

    private static func openPackagesFetcher(
        override: String?,
        skip: Bool,
        availability: SearchModels.Search.AvailabilityFilter?,
        into fetchers: inout [any Search.CandidateFetcher]
    ) {
        guard !skip else { return }
        let url = override.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Paths.live().packagesDatabase
        guard FileManager.default.fileExists(atPath: url.path) else {
            // #654 — see openDocsFetchers above. Stderr keeps `--format
            // json` stdout pure for `jq` consumers.
            Cupertino.Context.composition.logging.recording.warning(
                "ℹ️  packages.db not found at \(url.path) — skipping packages."
            )
            return
        }
        fetchers.append(SearchModule.PackageFTSCandidateFetcher(
            dbPath: url,
            availability: availability
        ))
    }

    private static func openSamplesFetcher(
        override: String?,
        skip: Bool,
        availability: SearchModels.Search.AvailabilityFilter?,
        into fetchers: inout [any Search.CandidateFetcher]
    ) async -> Sample.Search.Service? {
        guard !skip else { return nil }
        let url = override.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Sample.Index.databasePath(baseDirectory: Shared.Paths.live().baseDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // #654 — see openDocsFetchers above. Stderr keeps `--format
            // json` stdout pure for `jq` consumers.
            Cupertino.Context.composition.logging.recording.warning(
                "ℹ️  samples.db not found at \(url.path) — skipping samples."
            )
            return nil
        }
        do {
            let database = try await Sample.Index.Database(dbPath: url, logger: Cupertino.Context.composition.logging.recording)
            let service = Sample.Search.Service(database: database)
            fetchers.append(Sample.Services.CandidateFetcher(
                service: service,
                availability: availability
            ))
            return service
        } catch {
            Cupertino.Context.composition.logging.recording.error(
                "⚠️  Could not open samples.db: \(error.localizedDescription)"
            )
            return nil
        }
    }

    // MARK: - Print

    static func printSmartReport(
        result: Search.SmartResult,
        question: String,
        availabilityFilterActive: Bool,
        platform: String?,
        minVersion: String?,
        format: OutputFormat,
        brief: Bool
    ) {
        switch format {
        case .text:
            printSmartReportText(
                result: result,
                question: question,
                availabilityFilterActive: availabilityFilterActive,
                platform: platform,
                minVersion: minVersion,
                brief: brief
            )
        case .markdown:
            printSmartReportMarkdown(
                result: result,
                question: question,
                availabilityFilterActive: availabilityFilterActive,
                platform: platform,
                minVersion: minVersion,
                brief: brief
            )
        case .json:
            // JSON keeps full chunks so programmatic consumers (LLMs, scripts)
            // never lose data — they can truncate themselves if needed.
            printSmartReportJSON(result: result, question: question)
        }
    }

    /// First N non-blank lines of a chunk, used by `--brief` mode. Default
    /// 12 — enough context to actually understand what each result is about
    /// (covers a full overview paragraph + start of the meat) without burying
    /// the next result. Drop smaller via `lines:` if a future flag wants
    /// triage-density output.
    static func briefExcerpt(of chunk: String, lines: Int = 12) -> String {
        let nonEmpty = chunk
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let take = nonEmpty.prefix(lines)
        let truncated = take.joined(separator: "\n")
        return nonEmpty.count > lines ? truncated + "\n…" : truncated
    }

    private static func printSmartReportText(
        result: Search.SmartResult,
        question: String,
        availabilityFilterActive: Bool,
        platform: String?,
        minVersion: String?,
        brief: Bool
    ) {
        // #640 — surface configuration-error sources before the body so
        // the user sees the schema-mismatch warning whether the query
        // matched anything or not. Prints to stderr-equivalent
        // (`print` here goes to stdout for CLI piping; the warning
        // shape echoes what CLI users already get from the loud
        // `cupertino search` schema error).
        printDegradedSourcesText(result: result)
        if result.candidates.isEmpty {
            let sources = result.contributingSources.isEmpty
                ? "no sources responded"
                : "searched \(result.contributingSources.joined(separator: ", "))"
            print("No matches for: \(question)")
            print("(\(sources))")
            return
        }

        print("Question: \(question)")
        print("Searched: \(result.contributingSources.joined(separator: ", "))")
        printPlatformNoticeText(
            result: result,
            availabilityFilterActive: availabilityFilterActive,
            platform: platform,
            minVersion: minVersion
        )

        print("")
        for (idx, fused) in result.candidates.enumerated() {
            let cand = fused.candidate
            print(String(repeating: "═", count: 70))
            print(
                "[\(idx + 1)] \(cand.title)  •  source: \(cand.source)  •  "
                    + "score: \(String(format: "%.4f", fused.score))"
            )
            print("    \(cand.identifier)")
            print(String(repeating: "─", count: 70))
            print(brief ? briefExcerpt(of: cand.chunk) : cand.chunk)
            if let readCmd = readFullCommand(for: cand) {
                print("")
                print("▶ Read full: \(readCmd)")
            }
            print("")
        }

        printSeeAlsoText(question: question, result: result)
        printTipsFooterText(availabilityFilterActive: availabilityFilterActive)
    }

    private static func printSeeAlsoText(
        question: String,
        result: Search.SmartResult
    ) {
        guard !result.contributingSources.isEmpty else { return }
        print(String(repeating: "─", count: 70))
        print("See also — drill into one source:")
        for source in result.contributingSources {
            print("  cupertino search \"\(question)\" --source \(source)")
        }
        print("")
    }

    /// Emit a `⚠ N sources unavailable` banner when any fetcher hit a
    /// configuration error (#640). No-op when `result.degradedSources`
    /// is empty so the existing happy-path output is unchanged.
    private static func printDegradedSourcesText(result: Search.SmartResult) {
        guard !result.degradedSources.isEmpty else { return }
        let count = result.degradedSources.count
        print("⚠ \(count) source\(count == 1 ? "" : "s") unavailable due to configuration error:")
        for degraded in result.degradedSources {
            print("  - \(degraded.name): \(degraded.reason)")
        }
        print("")
    }

    private static func printDegradedSourcesMarkdown(result: Search.SmartResult) {
        guard !result.degradedSources.isEmpty else { return }
        print("> ⚠ **\(result.degradedSources.count) source\(result.degradedSources.count == 1 ? "" : "s") unavailable due to configuration error:**")
        for degraded in result.degradedSources {
            print("> - `\(degraded.name)`: \(degraded.reason)")
        }
        print("")
    }

    private static func printTipsFooterText(availabilityFilterActive: Bool) {
        print("💡 Narrow with --source <name>: "
            + Shared.Constants.Search.availableSources.joined(separator: ", "))
        if !availabilityFilterActive {
            print("💡 Filter by platform: --platform iOS --min-version 16.0  "
                + "(or macOS / tvOS / watchOS / visionOS)")
        }
    }

    private static func printPlatformNoticeText(
        result: Search.SmartResult,
        availabilityFilterActive: Bool,
        platform: String?,
        minVersion: String?
    ) {
        guard availabilityFilterActive,
              let platform,
              let minVersion else { return }
        let unfiltered = result.contributingSources.filter {
            unfilteredSourcesUnderPlatformFlag.contains($0)
        }
        guard !unfiltered.isEmpty else { return }
        print(
            "ℹ️  --platform \(platform) --min-version \(minVersion) doesn't apply to "
                + unfiltered.joined(separator: ", ")
                + " — those sources use a different availability axis "
                + "(Swift language version). apple-docs / apple-archive / hig / "
                + "packages / samples results ARE filtered."
        )
    }

    private static func printSmartReportMarkdown(
        result: Search.SmartResult,
        question: String,
        availabilityFilterActive: Bool,
        platform: String?,
        minVersion: String?,
        brief: Bool
    ) {
        print("# Results for `\(question)`")
        print("")
        // #640 — schema-mismatch / DB-unopenable warning at the top so
        // AI agents reading the markdown body see it before the
        // candidate list. Uses a blockquote so MCP clients render it
        // distinctly.
        printDegradedSourcesMarkdown(result: result)
        if result.candidates.isEmpty {
            let sources = result.contributingSources.isEmpty
                ? "no sources responded"
                : result.contributingSources.joined(separator: ", ")
            print("_No matches. Searched: \(sources)._")
            return
        }
        print("_Searched: \(result.contributingSources.joined(separator: ", "))._")
        printPlatformNoticeMarkdown(
            result: result,
            availabilityFilterActive: availabilityFilterActive,
            platform: platform,
            minVersion: minVersion
        )
        print("")
        for (idx, fused) in result.candidates.enumerated() {
            let cand = fused.candidate
            print("## \(idx + 1). \(cand.title)")
            print("")
            print(
                "- **Source:** `\(cand.source)`"
                    + "  •  **Score:** \(String(format: "%.4f", fused.score))"
            )
            print("- **Id:** `\(cand.identifier)`")
            if let readCmd = readFullCommand(for: cand) {
                print("- **Read full:** `\(readCmd)`")
            }
            print("")
            print(brief ? briefExcerpt(of: cand.chunk) : cand.chunk)
            print("")
        }

        printSeeAlsoMarkdown(question: question, result: result)
        printTipsFooterMarkdown(availabilityFilterActive: availabilityFilterActive)
    }

    private static func printSeeAlsoMarkdown(
        question: String,
        result: Search.SmartResult
    ) {
        guard !result.contributingSources.isEmpty else { return }
        print("---")
        print("")
        print("**See also — drill into one source:**")
        print("")
        for source in result.contributingSources {
            print("- `cupertino search \"\(question)\" --source \(source)`")
        }
        print("")
    }

    private static func printTipsFooterMarkdown(availabilityFilterActive: Bool) {
        let sources = Shared.Constants.Search.availableSources.joined(separator: ", ")
        print("> 💡 **Narrow with `--source <name>`:** \(sources)")
        if !availabilityFilterActive {
            print(
                "> 💡 **Filter by platform:** `--platform iOS --min-version 16.0` "
                    + "(or `macOS` / `tvOS` / `watchOS` / `visionOS`)"
            )
        }
    }

    private static func printPlatformNoticeMarkdown(
        result: Search.SmartResult,
        availabilityFilterActive: Bool,
        platform: String?,
        minVersion: String?
    ) {
        guard availabilityFilterActive,
              let platform,
              let minVersion else { return }
        let unfiltered = result.contributingSources.filter {
            unfilteredSourcesUnderPlatformFlag.contains($0)
        }
        guard !unfiltered.isEmpty else { return }
        print(
            "> ℹ️ `--platform \(platform) --min-version \(minVersion)` doesn't apply "
                + "to " + unfiltered.joined(separator: ", ")
                + " (Swift language version axis)."
        )
    }

    private static func printSmartReportJSON(
        result: Search.SmartResult,
        question: String
    ) {
        struct CandidateOut: Encodable {
            let rank: Int
            let source: String
            let identifier: String
            let title: String
            let chunk: String
            let score: Double
            let kind: String?
            let metadata: [String: String]
            /// CLI command an LLM should run to read the full document.
            /// Nil for sources without a first-party read command (packages
            /// today — read directly from `~/.cupertino/packages/<id>`).
            let readFullCommand: String?
        }
        // `degradedSources` (#640) field next to `contributingSources`
        // so JSON consumers (AI agents, dashboards, automated pipelines)
        // can distinguish "no apple-docs match for the query" from
        // "apple-docs.db is unopenable". Empty array on the happy path
        // keeps the shipped output shape backwards-compatible.
        struct DegradedSourceOut: Encodable {
            let name: String
            let reason: String
        }
        struct ReportOut: Encodable {
            let question: String
            let contributingSources: [String]
            let degradedSources: [DegradedSourceOut]
            let candidates: [CandidateOut]
        }
        let report = ReportOut(
            question: question,
            contributingSources: result.contributingSources,
            degradedSources: result.degradedSources.map {
                DegradedSourceOut(name: $0.name, reason: $0.reason)
            },
            candidates: result.candidates.enumerated().map { idx, fused in
                CandidateOut(
                    rank: idx + 1,
                    source: fused.candidate.source,
                    identifier: fused.candidate.identifier,
                    title: fused.candidate.title,
                    chunk: fused.candidate.chunk,
                    score: fused.score,
                    kind: fused.candidate.kind,
                    metadata: fused.candidate.metadata,
                    readFullCommand: readFullCommand(for: fused.candidate)
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report),
           let json = String(data: data, encoding: .utf8) {
            Cupertino.Context.composition.logging.recording.output(json)
        }
    }

    // MARK: - Read-full command per source

    /// CLI command a downstream consumer (LLM, script, human) should run to
    /// read the full document a chunk was excerpted from. After #239's
    /// option-B unification, every source resolves through the single
    /// `cupertino read <id> --source <name>` entry point; the source flag
    /// disambiguates sample-file vs. package paths (both have shape
    /// `<seg>/<seg>/<seg>`). Returns nil only for unknown sources.
    static func readFullCommand(for candidate: Search.SmartCandidate) -> String? {
        let source: String
        switch candidate.source {
        case Shared.Constants.SourcePrefix.appleDocs,
             Shared.Constants.SourcePrefix.appleArchive,
             Shared.Constants.SourcePrefix.hig,
             Shared.Constants.SourcePrefix.swiftEvolution,
             Shared.Constants.SourcePrefix.swiftOrg,
             Shared.Constants.SourcePrefix.swiftBook,
             Shared.Constants.SourcePrefix.samples,
             Shared.Constants.SourcePrefix.packages:
            source = candidate.source
        default:
            return nil
        }
        return "cupertino read \(candidate.identifier) --source \(source)"
    }
}
