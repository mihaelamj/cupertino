@_spi(CupertinoInternal) import CupertinoDataEngine
import Foundation
import LoggingModels
import SampleIndexModels
import SampleIndexSQLite
import SearchModels
import SearchSQLite

// MARK: - CupertinoComposition.DataEngine

extension CupertinoComposition {
    /// Per-source corpus bundle configuration with schema versions supplied
    /// from Cupertino's concrete storage producers at the composition root.
    @_spi(CupertinoInternal)
    public static func makePerSourceDataEngineConfiguration(
        corpusDirectory: URL
    ) -> CupertinoDataEngine.Configuration {
        CupertinoDataEngine.Configuration.perSourceBundle(
            baseDirectory: corpusDirectory,
            searchSchemaVersion: Search.Index.schemaVersion,
            sampleSchemaVersion: Sample.Index.Database.schemaVersion,
            packagesSchemaVersion: Search.PackageIndex.schemaVersion
        )
    }

    /// Legacy corpus bundle configuration with schema versions supplied from
    /// Cupertino's concrete storage producers at the composition root.
    @_spi(CupertinoInternal)
    public static func makeLegacyDataEngineConfiguration(
        corpusDirectory: URL
    ) -> CupertinoDataEngine.Configuration {
        CupertinoDataEngine.Configuration.legacyBundle(
            baseDirectory: corpusDirectory,
            searchSchemaVersion: Search.Index.schemaVersion,
            sampleSchemaVersion: Sample.Index.Database.schemaVersion,
            packagesSchemaVersion: Search.PackageIndex.schemaVersion
        )
    }

    /// Build the read-only embedded data engine using Cupertino's production
    /// storage readers. App UI layers receive the returned engine or its
    /// protocol-typed readers; they do not depend on storage factories.
    @_spi(CupertinoInternal)
    public static func makeReadOnlyDataEngine(
        configuration: CupertinoDataEngine.Configuration,
        logger: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await CupertinoDataEngine(
            configuration: configuration,
            sourceReaderFactory: DataEngineSourceReaderFactory(logger: logger),
            sampleReaderFactory: DataEngineSampleReaderFactory(logger: logger),
            packageReaderFactory: DataEnginePackageReaderFactory()
        )
    }

    /// Convenience for the current per-source bundle layout.
    public static func makePerSourceReadOnlyDataEngine(
        corpusDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await makeReadOnlyDataEngine(
            configuration: makePerSourceDataEngineConfiguration(corpusDirectory: corpusDirectory),
            logger: logger
        )
    }

    /// Convenience for the legacy corpus layout used by some local bundles.
    public static func makeLegacyReadOnlyDataEngine(
        corpusDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await makeReadOnlyDataEngine(
            configuration: makeLegacyDataEngineConfiguration(corpusDirectory: corpusDirectory),
            logger: logger
        )
    }
}

private struct DataEngineSourceReaderFactory: Search.DatabaseFactory {
    let logger: any Logging.Recording

    func openDatabase(at url: URL) async throws -> any Search.Database {
        try await Search.Index(
            dbPath: url,
            logger: logger,
            indexers: [:],
            sourceLookup: .empty,
            readOnly: true
        )
    }
}

private struct DataEngineSampleReaderFactory: Sample.Index.DatabaseFactory {
    let logger: any Logging.Recording

    func openDatabase(at url: URL) async throws -> any Sample.Index.Reader {
        try await Sample.Index.Database(
            dbPath: url,
            logger: logger,
            readOnly: true
        )
    }
}

private struct DataEnginePackageReaderFactory: CupertinoDataEngine.PackageReaderFactory {
    func openPackageReader(at url: URL) async throws -> any CupertinoDataEngine.PackageReader {
        let query = try await Search.PackageQuery(dbPath: url)
        return DataEnginePackageReader(query: query)
    }
}

private struct DataEnginePackageReader: CupertinoDataEngine.PackageReader {
    let query: Search.PackageQuery

    func searchPackages(
        query: String,
        limit: Int,
        availability: Search.AvailabilityFilter?,
        swiftTools: Search.SwiftToolsFilter?,
        appleImport: String?
    ) async throws -> [Search.Result] {
        try await self.query.searchPackages(
            query: query,
            limit: limit,
            availability: availability,
            swiftTools: swiftTools,
            appleImport: appleImport
        )
    }

    func searchPackageSymbolsByGenericConstraint(
        constraint: String,
        framework: String?,
        limit: Int
    ) async throws -> [Search.Result] {
        try await query.searchPackageSymbolsByGenericConstraint(
            constraint: constraint,
            framework: framework,
            limit: limit
        )
    }

    func disconnect() async {
        await query.disconnect()
    }
}
