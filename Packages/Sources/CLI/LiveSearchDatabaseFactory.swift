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

// MARK: - Production Search.DatabaseFactory

// Concrete `Search.DatabaseFactory` (GoF Factory Method, 1994 p. 107)
// wired into every `Services.ServiceContainer.with*Service` and
// `Services.ReadService` call. Production wiring opens a
// `SearchModule.Index` at the resolved path — `Search.Index` conforms
// to `Search.Database` (the protocol in SearchModels) so the concrete
// actor flows through Services' protocol-typed inits unchanged.
//
// Each command's `run()` method constructs a fresh instance at its
// own composition sub-root rather than reaching for a shared
// module-scope handle. The struct is stateless, so multiple instances
// are equivalent and a Singleton (p. 127) would add no value while
// pulling in the global-access drawback (Seemann, *Dependency
// Injection*, 2011, ch. 5: Service Locator anti-pattern).

struct LiveSearchDatabaseFactory: Search.DatabaseFactory {
    func openDatabase(at url: URL) async throws -> any Search.Database {
        // #932: factory feeds read-only consumers (MCP serve, smart-search,
        // doctor, etc.). Indexing happens through `cupertino save` which has
        // its own production-dict composition site; this factory's
        // consumers never call `indexItem`. Empty dict is the honest
        // dependency declaration for read paths.
        // #1194: open read-only so a query connection cannot write or delete
        // rows. Every consumer of this factory is a read path.
        try await SearchModule.Index(dbPath: url, logger: Cupertino.Context.composition.logging.recording, indexers: [:], sourceLookup: .empty, readOnly: true)
    }
}
