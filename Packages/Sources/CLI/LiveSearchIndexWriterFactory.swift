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

// MARK: - Production Search.IndexWriterFactory

// Concrete `Search.IndexWriterFactory` (GoF Factory Method, 1994 p. 107)
// placeholder for the write side. Introduced by #897 alongside the
// rewire that switched `Search.IndexBuilder.init`'s `searchIndex:`
// parameter from the concrete `Search.Index` type to
// `any Search.Database & Search.IndexWriter`. Mirrors
// `LiveSearchDatabaseFactory`'s shape but is NOT yet wired into any
// production call site: every existing `Search.IndexBuilder`
// construction call site holds a `SearchModule.Index` instance and
// passes it directly to the composed-protocol init parameter
// (`Search.Index` conforms via the witness extension in
// `Search.Index.IndexWriter.swift`). The factory exists as the seam
// for future call sites that prefer the Factory Method abstraction,
// mirroring how `LiveSearchDatabaseFactory` is consumed by
// `Services.ServiceContainer` today.

struct LiveSearchIndexWriterFactory: Search.IndexWriterFactory {
    func openWriter(at url: URL) async throws -> any Search.IndexWriter {
        // #932: write factory but not the indexItem-dispatch surface.
        // The 7 strategies in `Search.IndexBuilder` call lower-level write
        // APIs (`indexStructuredDocument`, `indexCodeExamples`, etc.), not
        // `indexItem`. Empty dict is correct; the only production
        // `indexItem` consumer (when it lands, e.g. #58 WWDC) will use the
        // explicit dict assembled in `CLIImpl.Command.Save.Indexers.swift`.
        try await SearchModule.Index(dbPath: url, logger: Cupertino.Context.composition.logging.recording, indexers: [:], sourceLookup: .empty)
    }
}
