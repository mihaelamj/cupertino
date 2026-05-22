import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - Search.makeDefaultStrategies

/// Build the default strategy array for the standard six documentation
/// sources. Lifted from `Search.IndexBuilder.makeDefaultStrategies` to
/// this `SearchStrategies` target by #899 so the orchestration `Search`
/// target stays free of any concrete strategy dependency. Composition
/// roots call `Search.makeDefaultStrategies(...)` then pass the
/// resulting array to `Search.IndexBuilder.init(searchIndex:strategies:...)`.
///
/// Optional sources are only included when their directory parameter is
/// non-nil. Sample code indexing is conditional on `indexSampleCode`.
extension Search {
    public static func makeDefaultStrategies(
        metadata: Shared.Models.CrawlMetadata?,
        docsDirectory: URL,
        evolutionDirectory: URL? = nil,
        swiftOrgDirectory: URL? = nil,
        archiveDirectory: URL? = nil,
        higDirectory: URL? = nil,
        indexSampleCode: Bool = true,
        markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
        sampleCatalogProvider: any Search.SampleCatalogProvider,
        logger: any LoggingModels.Logging.Recording,
        importLogSink: (any Search.ImportLogSink)? = nil
    ) -> [any Search.SourceIndexingStrategy] {
        _ = metadata // reserved for future per-source metadata routing
        var strategies: [any Search.SourceIndexingStrategy] = [
            Search.AppleDocsStrategy(
                docsDirectory: docsDirectory,
                markdownStrategy: markdownStrategy,
                logger: logger,
                importLogSink: importLogSink
            ),
        ]
        if let dir = evolutionDirectory {
            strategies.append(Search.SwiftEvolutionStrategy(evolutionDirectory: dir, logger: logger))
        }
        if let dir = swiftOrgDirectory {
            strategies.append(Search.SwiftOrgStrategy(
                swiftOrgDirectory: dir,
                markdownStrategy: markdownStrategy,
                logger: logger
            ))
        }
        if let dir = archiveDirectory {
            strategies.append(Search.AppleArchiveStrategy(archiveDirectory: dir, logger: logger))
        }
        if let dir = higDirectory {
            strategies.append(Search.HIGStrategy(higDirectory: dir, logger: logger))
        }
        if indexSampleCode {
            strategies.append(Search.SampleCodeStrategy(sampleCatalogProvider: sampleCatalogProvider, logger: logger))
        }
        // #789: SwiftPackagesStrategy + the search.db `packages` /
        // `package_dependencies` tables removed. The canonical packages
        // store is `packages.db` (built by `cupertino save --packages`,
        // queried by `cupertino package-search`); the in-search.db tables
        // were always a shallow duplicate fed from a slimmed-to-empty
        // bundled catalog and added zero value over packages.db.
        return strategies
    }
}
