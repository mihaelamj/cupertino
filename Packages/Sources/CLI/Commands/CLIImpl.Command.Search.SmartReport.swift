import ArgumentParser
import Foundation
import Logging
import LoggingModels
import SampleIndex
import SampleIndexSQLite
import SearchAPI
import SearchModels
import SearchSQLite
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
    /// Bundle returned by `buildFetchers`. Each per-source `Search.Index`
    /// in `docsIndexes` is keyed by source-id (`apple-docs`, `hig`, …) so
    /// the caller can pick one for framework validation and disconnect
    /// them all once the SmartQuery has run -- the fetchers don't own
    /// those connections.
    struct FetcherPlan {
        let fetchers: [any Search.CandidateFetcher]
        /// Per-source DB handles, keyed by `SourceProvider.definition.id`.
        /// Post-#1037/#1038, every docs source has its own SQLite file
        /// (apple-documentation.db, hig.db, apple-archive.db,
        /// swift-evolution.db, swift-org.db, swift-book.db). Each open
        /// connection lives here until `runUnifiedSearch` disconnects.
        let docsIndexes: [String: SearchModule.Index]
        let sampleService: Sample.Search.Service?
        /// Per-source open-time failure reasons. Keyed by source-id;
        /// populated only for sources whose per-source DB exists on disk
        /// but couldn't be opened (schema mismatch, corrupt file,
        /// "not a database"). Mirrors `CompositeToolProvider`'s open-time
        /// classifier from #645 / PR #649 on the MCP side, lifted to a
        /// per-source dictionary post-#1037 so a single stale DB
        /// (e.g. `hig.db` after a partial migration) reports its own
        /// `DegradedSource` entry rather than synthesising six fakes.
        /// Empty on the file-missing path (legitimate "samples-only"
        /// case) and on the happy path.
        let disabledReasonsBySource: [String: String]
    }

    /// Docs-backed sources in a consistent order. `apple-archive` is included
    /// with `includeArchive: true` so the base search path doesn't exclude it.
    ///
    /// #1042 audit + wiring batch 3: derived at call time from the
    /// production source registry. A "docs-tier" source is one whose
    /// `destinationDB` is in the search.db FTS family. That covers
    /// apple-docs, hig, apple-archive, swift-evolution, swift-org,
    /// swift-book today, and any future search-tier source. `searchRoute`
    /// is NOT the right predicate here — HIG has `.hig` dispatch but
    /// still lives in the search.db family (Cluster 9 sub-3 test
    /// showed this regression and was caught by `CLISearchUrlResolutionTests`).
    /// `includeArchive` is `true` for the apple-archive provider only.
    ///
    /// 2026-05-26 audit #1055 layer-2 part 3: filter flipped from a
    /// hardcoded `excluded: [.appleSampleCode, .packages]` descriptor
    /// set to `provider.isSearchTier`. Pre-fix any new source with a
    /// non-FTS backend (its own bespoke index) had to be appended to
    /// that set; post-fix `SampleCodeSource` and `PackagesSource`
    /// override `isSearchTier = false` themselves, every other source
    /// inherits the `true` default and joins the docs-tier fan-out
    /// automatically.
    static func docsSources() -> [(prefix: String, includeArchive: Bool)] {
        let registry = CLIImpl.makeProductionSourceRegistry()
        return registry.allEnabled
            .filter(\.isSearchTier)
            .map { (
                prefix: $0.definition.id,
                includeArchive: $0.definition.id == Shared.Constants.SourcePrefix.appleArchive
            ) }
    }

    /// Sources whose results aren't scoped by `--platform`/`--min-version`.
    /// Only the Swift-language-version-axis sources remain unfiltered (their
    /// pages don't carry `min_<platform>` columns at all -- see #225 for the
    /// matching `--swift` flag).
    ///
    /// #1042 audit + wiring batch 3: derived at call time from each
    /// registered provider's `Search.Capabilities.metadata[.hasMinSwiftVersion]`
    /// flag (the same source-of-truth Cluster 4's CandidateFetcher
    /// wiring uses). A new Swift-version-axis source declares the
    /// metadata flag and lands in this set without touching this file.
    static func unfilteredSourcesUnderPlatformFlag() -> Set<String> {
        let registry = CLIImpl.makeProductionSourceRegistry()
        return Set(
            registry.allEnabled
                .filter { $0.capabilities.metadata[.hasMinSwiftVersion] == true }
                .map(\.definition.id)
        )
    }

    /// Validate the `--platform` / `--min-version` pair into an
    /// `AvailabilityFilter`. Either both flags or neither -- anything else
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
            appleImport: appleImports,
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
            docsIndexes: docsResult.indexes,
            sampleService: sampleService,
            disabledReasonsBySource: docsResult.disabledReasonsBySource
        )
    }

    /// Result of `openDocsFetchers`. Post-#1037/#1038 each docs source
    /// owns its own SQLite DB, so the open path returns a per-source
    /// map of opened indexes plus a per-source map of open-time
    /// failure reasons. Mirrors the older single-DB `DocsFetchersResult`
    /// but with `[String: …]` instead of `…?` so a partial failure
    /// (e.g. `hig.db` stale after migration) reports just its own
    /// degraded source rather than nuking the entire fan-out.
    struct DocsFetchersResult {
        /// Source-id → opened `SearchModule.Index`. One entry per
        /// per-source DB that opened successfully.
        let indexes: [String: SearchModule.Index]
        /// Source-id → open-time failure reason. One entry per
        /// per-source DB that exists on disk but failed to open.
        /// Source-ids whose DB legitimately doesn't exist on disk
        /// (samples-only path) DO NOT appear here.
        let disabledReasonsBySource: [String: String]
    }

    /// Pure URL-resolution helper extracted from `openDocsFetchers` so
    /// the per-source vs. override mapping can be unit-tested without
    /// touching SQLite. Returns one entry per docs source whose
    /// `SourceProvider` exists in `providerByID`; sources without a
    /// registered provider are dropped (caller logs separately).
    ///
    /// - Parameters:
    ///   - override: when non-nil, every docs source-id maps to this
    ///     single URL (legacy `--search-db` back-compat path; the
    ///     openedByPath cache in `openDocsFetchers` collapses the six
    ///     entries to one Index open).
    ///   - providerByID: source-id → registered `SourceProvider`.
    ///     Built from `CLIImpl.makeProductionSourceRegistry()`'s
    ///     `allEnabled` list.
    ///   - baseDirectory: cupertino's base directory (resolved at the
    ///     composition root via `Shared.Paths.live().baseDirectory`).
    ///   - sources: docs-source prefixes to resolve. Defaults to
    ///     `docsSources` (the production list).
    static func urlsByDocsSourceID(
        override: URL?,
        providerByID: [String: any Search.SourceProvider],
        baseDirectory: URL,
        sources: [(prefix: String, includeArchive: Bool)]? = nil
    ) -> [String: URL] {
        let effective = sources ?? Self.docsSources()
        var result: [String: URL] = [:]
        for source in effective {
            if let override {
                result[source.prefix] = override
            } else if let provider = providerByID[source.prefix] {
                result[source.prefix] = baseDirectory.appendingPathComponent(provider.destinationDB.filename)
            }
        }
        return result
    }

    /// The lookup key the smart-report path uses to find the apple-docs
    /// `SearchModule.Index` for framework-name validation. Pulled into a
    /// static constant so tests can pin the contract (`runUnifiedSearch`
    /// reads `plan.docsIndexes[Search.frameworkValidationSourceID]`;
    /// swapping the constant to a DB id like "apple-documentation" by
    /// mistake would silently skip every `--framework` check, and a
    /// test that asserts the constant catches the regression).
    static let frameworkValidationSourceID: String = Shared.Constants.SourcePrefix.appleDocs

    private static func openDocsFetchers(
        override: String?,
        skip: Bool,
        availability: SearchModels.Search.AvailabilityFilter?,
        framework: String?,
        into fetchers: inout [any Search.CandidateFetcher]
    ) async -> DocsFetchersResult {
        guard !skip else { return DocsFetchersResult(indexes: [:], disabledReasonsBySource: [:]) }

        // Resolve per-source DBs via the production source registry:
        // each `SourceProvider.destinationDB.filename` carries its own
        // DB filename, so adding a new docs source post-this-refactor
        // is still a 2-file PR (descriptor + indexer concrete) with
        // zero edits here.
        let registry = CLIImpl.makeProductionSourceRegistry()
        let providerByID: [String: any Search.SourceProvider] = Dictionary(
            uniqueKeysWithValues: registry.allEnabled.map { ($0.definition.id, $0) }
        )
        let baseDirectory = Shared.Paths.live().baseDirectory

        // #1042 Cluster 4 wiring: derive the CandidateFetcher capability
        // sets from each registered provider's `Search.Capabilities`
        // metadata, instead of letting the fetchers fall back to the
        // 5-source hardcoded defaults. A new registered source's
        // `hasMinSwiftVersion` / `hasFrameworkColumn` flags now reach
        // the availability + framework filtering paths automatically.
        let swiftVersionSourceIDs: Set<String> = Set(
            registry.allEnabled
                .filter { $0.capabilities.metadata[.hasMinSwiftVersion] == true }
                .map(\.definition.id)
        )
        let frameworkScopedSourceIDs: Set<String> = Set(
            registry.allEnabled
                .filter { $0.capabilities.metadata[.hasFrameworkColumn] == true }
                .map(\.definition.id)
        )

        // Honour the legacy `--search-db` override for back-compat:
        // when set, every docs source points at that single DB. Useful
        // for tests + the migration window when a user hasn't re-run
        // `cupertino save` post-#1037 yet. When nil (the common case),
        // each source resolves to its own per-source DB.
        let overrideURL = override.map { URL(fileURLWithPath: $0).expandingTildeInPath }

        // Pure URL resolution: per-source filename via the registry,
        // or the override URL applied uniformly. Tested directly in
        // `CLISearchUrlResolutionTests`.
        let urlsBySource = urlsByDocsSourceID(
            override: overrideURL,
            providerByID: providerByID,
            baseDirectory: baseDirectory
        )

        var indexes: [String: SearchModule.Index] = [:]
        var disabledReasons: [String: String] = [:]

        // Cache opens by URL path so the override path opens a single
        // Index reused across all 6 source-prefixes; per-source path
        // opens one Index per file (one per source). `missingPaths`
        // dedups the file-missing warning so an override pointing at
        // a non-existent file emits one diagnostic instead of six
        // (the override path collapses every source-prefix to the
        // same URL).
        var openedByPath: [String: SearchModule.Index] = [:]
        var failedByPath: [String: String] = [:]
        var missingPaths: Set<String> = []

        for source in Self.docsSources() {
            guard let url = urlsBySource[source.prefix] else {
                // Unknown source-id (shouldn't happen for built-in
                // sources; defensive log + skip).
                Cupertino.Context.composition.logging.recording.warning(
                    "ℹ️  No registered SourceProvider for '\(source.prefix)' -- skipping."
                )
                continue
            }

            if let existing = openedByPath[url.path] {
                fetchers.append(Search.DocsSourceCandidateFetcher(
                    searchIndex: existing,
                    source: source.prefix,
                    includeArchive: source.includeArchive,
                    availability: availability,
                    framework: framework,
                    swiftVersionSources: swiftVersionSourceIDs,
                    frameworkScopedSources: frameworkScopedSourceIDs
                ))
                indexes[source.prefix] = existing
                continue
            }

            if let reason = failedByPath[url.path] {
                disabledReasons[source.prefix] = reason
                continue
            }

            if missingPaths.contains(url.path) {
                continue
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                // #654 -- file-missing diagnostic goes to stderr so
                // `--format json` stdout stays pure for `jq` consumers.
                Cupertino.Context.composition.logging.recording.warning(
                    "ℹ️  \(url.lastPathComponent) not found at \(url.path) -- skipping \(source.prefix)."
                )
                missingPaths.insert(url.path)
                continue
            }

            do {
                // #932: read-only smart-report path; no `indexItem` dispatch happens.
                let index = try await SearchModule.Index(
                    dbPath: url,
                    logger: Cupertino.Context.composition.logging.recording,
                    indexers: [:],
                    sourceLookup: .empty
                )
                fetchers.append(Search.DocsSourceCandidateFetcher(
                    searchIndex: index,
                    source: source.prefix,
                    includeArchive: source.includeArchive,
                    availability: availability,
                    framework: framework,
                    swiftVersionSources: swiftVersionSourceIDs,
                    frameworkScopedSources: frameworkScopedSourceIDs
                ))
                indexes[source.prefix] = index
                openedByPath[url.path] = index
            } catch {
                Cupertino.Context.composition.logging.recording.error(
                    "⚠️  Could not open \(url.lastPathComponent): \(error.localizedDescription)"
                )
                // #648 (CLI JSON path) -- file present + open failed is
                // a configuration error per-source. Classify with the
                // same patterns SmartQuery / UnifiedSearchService use
                // (#640 / #642) and record per-source so
                // `augmentWithOpenTimeDegradation` synthesises the
                // matching `DegradedSource` entry. Mirrors #648
                // (open-time) / PR #652 on the MCP side, lifted
                // post-#1037 to per-source granularity.
                let reason = SearchModule.SmartQuery.classifyDegradation(error)
                    ?? "search index initialisation failed: \(error.localizedDescription)"
                disabledReasons[source.prefix] = reason
                failedByPath[url.path] = reason
            }
        }

        return DocsFetchersResult(indexes: indexes, disabledReasonsBySource: disabledReasons)
    }

    private static func openPackagesFetcher(
        override: String?,
        skip: Bool,
        availability: SearchModels.Search.AvailabilityFilter?,
        appleImport: String?,
        into fetchers: inout [any Search.CandidateFetcher]
    ) {
        guard !skip else { return }
        let url = override.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Paths.live().packagesDatabase
        guard FileManager.default.fileExists(atPath: url.path) else {
            // #654 -- see openDocsFetchers above. Stderr keeps `--format
            // json` stdout pure for `jq` consumers.
            Cupertino.Context.composition.logging.recording.warning(
                "ℹ️  packages.db not found at \(url.path) -- skipping packages."
            )
            return
        }
        fetchers.append(SearchModule.PackageFTSCandidateFetcher(
            dbPath: url,
            availability: availability,
            appleImport: appleImport
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
            // #654 -- see openDocsFetchers above. Stderr keeps `--format
            // json` stdout pure for `jq` consumers.
            Cupertino.Context.composition.logging.recording.warning(
                "ℹ️  samples.db not found at \(url.path) -- skipping samples."
            )
            return nil
        }
        do {
            // #1194: smart-search samples fetcher is a read path; open read-only.
            let database = try await Sample.Index.Database(dbPath: url, logger: Cupertino.Context.composition.logging.recording, readOnly: true)
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
            // never lose data -- they can truncate themselves if needed.
            printSmartReportJSON(result: result, question: question)
        }
    }

    /// First N non-blank lines of a chunk, used by `--brief` mode. Default
    /// 12 -- enough context to actually understand what each result is about
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
        // #640 -- surface configuration-error sources before the body so
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
        print("See also -- drill into one source:")
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
            + CLIImpl.makeProductionSourceRegistry().allEnabled.map(\.definition.id).joined(separator: ", "))
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
            Self.unfilteredSourcesUnderPlatformFlag().contains($0)
        }
        guard !unfiltered.isEmpty else { return }
        print(
            "ℹ️  --platform \(platform) --min-version \(minVersion) doesn't apply to "
                + unfiltered.joined(separator: ", ")
                + " -- those sources use a different availability axis "
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
        // #640 -- schema-mismatch / DB-unopenable warning at the top so
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
        print("**See also -- drill into one source:**")
        print("")
        for source in result.contributingSources {
            print("- `cupertino search \"\(question)\" --source \(source)`")
        }
        print("")
    }

    private static func printTipsFooterMarkdown(availabilityFilterActive: Bool) {
        let sources = CLIImpl.makeProductionSourceRegistry().allEnabled.map(\.definition.id).joined(separator: ", ")
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
            Self.unfilteredSourcesUnderPlatformFlag().contains($0)
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
            /// today -- read directly from `~/.cupertino/packages/<id>`).
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
        // #1042 audit + wiring batch 3: registry-derived "is this a
        // known source?" gate. Pre-fix the switch enumerated 8
        // hardcoded source-ids; a new registered source would fall
        // through to `default → nil` (no read command generated). Now
        // any source-id appearing in the production registry generates
        // a `cupertino read <id> --source <name>` command.
        let registry = CLIImpl.makeProductionSourceRegistry()
        let knownIDs = Set(registry.allEnabled.map(\.definition.id))
        guard knownIDs.contains(candidate.source) else { return nil }
        return "cupertino read \(candidate.identifier) --source \(candidate.source)"
    }
}
