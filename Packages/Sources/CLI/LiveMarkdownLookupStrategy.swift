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
import Search
import SearchModels
import SearchSQLite
import Services
import ServicesModels
import SharedConstants

// MARK: - Production MarkdownLookupStrategy

// Concrete `MCP.Support.DocsResourceProvider.MarkdownLookupStrategy`
// wrapping a `SearchModule.Index` actor's `getDocumentContent(uri:format:)`.
// Wired by `cupertino serve` when a search.db is available so the MCP
// resource provider can fall back to indexed markdown before going to
// the filesystem. MCPSupport stays free of `import Search`; only the
// CLI composition root reaches the actor.

struct LiveMarkdownLookupStrategy: MCP.Support.MarkdownLookupStrategy {
    let searchIndex: SearchModule.Index

    func lookup(uri: String) async throws -> String? {
        try await searchIndex.getDocumentContent(uri: uri, format: .markdown)
    }
}
