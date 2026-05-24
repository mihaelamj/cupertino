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

// MARK: - Production PackageFileLookupStrategy

// Concrete `Services.ReadService.PackageFileLookupStrategy` (GoF Strategy)
// wrapping the `SearchModule.PackageQuery` actor. Lives at the CLI
// composition root so `Services` doesn't need `import Search`.
// `cupertino read` wires one of these into every `Services.ReadService.read`
// call.

struct LivePackageFileLookupStrategy: Services.ReadService.PackageFileLookupStrategy {
    func fileContent(
        dbURL: URL,
        owner: String,
        repo: String,
        relpath: String
    ) async throws -> String? {
        let query = try await SearchModule.PackageQuery(dbPath: dbURL)
        defer { Task { await query.disconnect() } }
        return try await query.fileContent(owner: owner, repo: repo, relpath: relpath)
    }
}
