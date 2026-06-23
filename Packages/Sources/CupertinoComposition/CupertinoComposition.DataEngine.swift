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

    /// The documentation browser (list documents + list topic-group children, issue #50 /
    /// query-side source pluggability), backed by the embedded data engine over the current
    /// per-source corpus. Returned as the `Search.DocumentBrowsing` protocol so callers (the MCP
    /// `list_documents` / `list_children` tools and the matching CLI commands) consume one shared
    /// implementation without naming the engine. The engine has a reader per source, so browsing
    /// works for ALL sources (apple-docs, hig, apple-archive, swift-evolution, swift-org,
    /// swift-book), not just apple-docs.
    public static func makePerSourceDocumentBrowsing(
        corpusDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> any Search.DocumentBrowsing {
        try await makePerSourceReadOnlyDataEngine(corpusDirectory: corpusDirectory, logger: logger)
    }

    /// Browsing surface for the unified `list` tool (#1311): the same engine, exposed both as the
    /// shared `Search.DocumentBrowsing` (levels 2/3) AND as a per-source framework lister (level 1).
    /// Built from ONE engine so the per-source DBs open once. The frameworks closure routes to the
    /// per-source reader (`documentBrowser(id:).listFrameworks()`), so each source lists its OWN
    /// frameworks rather than the global merged set the source-blind `list_frameworks` returned.
    public struct PerSourceBrowsing: Sendable {
        public let browsing: any Search.DocumentBrowsing
        public let frameworks: @Sendable (String) async throws -> [String: Int]
    }

    public static func makePerSourceBrowsing(
        corpusDirectory: URL,
        logger: any Logging.Recording
    ) async throws -> PerSourceBrowsing {
        let engine = try await makePerSourceReadOnlyDataEngine(corpusDirectory: corpusDirectory, logger: logger)
        return PerSourceBrowsing(
            browsing: engine,
            frameworks: { source in try await engine.documentBrowser(id: source).listFrameworks() }
        )
    }
}
