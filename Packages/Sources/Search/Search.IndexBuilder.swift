import Foundation
import Logging
import SearchModels
import SharedConstants
import SharedModels

// MARK: - Search Index Builder

extension Search {
    /// Orchestrates a full search index build by iterating an array of ``SourceIndexingStrategy``
    /// implementations, one per documentation source.
    ///
    /// `IndexBuilder` is responsible only for coordination:
    /// - Optionally clearing the existing index before the run.
    /// - Iterating the active strategy array in order.
    /// - Registering framework synonyms after all sources have been indexed.
    /// - Logging the final document count.
    ///
    /// Per-source logic (directory scanning, file parsing, URI construction, availability
    /// look-up) lives entirely in the concrete strategy types (``AppleDocsStrategy``,
    /// ``SwiftEvolutionStrategy``, ``SwiftOrgStrategy``, ``AppleArchiveStrategy``,
    /// ``HIGStrategy``, ``SampleCodeStrategy``, ``SwiftPackagesStrategy``).
    ///
    /// ## Building with the convenience initialiser
    ///
    /// ```swift
    /// let builder = Search.IndexBuilder(
    ///     searchIndex: index,
    ///     metadata: crawlMetadata,
    ///     docsDirectory: docsDir,
    ///     evolutionDirectory: evolutionDir,
    ///     swiftOrgDirectory: swiftOrgDir
    /// )
    /// try await builder.buildIndex()
    /// ```
    ///
    /// ## Building with a custom strategy array
    ///
    /// ```swift
    /// let builder = Search.IndexBuilder(
    ///     searchIndex: index,
    ///     strategies: [
    ///         Search.AppleDocsStrategy(docsDirectory: docsDir),
    ///         Search.SwiftEvolutionStrategy(evolutionDirectory: evolutionDir),
    ///     ]
    /// )
    /// try await builder.buildIndex()
    /// ```
    public actor IndexBuilder {
        private let searchIndex: Search.Index
        private let strategies: [any Search.SourceIndexingStrategy]

        // MARK: - Designated Initialiser

        /// Create an ``IndexBuilder`` with an explicit strategy array.
        ///
        /// Use this initialiser when you need full control over which sources are indexed
        /// and in what order.  For the standard seven-source build use the convenience
        /// initialiser instead.
        ///
        /// - Parameters:
        ///   - searchIndex: The ``Search/Index`` to write into.
        ///   - strategies: The ordered list of strategies to execute.
        public init(searchIndex: Search.Index, strategies: [any Search.SourceIndexingStrategy]) {
            self.searchIndex = searchIndex
            self.strategies = strategies
        }

        // MARK: - Convenience Initialiser

        /// Create an ``IndexBuilder`` configured for the standard seven documentation sources.
        ///
        /// Strategies are only added for optional sources (Evolution, Swift.org, Archive,
        /// HIG) when their corresponding directory is non-nil.  Sample code indexing is
        /// conditional on `indexSampleCode`.
        ///
        /// This initialiser is source-compatible with the pre-refactor actor; existing call
        /// sites require no changes.
        ///
        /// - Parameters:
        ///   - searchIndex: The ``Search/Index`` to write into.
        ///   - metadata: Optional crawl metadata (passed to ``AppleDocsStrategy``).
        ///   - docsDirectory: Root directory of the Apple documentation corpus.
        ///   - evolutionDirectory: Optional directory containing Swift Evolution proposals.
        ///   - swiftOrgDirectory: Optional directory containing Swift.org documentation.
        ///   - archiveDirectory: Optional directory containing Apple Archive documentation.
        ///   - higDirectory: Optional directory containing Human Interface Guidelines files.
        ///   - indexSampleCode: Whether to include the sample code catalog. Defaults to `true`.
        public init(
            searchIndex: Search.Index,
            metadata: Shared.Models.CrawlMetadata?,
            docsDirectory: URL,
            evolutionDirectory: URL? = nil,
            swiftOrgDirectory: URL? = nil,
            archiveDirectory: URL? = nil,
            higDirectory: URL? = nil,
            indexSampleCode: Bool = true,
            markdownToStructuredPage: @escaping Search.MarkdownToStructuredPage,
            sampleCatalogFetch: @escaping Search.SampleCatalogFetch
        ) {
            self.init(
                searchIndex: searchIndex,
                strategies: Self.makeDefaultStrategies(
                    metadata: metadata,
                    docsDirectory: docsDirectory,
                    evolutionDirectory: evolutionDirectory,
                    swiftOrgDirectory: swiftOrgDirectory,
                    archiveDirectory: archiveDirectory,
                    higDirectory: higDirectory,
                    indexSampleCode: indexSampleCode,
                    markdownToStructuredPage: markdownToStructuredPage,
                    sampleCatalogFetch: sampleCatalogFetch
                )
            )
        }

        // MARK: - Build

        /// Build the search index by running all active strategies in sequence.
        ///
        /// Each strategy is given the shared ``Search/Index`` instance.  Per-item errors
        /// are caught inside each strategy; only unrecoverable failures propagate here.
        ///
        /// After all strategies complete, framework synonyms are registered so that common
        /// alternate names (e.g., `"bluetooth"` → `"corebluetooth"`) resolve correctly.
        ///
        /// - Parameters:
        ///   - clearExisting: When `true` (the default), the index is cleared before any
        ///     strategies run.
        ///   - onProgress: Optional progress callback forwarded to each strategy.
        public func buildIndex(
            clearExisting: Bool = true,
            onProgress: Search.IndexingProgressCallback? = nil
        ) async throws {
            Logging.Log.info("🔨 Building search index...", category: .search)

            if clearExisting {
                try await searchIndex.clearIndex()
                Logging.Log.info("   Cleared existing index", category: .search)
            }

            var allStats: [Search.IndexStats] = []
            for strategy in strategies {
                let stats = try await strategy.indexItems(into: searchIndex, progress: onProgress)
                allStats.append(stats)
            }

            try await registerFrameworkSynonyms()

            // Log per-source breakdown so operators can diagnose index-build issues
            // without having to re-run with verbose logging.
            for stats in allStats {
                Logging.Log.info(
                    "   [\(stats.source)] indexed: \(stats.indexed), skipped: \(stats.skipped)",
                    category: .search
                )
            }
            let count = try await searchIndex.documentCount()
            Logging.Log.info("✅ Search index built: \(count) documents", category: .search)
        }

        // MARK: - Factory

        /// Build the default strategy array for the standard seven documentation sources.
        ///
        /// Optional sources are only included when their directory parameter is non-nil.
        ///
        /// - Parameters:
        ///   - metadata: Optional crawl metadata for ``AppleDocsStrategy``.
        ///   - docsDirectory: Root directory of the Apple documentation corpus.
        ///   - evolutionDirectory: Optional Swift Evolution proposals directory.
        ///   - swiftOrgDirectory: Optional Swift.org documentation directory.
        ///   - archiveDirectory: Optional Apple Archive documentation directory.
        ///   - higDirectory: Optional Human Interface Guidelines directory.
        ///   - indexSampleCode: Whether to include the ``SampleCodeStrategy``.
        /// - Returns: An ordered array of active ``SourceIndexingStrategy`` values.
        public static func makeDefaultStrategies(
            metadata: Shared.Models.CrawlMetadata?,
            docsDirectory: URL,
            evolutionDirectory: URL? = nil,
            swiftOrgDirectory: URL? = nil,
            archiveDirectory: URL? = nil,
            higDirectory: URL? = nil,
            indexSampleCode: Bool = true,
            markdownToStructuredPage: @escaping Search.MarkdownToStructuredPage,
            sampleCatalogFetch: @escaping Search.SampleCatalogFetch
        ) -> [any Search.SourceIndexingStrategy] {
            var strategies: [any Search.SourceIndexingStrategy] = [
                Search.AppleDocsStrategy(
                    docsDirectory: docsDirectory,
                    markdownToStructuredPage: markdownToStructuredPage
                ),
            ]
            if let dir = evolutionDirectory {
                strategies.append(Search.SwiftEvolutionStrategy(evolutionDirectory: dir))
            }
            if let dir = swiftOrgDirectory {
                strategies.append(Search.SwiftOrgStrategy(
                    swiftOrgDirectory: dir,
                    markdownToStructuredPage: markdownToStructuredPage
                ))
            }
            if let dir = archiveDirectory {
                strategies.append(Search.AppleArchiveStrategy(archiveDirectory: dir))
            }
            if let dir = higDirectory {
                strategies.append(Search.HIGStrategy(higDirectory: dir))
            }
            if indexSampleCode {
                strategies.append(Search.SampleCodeStrategy(sampleCatalogFetch: sampleCatalogFetch))
            }
            strategies.append(Search.SwiftPackagesStrategy())
            return strategies
        }

        // MARK: - Framework Synonyms

        /// Register well-known framework synonyms so that common alternate names resolve
        /// to the correct framework in search results.
        ///
        /// For example, searching `"bluetooth"` will return `CoreBluetooth` results.
        private func registerFrameworkSynonyms() async throws {
            let synonyms: [(identifier: String, synonyms: String)] = [
                ("corenfc", "nfc"),
                ("journalingsuggestions", "journaling"),
                ("corebluetooth", "bluetooth"),
                ("corelocation", "location"),
                ("coredata", "data"),
                ("coremotion", "motion"),
                ("coregraphics", "graphics"),
                ("coreimage", "imageprocessing"),
                ("coremedia", "media"),
                ("coreaudio", "audio"),
                ("coreml", "ml,machinelearning"),
                ("corespotlight", "spotlight"),
                ("coretext", "text"),
                ("corevideo", "video"),
                ("corehaptics", "haptics"),
                ("corewlan", "wifi,wlan"),
                ("coretelephony", "telephony"),
                ("metalperformanceshadersgraph", "mpsgraph"),
                ("avfoundation", "av"),
                ("scenekit", "scene"),
                ("spritekit", "sprite"),
                ("groupactivities", "shareplay"),
            ]
            for entry in synonyms {
                try await searchIndex.updateFrameworkSynonyms(
                    identifier: entry.identifier,
                    synonyms: entry.synonyms
                )
            }
        }
    }
}
