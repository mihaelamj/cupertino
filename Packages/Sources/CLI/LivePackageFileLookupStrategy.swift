import Core
import CoreJSONParser
import CorePackageIndexing
import CoreProtocols
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
// composition root so `Services` doesn't need `import SearchAPI`.
// `cupertino read` wires one of these into every `Services.ReadService.read`
// call.

/// 2026-05-26 audit #1055: conforms to the canonical
/// `Search.PackageFileLookupStrategy` protocol (in SearchModels)
/// that per-source `PackagesReadStrategy` consumes. The legacy
/// `Services.ReadService.PackageFileLookupStrategy` typealias still
/// points here for back-compat with the existing CLI plumbing.
struct LivePackageFileLookupStrategy: Search.PackageFileLookupStrategy {
    func read(
        packagesDB: URL,
        owner: String,
        repo: String,
        path: String
    ) async throws -> String? {
        let query = try await SearchModule.PackageQuery(dbPath: packagesDB)
        defer { Task { await query.disconnect() } }
        return try await query.fileContent(owner: owner, repo: repo, relpath: path)
    }
}
