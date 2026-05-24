import Core
import CoreJSONParser
import CorePackageIndexing
import CoreProtocols
import Crawler
import CrawlerModels
import Foundation
import Logging
import LoggingModels
import MCPCore
import MCPSupport
import SampleIndex
import SampleIndexModels
import SampleIndexSQLite
import SearchAPI
import SearchModels
import SearchSQLite
import Services
import ServicesModels
import SharedConstants

// MARK: - Production Crawler.PriorityPackageStrategy (#505)

// Concrete `Crawler.PriorityPackageStrategy` — wraps
// `Core.PackageIndexing.PriorityPackageGenerator` (an actor). Used
// only when a Swift.org crawl completes and the priority-package
// catalog needs regenerating.

struct LivePriorityPackageStrategy: Crawler.PriorityPackageStrategy {
    func generate(
        swiftOrgDocsPath: URL,
        outputPath: URL
    ) async throws -> Crawler.PriorityPackageOutcome {
        let generator = Core.PackageIndexing.PriorityPackageGenerator(
            swiftOrgDocsPath: swiftOrgDocsPath,
            outputPath: outputPath,
            logger: Cupertino.Context.composition.logging.recording
        )
        let list = try await generator.generate()
        return Crawler.PriorityPackageOutcome(
            totalUniqueReposFound: list.stats.totalUniqueReposFound
        )
    }
}
