import CupertinoDataEngine
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
        logger _: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await CupertinoDataEngine(configuration: configuration)
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
