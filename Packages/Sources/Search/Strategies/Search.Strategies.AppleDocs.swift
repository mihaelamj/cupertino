import CoreProtocols
import Foundation
import LoggingModels
import SearchModels
import SharedConstants
// MARK: - AppleDocsStrategy

extension Search {
    /// Indexes Apple Developer Documentation into the search index.
    ///
    /// The strategy supports two indexing paths, selected automatically:
    ///
    /// - **Directory scan** (default): recursively finds `.json` and `.md` files under
    ///   ``docsDirectory``, decodes each as a ``Shared/Models/StructuredDocumentationPage``,
    ///   deduplicates by canonical URL, and writes structured documents to the index.
    ///
    /// - **Metadata-driven** (when ``metadata`` is non-nil): iterates the URL→page map in
    ///   the crawl metadata, reads content from disk, and indexes plain documents.  This path
    ///   is used during incremental index builds.
    ///
    /// Both paths apply the #284 indexer-side defences that skip HTTP error template pages
    /// and JavaScript-disabled fallback pages.
    ///
    /// URI scheme: `apple-docs://{framework}/{filename}`
    ///
    /// ## Example
    /// ```swift
    /// // Directory scan (most common)
    /// let strategy = Search.AppleDocsStrategy(docsDirectory: docsDir)
    ///
    /// // Metadata-driven (incremental build)
    /// let strategy = Search.AppleDocsStrategy(docsDirectory: docsDir, metadata: crawlMetadata)
    ///
    /// let stats = try await strategy.indexItems(into: index, progress: nil)
    /// ```
    public struct AppleDocsStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index.
        public let source = Shared.Constants.SourcePrefix.appleDocs

        /// Root directory containing the crawled Apple documentation files.
        public let docsDirectory: URL

        /// Strategy for converting raw markdown to a structured page.
        /// Injected so this target doesn't depend on `CoreJSONParser`;
        /// the composition root supplies a concrete conformer wrapping
        /// `Core.JSONParser.MarkdownToStructuredPage.convert`.
        private let markdownStrategy: any Search.MarkdownToStructuredPageStrategy

        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        public init(
            docsDirectory: URL,
            markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.docsDirectory = docsDirectory
            self.markdownStrategy = markdownStrategy
            self.logger = logger
        }

        /// Index all Apple documentation pages by scanning ``docsDirectory``.
        ///
        /// Crawl metadata is intentionally not used here: metadata is for fetching,
        /// not indexing.  To index from metadata directly (e.g., in tests), call
        /// ``indexFromMetadata(into:metadata:progress:)`` instead.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional progress callback, called every 100 items.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        public func indexItems(
            into index: Search.Index,
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats {
            // Always use the directory-scan path; metadata is for crawling, not indexing.
            try await indexFromDirectory(into: index, progress: progress)
        }

        // MARK: - Directory-Scan Path

