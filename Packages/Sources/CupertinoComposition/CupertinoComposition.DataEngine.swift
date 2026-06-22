import CupertinoDataEngine
import Foundation
import LoggingModels
import SampleIndexModels
import SampleIndexSQLite
import SearchModels
import SearchSQLite

// MARK: - CupertinoComposition.DataEngine

extension CupertinoComposition {
    private static var dataEngineSchemaVersions: CupertinoDataEngine.SchemaVersions {
        CupertinoDataEngine.SchemaVersions(
            search: Search.Index.schemaVersion,
            sample: Sample.Index.Database.schemaVersion,
            packages: Search.PackageIndex.schemaVersion
        )
    }

    /// Opaque current per-source corpus handle with schema versions supplied
    /// from Cupertino's concrete storage producers at the composition root.
    @_spi(CupertinoInternal)
    public static func makePerSourceDataEngineCorpus(
        corpusDirectory: URL
    ) -> CupertinoDataEngine.Corpus {
        CupertinoDataEngine.Corpus.current(
            at: corpusDirectory,
            schemaVersions: dataEngineSchemaVersions
        )
    }

    /// Opaque legacy corpus handle with schema versions supplied from
    /// Cupertino's concrete storage producers at the composition root.
    @_spi(CupertinoInternal)
    public static func makeLegacyDataEngineCorpus(
        corpusDirectory: URL
    ) -> CupertinoDataEngine.Corpus {
        CupertinoDataEngine.Corpus.legacy(
            at: corpusDirectory,
            schemaVersions: dataEngineSchemaVersions
        )
    }

    /// Per-source corpus bundle configuration with schema versions supplied
    /// from Cupertino's concrete storage producers at the composition root.
    @_spi(CupertinoInternal)
    public static func makePerSourceDataEngineConfiguration(
        corpusDirectory: URL
    ) -> CupertinoDataEngine.Configuration {
        CupertinoDataEngine.Configuration.perSourceBundle(
            baseDirectory: corpusDirectory,
            searchSchemaVersion: dataEngineSchemaVersions.search,
            sampleSchemaVersion: dataEngineSchemaVersions.sample,
            packagesSchemaVersion: dataEngineSchemaVersions.packages
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
            searchSchemaVersion: dataEngineSchemaVersions.search,
            sampleSchemaVersion: dataEngineSchemaVersions.sample,
            packagesSchemaVersion: dataEngineSchemaVersions.packages
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

    /// Build the read-only embedded data engine from an opaque corpus handle.
    /// This is the app-facing path: callers supply a bundle/directory handle,
    /// not individual storage resources.
    @_spi(CupertinoInternal)
    public static func makeReadOnlyDataEngine(
        corpus: CupertinoDataEngine.Corpus,
        logger _: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await CupertinoDataEngine(corpus: corpus)
    }

    /// Convenience for the current per-source bundle layout.
    public static func makePerSourceReadOnlyDataEngine(
        corpusDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await makeReadOnlyDataEngine(
            corpus: makePerSourceDataEngineCorpus(corpusDirectory: corpusDirectory),
            logger: logger
        )
    }

    /// Convenience for the legacy corpus layout used by some local bundles.
    public static func makeLegacyReadOnlyDataEngine(
        corpusDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> CupertinoDataEngine {
        try await makeReadOnlyDataEngine(
            corpus: makeLegacyDataEngineCorpus(corpusDirectory: corpusDirectory),
            logger: logger
        )
    }

    /// The documentation-tree children listing (issue #50), backed by the embedded data engine
    /// over the current per-source corpus. Returned as the `Search.DocumentChildrenListing`
    /// protocol so callers (the MCP `list_children` tool) consume one shared parser without
    /// naming the engine. The engine parses a document's `## Topics` section into topic groups
    /// and their member documents; the server and the embedded apps now share this single
    /// implementation instead of maintaining two copies.
    public static func makePerSourceDocumentChildrenListing(
        corpusDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> any Search.DocumentChildrenListing {
        try await makePerSourceReadOnlyDataEngine(corpusDirectory: corpusDirectory, logger: logger)
    }
}
