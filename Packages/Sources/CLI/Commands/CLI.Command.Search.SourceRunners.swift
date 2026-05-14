import ArgumentParser
import Foundation
import Logging
import LoggingModels
import Search
import SearchModels
import Services
import ServicesModels
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Per-source runners

/// `--source <name>` paths split out of `CLI.Command.Search` so the struct body
/// stays under SwiftLint's `type_body_length` ceiling. The default
/// (no `--source`) fan-out + chunked report lives in
/// `CLI.Command.Search+SmartReport.swift` (#239).
extension CLI.Command.Search {
    func runDocsSearch() async throws {
        // GoF Factory Method (1994 p. 107): the search command's
        // composition sub-root. Each per-source runner constructs its
        // own stateless factories so no caller has to reach for a
        // shared module-scope handle.
        let searchDatabaseFactory: any SearchModule.DatabaseFactory = LiveSearchDatabaseFactory()
        let sampleDatabaseFactory: any Sample.Index.DatabaseFactory = LiveSampleIndexDatabaseFactory()

        let results = try await Services.ServiceContainer.withDocsService(dbPath: searchDb, searchDatabaseFactory: searchDatabaseFactory) { service in
            try await service.search(Services.SearchQuery(
                text: query,
                source: source,
                framework: framework,
                language: language,
                limit: limit,
                includeArchive: includeArchive,
                minimumiOS: minIos,
                minimumMacOS: minMacos,
                minimumTvOS: minTvos,
                minimumWatchOS: minWatchos,
                minimumVisionOS: minVisionos
            ))
        }

        let teasers = try await Services.ServiceContainer.withTeaserService(
            searchDbPath: searchDb,
            sampleDbPath: resolveSampleDbPath(),
            searchDatabaseFactory: searchDatabaseFactory,
            sampleDatabaseFactory: sampleDatabaseFactory
        ) { service in
            await service.fetchAllTeasers(
                query: query,
                framework: framework,
                currentSource: source,
                includeArchive: includeArchive
            )
        }

        switch format {
        case .text:
            let formatter = Services.Formatter.Text(
                query: query,
                source: source,
                teasers: teasers
            )
            Logging.LiveRecording().output(formatter.format(results))
        case .json:
            let formatter = Services.Formatter.JSON()
            Logging.LiveRecording().output(formatter.format(results))
        case .markdown:
            let formatter = Services.Formatter.Markdown(
                query: query,
                filters: Services.SearchFilters(
                    source: source,
                    framework: framework,
                    language: language,
                    minimumiOS: minIos,
                    minimumMacOS: minMacos,
                    minimumTvOS: minTvos,
                    minimumWatchOS: minWatchos,
                    minimumVisionOS: minVisionos
                ),
                config: .cliDefault,
                teasers: teasers
            )
            Logging.LiveRecording().output(formatter.format(results))
        }
    }

    func runSampleSearch() async throws {
        // GoF Factory Method (1994 p. 107): composition sub-root.
        let searchDatabaseFactory: any SearchModule.DatabaseFactory = LiveSearchDatabaseFactory()
        let sampleDatabaseFactory: any Sample.Index.DatabaseFactory = LiveSampleIndexDatabaseFactory()

        let dbPath = resolveSampleDbPath()

        let result = try await Services.ServiceContainer.withSampleService(dbPath: dbPath, sampleDatabaseFactory: sampleDatabaseFactory) { service in
            try await service.search(Sample.Search.Query(
                text: query,
                framework: framework,
                searchFiles: true,
                limit: limit
            ))
        }

        // Best-effort teaser fetch: when search.db is locked (typically
        // another process running `cupertino save --docs`) or missing, log
        // and fall back to empty teasers rather than aborting the samples
        // query (#237).
        let teasers: Services.Formatter.TeaserResults
        do {
            teasers = try await Services.ServiceContainer.withTeaserService(
                searchDbPath: searchDb,
                sampleDbPath: resolveSampleDbPath(),
                searchDatabaseFactory: searchDatabaseFactory,
                sampleDatabaseFactory: sampleDatabaseFactory
            ) { service in
                await service.fetchAllTeasers(
                    query: query,
                    framework: framework,
                    currentSource: Shared.Constants.SourcePrefix.samples,
                    includeArchive: false
                )
            }
        } catch {
            Logging.LiveRecording().info(
                "ℹ️  Teaser results from other sources unavailable: \(error.localizedDescription) "
                    + "(common when another process is writing search.db). "
                    + "Continuing with samples results only."
            )
            teasers = Services.Formatter.TeaserResults()
        }

        switch format {
        case .text:
            let formatter = Sample.Format.Text.Search(query: query, framework: framework, teasers: teasers)
            Logging.LiveRecording().output(formatter.format(result))
        case .json:
            let formatter = Sample.Format.JSON.Search(query: query, framework: framework)
            Logging.LiveRecording().output(formatter.format(result))
        case .markdown:
            let formatter = Sample.Format.Markdown.Search(query: query, framework: framework, teasers: teasers)
            Logging.LiveRecording().output(formatter.format(result))
        }
    }

