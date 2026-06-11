import Foundation
import LoggingModels
import SearchModels
import SearchSchema
import SharedConstants
import SQLite3
import SQLiteSupport

public extension Search {
    actor Indexer: Search.Database {
        public static let schemaVersion: Int32 = Search.Schema.currentVersion
        public nonisolated let connection: Search.Connection
        public nonisolated var dbPath: URL {
            connection.dbPath
        }

        var database: OpaquePointer? {
            connection.database
        }

        var isInitialized: Bool {
            connection.isInitialized
        }

        let logger: any LoggingModels.Logging.Recording
        public nonisolated let indexers: [String: any Search.SourceIndexer]
        public nonisolated let sourceLookup: Search.SourceLookup

        public internal(set) var incrementalSkips = 0

        public let reader: Search.Index

        public init(
            connection: Search.Connection,
            logger: any LoggingModels.Logging.Recording,
            indexers: [String: any Search.SourceIndexer],
            sourceLookup: Search.SourceLookup
        ) {
            self.connection = connection
            self.logger = logger
            self.indexers = indexers
            self.sourceLookup = sourceLookup
            reader = Search.Index(
                connection: connection,
                logger: logger,
                indexers: indexers,
                sourceLookup: sourceLookup
            )
        }

        public init(
            dbPath: URL,
            logger: any LoggingModels.Logging.Recording,
            indexers: [String: any Search.SourceIndexer],
            sourceLookup: Search.SourceLookup
        ) async throws {
            let connection = Search.Connection(dbPath: dbPath, logger: logger, readOnly: false)
            try connection.connect()

            self.connection = connection
            self.logger = logger
            self.indexers = indexers
            self.sourceLookup = sourceLookup
            reader = Search.Index(
                connection: connection,
                logger: logger,
                indexers: indexers,
                sourceLookup: sourceLookup
            )

            try await checkAndMigrateSchema()
            try await createTables()
            try await setSchemaVersion()
        }

        public func disconnect() {
            connection.disconnect()
        }

        // MARK: - Search.Database delegation (forwarding to reader)

        public func search(
            query: String,
            source: String?,
            framework: String?,
            language: String?,
            limit: Int,
            includeArchive: Bool,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?,
            minSwift: String?
        ) async throws -> [Search.Result] {
            try await reader.search(
                query: query,
                source: source,
                framework: framework,
                language: language,
                limit: limit,
                includeArchive: includeArchive,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )
        }

        public func getDocumentContent(uri: String, format: Search.DocumentFormat) async throws -> String? {
            try await reader.getDocumentContent(uri: uri, format: format)
        }

        public func listFrameworks() async throws -> [String: Int] {
            try await reader.listFrameworks()
        }

        public func documentCount() async throws -> Int {
            try await reader.documentCount()
        }

        public func searchSymbols(
            query: String?,
            kind: String?,
            isAsync: Bool?,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchSymbols(query: query, kind: kind, isAsync: isAsync, framework: framework, limit: limit)
        }

        public func searchPropertyWrappers(
            wrapper: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchPropertyWrappers(wrapper: wrapper, framework: framework, limit: limit)
        }

        public func searchConcurrencyPatterns(
            pattern: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchConcurrencyPatterns(pattern: pattern, framework: framework, limit: limit)
        }

        public func searchConformances(
            protocolName: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchConformances(protocolName: protocolName, framework: framework, limit: limit)
        }

        public func searchByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchByGenericConstraint(constraint: constraint, framework: framework, limit: limit)
        }

        public func resolveSymbolURIs(title: String) async throws -> [Search.InheritanceCandidate] {
            try await reader.resolveSymbolURIs(title: title)
        }

        public func walkInheritance(
            startURI: String,
            direction: Search.InheritanceDirection,
            maxDepth: Int
        ) async throws -> Search.InheritanceTree {
            try await reader.walkInheritance(startURI: startURI, direction: direction, maxDepth: maxDepth)
        }

        public func fetchPlatformMinima(
            uris: [String]
        ) async throws -> [String: Search.PlatformMinima] {
            try await reader.fetchPlatformMinima(uris: uris)
        }

        public func getFrameworkAvailability(
            framework: String
        ) async -> Search.FrameworkAvailability {
            await reader.getFrameworkAvailability(framework: framework)
        }

        public func listResourceEntries(mode: Search.ResourceListMode) async throws -> [Search.URIResource] {
            try await reader.listResourceEntries(mode: mode)
        }
    }
}
