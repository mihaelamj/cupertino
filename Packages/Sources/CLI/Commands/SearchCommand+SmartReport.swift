import ArgumentParser
import Foundation
import Logging
import SampleIndex
import Search
import Services
import Shared

// MARK: - SmartQuery fan-out helpers (#239)

/// Helpers for `SearchCommand`'s default (no `--source`) path: building the
/// per-DB `CandidateFetcher` list, then printing the fused result in
/// text / markdown / json. Lifted out of `SearchCommand.swift` so the
/// struct body stays under SwiftLint's `type_body_length` ceiling and so
/// the printers don't need access to instance-level CLI options.
extension SearchCommand {
    /// Bundle returned by `buildFetchers`. The `searchIndex` and
    /// `sampleService` references are kept so the caller can disconnect
    /// them once the SmartQuery has run — the fetchers don't own those
    /// connections.
    struct FetcherPlan {
        let fetchers: [any Search.CandidateFetcher]
        let searchIndex: Search.Index?
        let sampleService: Services.SampleSearchService?
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
    func resolveAvailabilityFilter() throws -> Search.PackageQuery.AvailabilityFilter? {
        switch (platform, minVersion) {
        case let (platform?, minVersion?):
            return Search.PackageQuery.AvailabilityFilter(
                platform: platform,
                minVersion: minVersion
            )
        case (.some, nil), (nil, .some):
            Logging.ConsoleLogger.error(
                "❌ --platform and --min-version must be used together (#220)."
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
        availabilityFilter: Search.PackageQuery.AvailabilityFilter?
    ) async -> FetcherPlan {
        var fetchers: [any Search.CandidateFetcher] = []

        let searchIndex = await Self.openDocsFetchers(
            override: searchDb,
            skip: skipDocs,
            availability: availabilityFilter,
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
            searchIndex: searchIndex,
            sampleService: sampleService
        )
    }

    private static func openDocsFetchers(
        override: String?,
        skip: Bool,
        availability: Search.PackageQuery.AvailabilityFilter?,
        into fetchers: inout [any Search.CandidateFetcher]
    ) async -> Search.Index? {
        guard !skip else { return nil }
        let url = override.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultSearchDatabase
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logging.ConsoleLogger.info(
                "ℹ️  search.db not found at \(url.path) — skipping doc sources."
            )
            return nil
        }
        do {
            let index = try await Search.Index(dbPath: url)
            for source in docsSources {
                fetchers.append(Search.DocsSourceCandidateFetcher(
                    searchIndex: index,
                    source: source.prefix,
                    includeArchive: source.includeArchive,
                    availability: availability
                ))
            }
            return index
        } catch {
            Logging.ConsoleLogger.error(
                "⚠️  Could not open search.db: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private static func openPackagesFetcher(
        override: String?,
        skip: Bool,
        availability: Search.PackageQuery.AvailabilityFilter?,
        into fetchers: inout [any Search.CandidateFetcher]
    ) {
        guard !skip else { return }
        let url = override.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultPackagesDatabase
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logging.ConsoleLogger.info(
                "ℹ️  packages.db not found at \(url.path) — skipping packages."
            )
            return
        }
        fetchers.append(Search.PackageFTSCandidateFetcher(
            dbPath: url,
            availability: availability
        ))
    }

    private static func openSamplesFetcher(
        override: String?,
        skip: Bool,
        availability: Search.PackageQuery.AvailabilityFilter?,
        into fetchers: inout [any Search.CandidateFetcher]
    ) async -> Services.SampleSearchService? {
        guard !skip else { return nil }
        let url = override.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? SampleIndex.defaultDatabasePath
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logging.ConsoleLogger.info(
                "ℹ️  samples.db not found at \(url.path) — skipping samples."
            )
            return nil
        }
        do {
            let service = try await Services.SampleSearchService(dbPath: url)
            fetchers.append(Services.SampleCandidateFetcher(
                service: service,
                availability: availability
            ))
            return service
        } catch {
            Logging.ConsoleLogger.error(
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
        format: OutputFormat
    ) {
        switch format {
        case .text:
            printSmartReportText(
                result: result,
                question: question,
                availabilityFilterActive: availabilityFilterActive,
                platform: platform,
                minVersion: minVersion
            )
        case .markdown:
            printSmartReportMarkdown(
                result: result,
                question: question,
                availabilityFilterActive: availabilityFilterActive,
                platform: platform,
                minVersion: minVersion
            )
        case .json:
            printSmartReportJSON(result: result, question: question)
        }
    }

    private static func printSmartReportText(
        result: Search.SmartResult,
        question: String,
        availabilityFilterActive: Bool,
        platform: String?,
        minVersion: String?
    ) {
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
            print(cand.chunk)
            print("")
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
                + "(Swift language version, see #225). apple-docs / apple-archive / hig / "
                + "packages / samples results ARE filtered."
        )
    }

    private static func printSmartReportMarkdown(
        result: Search.SmartResult,
        question: String,
        availabilityFilterActive: Bool,
        platform: String?,
        minVersion: String?
    ) {
        print("# Results for `\(question)`")
        print("")
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
            print("")
            print(cand.chunk)
            print("")
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
                + " (Swift language version axis, #225)."
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
        }
        struct ReportOut: Encodable {
            let question: String
            let contributingSources: [String]
            let candidates: [CandidateOut]
        }
        let report = ReportOut(
            question: question,
            contributingSources: result.contributingSources,
            candidates: result.candidates.enumerated().map { idx, fused in
                CandidateOut(
                    rank: idx + 1,
                    source: fused.candidate.source,
                    identifier: fused.candidate.identifier,
                    title: fused.candidate.title,
                    chunk: fused.candidate.chunk,
                    score: fused.score,
                    kind: fused.candidate.kind,
                    metadata: fused.candidate.metadata
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report),
           let json = String(data: data, encoding: .utf8) {
            Log.output(json)
        }
    }
}