    /// Single-source view for `--source packages`. Packages live in their
    /// own DB (`packages.db`), so this can't share `runDocsSearch`'s code
    /// path against `search.db`. Mirrors the unified-search shape exactly:
    /// a SmartQuery wrapped around one `PackageFTSCandidateFetcher`,
    /// rendered through the same `printSmartReport` formatter the default
    /// path uses. Output JSON is therefore the unified
    /// `{candidates, contributingSources, question}` shape with
    /// `contributingSources: ["packages"]`. (#261)
    func runPackageSearch() async throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logging.LiveRecording().error("❌ Query cannot be empty.")
            throw ExitCode.failure
        }

        let dbURL = packagesDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultPackagesDatabase

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            Logging.LiveRecording().error("❌ packages.db not found at \(dbURL.path)")
            Logging.LiveRecording().error("   Run `cupertino setup` to download it, or `cupertino save --packages` to build locally.")
            throw ExitCode.failure
        }

        let availabilityFilter = try resolveAvailabilityFilter()
        let fetcher = SearchModule.PackageFTSCandidateFetcher(
            dbPath: dbURL,
            availability: availabilityFilter
        )
        let smartQuery = SearchModule.SmartQuery(fetchers: [fetcher])
        let result = await smartQuery.answer(
            question: trimmed,
            limit: limit,
            perFetcherLimit: max(20, perSource)
        )

        Self.printSmartReport(
            result: result,
            question: trimmed,
            availabilityFilterActive: availabilityFilter != nil,
            platform: platform,
            minVersion: minVersion,
            format: format,
            brief: brief
        )
    }

    func runHIGSearch() async throws {
        // GoF Factory Method (1994 p. 107): composition sub-root.
        let searchDatabaseFactory: any SearchModule.DatabaseFactory = LiveSearchDatabaseFactory()
        let sampleDatabaseFactory: any Sample.Index.DatabaseFactory = LiveSampleIndexDatabaseFactory()

        let results = try await Services.ServiceContainer.withDocsService(dbPath: searchDb, searchDatabaseFactory: searchDatabaseFactory) { service in
            try await service.search(Services.SearchQuery(
                text: query,
                source: Shared.Constants.SourcePrefix.hig,
                framework: nil,
                language: nil,
                limit: limit,
                includeArchive: false
            ))
        }

        let teasers = try await Services.ServiceContainer.withTeaserService(
            searchDbPath: searchDb,
            sampleDbPath: resolveSampleDbPath(),
            searchDatabaseFactory: searchDatabaseFactory,
            sampleDatabaseFactory: sampleDatabaseFactory
        ) { service in
            await service.fetchAllTeasers(
                query: query,
                framework: framework,
                currentSource: Shared.Constants.SourcePrefix.hig,
                includeArchive: false
            )
        }

        let higQuery = Services.HIGQuery(text: query, platform: nil, category: nil)

        switch format {
        case .text:
            let formatter = Services.Formatter.HIG.Text(query: higQuery, teasers: teasers)
            Logging.LiveRecording().output(formatter.format(results))
        case .json:
            let formatter = Services.Formatter.HIG.JSON(query: higQuery)
            Logging.LiveRecording().output(formatter.format(results))
        case .markdown:
            let formatter = Services.Formatter.HIG.Markdown(query: higQuery, config: .cliDefault, teasers: teasers)
            Logging.LiveRecording().output(formatter.format(results))
        }
    }
}
