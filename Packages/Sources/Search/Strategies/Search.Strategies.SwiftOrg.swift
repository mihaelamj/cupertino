import CoreJSONParser
import CoreProtocols
import Foundation
import Logging
import SharedConstants
import SharedModels
import SearchModels

// MARK: - SwiftOrgStrategy

extension Search {
    /// Indexes Swift.org documentation into the search index.
    ///
    /// Scans ``swiftOrgDirectory`` for both `.json` and `.md` documentation files,
    /// preferring JSON when both formats exist for the same page (matching the Apple
    /// Docs behaviour).  The first path component beneath ``swiftOrgDirectory`` is
    /// used as the source identifier (typically `"swift-book"` or `"swift-org"`).
    ///
    /// Pages from the Swift Book (`source == "swift-book"`) are indexed with universal
    /// platform availability to reflect that the Swift language itself runs everywhere
    /// Swift is supported.
    ///
    /// URI scheme: `{source}://{filename}`
    ///
    /// ## Example
    /// ```swift
    /// let strategy = Search.SwiftOrgStrategy(swiftOrgDirectory: swiftOrgDir)
    /// let stats = try await strategy.indexItems(into: index, progress: nil)
    /// ```
    public struct SwiftOrgStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index.
        ///
        /// Reports `"swift-org"` as the top-level source; individual pages may be
        /// sub-sourced as `"swift-book"` or `"swift-org"` based on the directory
        /// layout.
        public let source = Shared.Constants.SourcePrefix.swiftOrg

        /// Root directory containing the Swift.org documentation files.
        public let swiftOrgDirectory: URL

        /// Create a strategy for indexing Swift.org documentation.
        ///
        /// - Parameter swiftOrgDirectory: Root directory of the Swift.org corpus.
        public init(swiftOrgDirectory: URL) {
            self.swiftOrgDirectory = swiftOrgDirectory
        }

        /// Index all Swift.org documentation pages found under ``swiftOrgDirectory``.
        ///
        /// Handles both `.json` (structured) and `.md` (Markdown) formats using the same
        /// dual-format dispatch as the Apple Docs strategy.  Applies is404Page checks and
        /// logs progress at regular intervals.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional progress callback, called at regular intervals.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        public func indexItems(
            into index: Search.Index,
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats {
            guard FileManager.default.fileExists(atPath: swiftOrgDirectory.path) else {
                Logging.Log.info(
                    "⚠️  Swift.org directory not found: \(swiftOrgDirectory.path)",
                    category: .search
                )
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            let docFiles = try Search.StrategyHelpers.findDocFiles(in: swiftOrgDirectory)
            guard !docFiles.isEmpty else {
                Logging.Log.info("⚠️  No Swift.org documentation found", category: .search)
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            Logging.Log.info(
                "🔶 Indexing \(docFiles.count) Swift.org documentation pages...",
                category: .search
            )

            var indexed = 0
            var skipped = 0

            for (idx, file) in docFiles.enumerated() {
                let pageSource = Search.StrategyHelpers.extractFrameworkFromPath(
                    file, relativeTo: swiftOrgDirectory
                ) ?? Shared.Constants.SourcePrefix.swiftOrg

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
                        Logging.Log.error(
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
                        string: "https://www.swift.org/documentation/" +
                                "\(file.deletingPathExtension().lastPathComponent)"
                    )
                    guard let converted = Core.JSONParser.MarkdownToStructuredPage.convert(
                        mdContent, url: pageURL
                    ) else {
                        Logging.Log.error(
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
                        Logging.Log.error(
                            "❌ Failed to encode \(file.lastPathComponent) to JSON",
                            category: .search
                        )
                        skipped += 1
                        continue
                    }
                    jsonString = json
                }

                let title = structuredPage.title
                let content = structuredPage.rawMarkdown ?? structuredPage.overview ?? ""
                if Search.StrategyHelpers.is404Page(title: title, content: content) {
                    skipped += 1
                    continue
                }

                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "\(pageSource)://\(filename)"

                do {
                    // The Swift Book covers all platforms that ship Swift support.
                    let isSwiftBook = pageSource == "swift-book"
                    try await index.indexStructuredDocument(
                        uri: uri,
                        source: pageSource,
                        framework: pageSource,
                        page: structuredPage,
                        jsonData: jsonString,
                        overrideMinIOS: isSwiftBook ? "8.0" : nil,
                        overrideMinMacOS: isSwiftBook ? "10.9" : nil,
                        overrideMinTvOS: isSwiftBook ? "9.0" : nil,
                        overrideMinWatchOS: isSwiftBook ? "2.0" : nil,
                        overrideMinVisionOS: isSwiftBook ? "1.0" : nil,
                        overrideAvailabilitySource: isSwiftBook ? "universal" : nil
                    )

                    // Index code examples and AST symbols (#192).
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
                    Logging.Log.error(
                        "❌ Failed to index \(uri): \(error)", category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    Logging.Log.info(
                        "   Progress: \(idx + 1)/\(docFiles.count)", category: .search
                    )
                }
            }

            Logging.Log.info(
                "   Swift.org: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }
    }
}
