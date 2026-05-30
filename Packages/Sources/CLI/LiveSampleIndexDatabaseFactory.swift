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

// MARK: - Production Sample.Index.DatabaseFactory

// Concrete `Sample.Index.DatabaseFactory` (GoF Factory Method) wired
// into every `Services.ServiceContainer.with*SampleService` /
// `withTeaserService` / `withUnifiedSearchService` call. Parallel to
// `LiveSearchDatabaseFactory` on the docs side: opens a real
// `Sample.Index.Database` at the resolved path. `Services` builds the
// `Sample.Search.Service` wrapper internally — the composition root
// only knows about the low-level DB factory. `Services` no longer
// imports `SampleIndex`; the concrete actor is reached only here.

struct LiveSampleIndexDatabaseFactory: Sample.Index.DatabaseFactory {
    func openDatabase(at url: URL) async throws -> any Sample.Index.Reader {
        // #1194: every consumer of this factory is a read path (read-sample,
        // list-samples, smart-search, serve). Open read-only so a query
        // connection cannot write or delete rows.
        try await Sample.Index.Database(dbPath: url, logger: Cupertino.Context.composition.logging.recording, readOnly: true)
    }
}
