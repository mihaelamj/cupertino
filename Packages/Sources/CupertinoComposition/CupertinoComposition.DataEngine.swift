import CupertinoDataEngine
import Foundation
import LoggingModels
import SampleIndexModels
import SampleIndexSQLite
import SearchModels
import SearchSQLite

// MARK: - CupertinoComposition.DataEngine

extension CupertinoComposition {
    /// Per-source database bundle configuration with schema versions supplied
    /// from the concrete database producers at the composition root.
    public static func makePerSourceDataEngineConfiguration(
        baseDirectory: URL
    ) -> CupertinoDataEngine.Configuration {
        CupertinoDataEngine.Configuration.perSourceBundle(
            baseDirectory: baseDirectory,
            searchSchemaVersion: Search.Index.schemaVersion,
            sampleSchemaVersion: Sample.Index.Database.schemaVersion,
            packagesSchemaVersion: Search.PackageIndex.schemaVersion
        )
    }

    /// Legacy three-database bundle configuration with schema versions supplied
    /// from the concrete database producers at the composition root.
    public static func makeLegacyDataEngineConfiguration(
        baseDirectory: URL
    ) -> CupertinoDataEngine.Configuration {
        CupertinoDataEngine.Configuration.legacyBundle(
            baseDirectory: baseDirectory,
            searchSchemaVersion: Search.Index.schemaVersion,
            sampleSchemaVersion: Sample.Index.Database.schemaVersion,
            packagesSchemaVersion: Search.PackageIndex.schemaVersion
        )
    }

    /// Build the read-only embedded data engine using production SQLite-backed
    /// readers. App UI layers should receive the returned engine or its
    /// protocol-typed readers; they should not depend on these factory structs.
    public static func makeReadOnlyDataEngine(
        configuration: CupertinoDataEngine.Configuration,
        logger: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await CupertinoDataEngine(
            configuration: configuration,
            searchDatabaseFactory: DataEngineSearchDatabaseFactory(logger: logger),
            sampleDatabaseFactory: DataEngineSampleDatabaseFactory(logger: logger),
            packageDatabaseFactory: DataEnginePackageDatabaseFactory()
        )
    }

    /// Convenience for the current per-source bundle layout.
    public static func makePerSourceReadOnlyDataEngine(
        baseDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await makeReadOnlyDataEngine(
            configuration: makePerSourceDataEngineConfiguration(baseDirectory: baseDirectory),
            logger: logger
        )
    }

    /// Convenience for the legacy three-file layout used by some local bundles.
    public static func makeLegacyReadOnlyDataEngine(
        baseDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await makeReadOnlyDataEngine(
            configuration: makeLegacyDataEngineConfiguration(baseDirectory: baseDirectory),
            logger: logger
        )
    }
}

private struct DataEngineSearchDatabaseFactory: Search.DatabaseFactory {
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

private struct DataEngineSampleDatabaseFactory: Sample.Index.DatabaseFactory {
    let logger: any Logging.Recording

    func openDatabase(at url: URL) async throws -> any Sample.Index.Reader {
        try await Sample.Index.Database(
            dbPath: url,
            logger: logger,
            readOnly: true
        )
    }
}

private struct DataEnginePackageDatabaseFactory: CupertinoDataEngine.PackageDatabaseFactory {
    func openDatabase(at url: URL) async throws -> any CupertinoDataEngine.PackageConnection {
        let query = try await Search.PackageQuery(dbPath: url)
        return DataEnginePackageDatabase(query: query)
    }
}

private struct DataEnginePackageDatabase: CupertinoDataEngine.PackageConnection {
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