        /// Index Apple documentation by scanning ``docsDirectory`` for files.
        ///
        /// This path decodes each file as a ``Shared/Models/StructuredDocumentationPage``,
        /// deduplicates by canonical URL, applies #284 defences, and writes structured
        /// documents including code examples and AST symbols.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional progress callback, called every 100 items.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        func indexFromDirectory(
            into index: Search.Index,
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats {
            guard FileManager.default.fileExists(atPath: docsDirectory.path) else {
                logger.info(
                    "⚠️  Docs directory not found: \(docsDirectory.path)", category: .search
                )
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            logger.info(
                "📂 Scanning directory for documentation (no metadata.json)...",
                category: .search
            )

            let rawFiles = try Search.StrategyHelpers.findDocFiles(in: docsDirectory)
            let docFiles = Search.StrategyHelpers.deduplicateDocFilesByCanonicalURL(
                rawFiles, docsDirectory: docsDirectory
            )

            guard !docFiles.isEmpty else {
                logger.info(
                    "⚠️  No documentation files found in \(docsDirectory.path)",
                    category: .search
                )
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            logger.info(
                "📚 Indexing \(docFiles.count) documentation pages from directory...",
                category: .search
            )

            var indexed = 0
            var skipped = 0

            for (idx, file) in docFiles.enumerated() {
                guard let rawFramework = Search.StrategyHelpers.extractFrameworkFromPath(
                    file, relativeTo: docsDirectory
                ) else {
                    logger.error(
                        "❌ Could not extract framework from path: \(file.path) " +
                            "(relative to \(docsDirectory.path))",
                        category: .search
                    )
                    skipped += 1
                    continue
                }
                let framework = Search.StrategyHelpers.canonicalPathComponent(rawFramework)

                let structuredPage: Shared.Models.StructuredDocumentationPage
                let jsonString: String

                if file.pathExtension == "json" {
                    do {
                        let jsonData = try Data(contentsOf: file)
                        jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        structuredPage = try decoder.decode(
                            Shared.Models.StructuredDocumentationPage.self, from: jsonData
                        )
                    } catch {
                        logger.error(
                            "❌ Failed to decode \(file.lastPathComponent): \(error)",
                            category: .search
                        )
                        skipped += 1
                        continue
                    }
                } else {
                    guard let mdContent = try? String(contentsOf: file, encoding: .utf8) else {
                        skipped += 1
                        continue
                    }
                    let pageURL = URL(
                        string: "\(Shared.Constants.BaseURL.appleDeveloperDocs)\(framework)/" +
                            "\(file.deletingPathExtension().lastPathComponent)"
                    )
                    guard let converted = markdownStrategy.convert(markdown: mdContent, url: pageURL) else {
                        logger.error(
                            "❌ Failed to convert \(file.lastPathComponent) to structured page",
                            category: .search
                        )
                        skipped += 1
                        continue
                    }
                    structuredPage = converted
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    guard let jsonData = try? encoder.encode(structuredPage),
                          let json = String(data: jsonData, encoding: .utf8) else {
                        logger.error(
                            "❌ Failed to encode \(file.lastPathComponent) to JSON",
                            category: .search
                        )
                        skipped += 1
                        continue
                    }
                    jsonString = json
                }

                // #284 indexer-side defences.
                if Search.StrategyHelpers.titleLooksLikeHTTPErrorTemplate(structuredPage.title) {
                    logger.error(
                        "⛔ Skipping HTTP-error-template page (#284 indexer defence): " +
                            "title=\(structuredPage.title.prefix(60)) " +
                            "file=\(file.lastPathComponent)",
                        category: .search
                    )
                    skipped += 1
                    continue
                }
                if Search.StrategyHelpers.pageLooksLikeJavaScriptFallback(structuredPage) {
                    logger.error(
                        "⛔ Skipping JS-disabled-fallback page (#284 indexer defence): " +
                            "title=\(structuredPage.title.prefix(60)) " +
                            "file=\(file.lastPathComponent)",
                        category: .search
                    )
                    skipped += 1
                    continue
                }

                let filename = Shared.Models.URLUtilities.normalize(structuredPage.url)?
                    .lastPathComponent
                    ?? Search.StrategyHelpers.canonicalPathComponent(
                        file.deletingPathExtension().lastPathComponent
                    )
                let uri = "apple-docs://\(framework)/\(filename)"

                do {
                    try await index.indexStructuredDocument(
                        uri: uri,
                        source: source,
                        framework: framework,
                        page: structuredPage,
                        jsonData: jsonString
                    )

                    // Index code examples and extract AST symbols (#192).
                    if !structuredPage.codeExamples.isEmpty {
                        let examples = structuredPage.codeExamples.map {
                            (code: $0.code, language: $0.language ?? "swift")
                        }
                        try await index.indexCodeExamples(docUri: uri, codeExamples: examples)
                        try await index.extractCodeExampleSymbols(
                            docUri: uri, codeExamples: examples
                        )
                    }
                    indexed += 1
                } catch {
                    logger.error(
                        "❌ Failed to index \(uri): \(error)", category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % 100 == 0 {
                    progress?(idx + 1, docFiles.count)
                    logger.info(
                        "   Progress: \(idx + 1)/\(docFiles.count) " +
                            "(\(indexed) indexed, \(skipped) skipped)",
                        category: .search
                    )
                }
            }

            logger.info(
                "   Directory scan: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }

        // MARK: - Metadata-Driven Path

        /// Index Apple documentation using crawl metadata.
        ///
        /// This path is used during incremental index builds.  It iterates the URL→page map
        /// in `metadata`, reads each page's content from the file path recorded in the
        /// metadata, and indexes plain (non-structured) documents.
        ///
        /// Rows whose URL key cannot be parsed by `URL(string:)` are skipped rather than
        /// crashing the build (fix for PR #288).
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - metadata: The crawl metadata map to iterate.
        ///   - progress: Optional progress callback, called every 100 items.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        func indexFromMetadata(
            into index: Search.Index,
            metadata: Shared.Models.CrawlMetadata,
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats {
            let total = metadata.pages.count
            guard total > 0 else {
                logger.info(
                    "⚠️  No Apple documentation found in metadata", category: .search
                )
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            logger.info(
                "📚 Indexing \(total) Apple documentation pages from metadata...",
                category: .search
            )

            var processed = 0
            var indexed = 0
            var skipped = 0

            for (url, pageMetadata) in metadata.pages {
                let filePath = URL(fileURLWithPath: pageMetadata.filePath)

                guard FileManager.default.fileExists(atPath: filePath.path) else {
                    skipped += 1; processed += 1; continue
                }
                guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
                    skipped += 1; processed += 1; continue
                }
                // `url` comes from indexed page metadata; skip rather than crash if it
                // doesn't parse (PR #288 malformed-URL fix).
                guard let parsedURL = URL(string: url) else {
                    skipped += 1; processed += 1; continue
                }

                let title = Search.StrategyHelpers.extractTitle(from: content)
                    ?? Shared.Models.URLUtilities.filename(from: parsedURL)
                let uri = "apple-docs://\(pageMetadata.framework)/" +
                    "\(Shared.Models.URLUtilities.filename(from: parsedURL))"

                do {
                    try await index.indexDocument(Search.Index.IndexDocumentParams(
                        uri: uri,
                        source: source,
                        framework: pageMetadata.framework,
                        title: title,
                        content: content,
                        filePath: pageMetadata.filePath,
                        contentHash: pageMetadata.contentHash,
                        lastCrawled: pageMetadata.lastCrawled
                    ))
                    indexed += 1
                } catch {
                    logger.error(
                        "❌ Failed to index \(uri): \(error)", category: .search
                    )
                    skipped += 1
                }

                processed += 1
                if processed % 100 == 0 {
                    progress?(processed, total)
                    logger.info(
                        "   Progress: \(processed)/\(total) " +
                            "(\(indexed) indexed, \(skipped) skipped)",
                        category: .search
                    )
                }
            }

            logger.info(
                "   Apple Docs: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }
    }
}
