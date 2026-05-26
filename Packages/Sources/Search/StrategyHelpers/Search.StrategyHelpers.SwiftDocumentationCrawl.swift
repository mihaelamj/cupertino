import Foundation
import LoggingModels
import SearchModels
import SharedConstants

// MARK: - Swift documentation crawl helper

extension Search.StrategyHelpers {
    /// Sub-source scope filter for the shared Swift documentation crawl.
    /// Post the "diff db for each source" follow-up to #1037 + #1038,
    /// swift-org and swift-book each own their own DB and their own
    /// `SourceIndexingStrategy` concrete; both delegate to
    /// `crawlSwiftDocumentation(...)` with their respective scope so the
    /// per-page tag filter routes emission to the right destination.
    ///
    /// - `.both`: pre-#1038 view-source behaviour. Every page (whatever
    ///   its URL-prefix tag) is indexed; used by the legacy descriptor
    ///   `Shared.Models.DatabaseDescriptor.swiftDocumentation` for the
    ///   pre-#1038 co-located shape.
    /// - `.swiftOrgOnly`: emit only pages whose URL-prefix tag is
    ///   `swift-org`. Others count toward `skipped`. Used by
    ///   `SwiftOrgSource.makeStrategy(env:)`.
    /// - `.swiftBookOnly`: emit only pages whose URL-prefix tag is
    ///   `swift-book`. Used by `SwiftBookSource.makeStrategy(env:)`.
    public enum SwiftDocumentationScope: Sendable {
        case both
        case swiftOrgOnly
        case swiftBookOnly
    }

    /// Shared crawl-and-emit helper for the Swift documentation corpus.
    /// Walks the supplied `swiftOrgDirectory`, decodes each `.json` / `.md`
    /// page, applies the scope filter, and indexes the surviving pages
    /// into the supplied `index`. Returns the per-source `IndexStats` for
    /// the calling strategy.
    ///
    /// The helper lives in `SearchStrategyHelpers` (a neutral target
    /// both `SwiftOrgSource` and `SwiftBookSource` already depend on) so
    /// each per-source strategy concrete can call into it WITHOUT
    /// importing the sibling source target. Per
    /// `mihaela-agents/Rules/swift/per-package-import-contract.md` and
    /// `feedback_sources_100pct_pluggable`, source targets must be
    /// standalone-portable (Foundation + own *Models + neutral helpers
    /// only); cross-source imports are forbidden.
    ///
    /// Logging: the helper takes a `Logging.Recording` and emits
    /// progress + per-page-error lines under `category: .search`. The
    /// per-source strategy wrapper passes the `source` used in the
    /// final stats summary line.
    ///
    /// - Parameters:
    ///   - swiftOrgDirectory: Root directory of the crawled corpus.
    ///   - markdownStrategy: Adapter converting raw markdown to
    ///     `Shared.Models.StructuredDocumentationPage`.
    ///   - logger: GoF Strategy seam for log emission.
    ///   - scope: Per-page filter; see `SwiftDocumentationScope`.
    ///   - summarySource: The source-id reported by the returned
    ///     `IndexStats.source` (the caller's strategy `source` field).
    ///   - index: `Search.Database & Search.IndexWriter` actor (e.g.
    ///     `Search.Index`) that receives the indexed pages.
    ///   - progress: Optional progress callback.
    public static func crawlSwiftDocumentation(
        swiftOrgDirectory: URL,
        markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
        logger: any LoggingModels.Logging.Recording,
        scope: SwiftDocumentationScope,
        summarySource: String,
        into index: any Search.Database & Search.IndexWriter,
        progress _: (any Search.IndexingProgressReporting)?
    ) async throws -> Search.IndexStats {
        guard FileManager.default.fileExists(atPath: swiftOrgDirectory.path) else {
            return Search.IndexStats(
                source: summarySource,
                indexed: 0,
                skipped: 0,
                wasSkipped: true,
                skipReason: "no local corpus"
            )
        }

        let docFiles = try Search.StrategyHelpers.findDocFiles(in: swiftOrgDirectory)
        guard !docFiles.isEmpty else {
            return Search.IndexStats(
                source: summarySource,
                indexed: 0,
                skipped: 0,
                wasSkipped: true,
                skipReason: "no documents found"
            )
        }

        let scopeLabel: String
        switch scope {
        case .both: scopeLabel = "Swift.org + Swift Book"
        case .swiftOrgOnly: scopeLabel = "Swift.org"
        case .swiftBookOnly: scopeLabel = "Swift Book"
        }
        logger.info(
            "🔶 Indexing \(docFiles.count) \(scopeLabel) documentation pages...",
            category: .search
        )

        var indexed = 0
        var skipped = 0

        for (idx, file) in docFiles.enumerated() {
            let pageSource = Search.StrategyHelpers.extractFrameworkFromPath(
                file, relativeTo: swiftOrgDirectory
            ) ?? Shared.Constants.SourcePrefix.swiftOrg

            // Per-page scope filter. Pages whose URL-prefix tag belongs
            // to the other sub-source are silently skipped (no error
            // log) since the sibling strategy will pick them up.
            switch scope {
            case .both:
                break
            case .swiftOrgOnly:
                if pageSource != Shared.Constants.SourcePrefix.swiftOrg {
                    skipped += 1
                    continue
                }
            case .swiftBookOnly:
                if pageSource != Shared.Constants.SourcePrefix.swiftBook {
                    skipped += 1
                    continue
                }
            }

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
                    string: "https://www.swift.org/documentation/" +
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
                      let json = String(data: jsonData, encoding: .utf8)
                else {
                    logger.error(
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
            // #429 indexer-side poison defence (HTTP error template
            // titles + JS-disabled fallback content).
            if Search.StrategyHelpers.titleLooksLikeHTTPErrorTemplate(title) {
                logger.error(
                    "⛔ Skipping HTTP-error-template page (#429 defence): " +
                        "title=\(title.prefix(60)) file=\(file.lastPathComponent)",
                    category: .search
                )
                skipped += 1
                continue
            }
            if Search.StrategyHelpers.pageLooksLikeJavaScriptFallback(structuredPage) {
                logger.error(
                    "⛔ Skipping JS-fallback page (#429 defence): " +
                        "title=\(title.prefix(60)) file=\(file.lastPathComponent)",
                    category: .search
                )
                skipped += 1
                continue
            }

            let filename = file.deletingPathExtension().lastPathComponent
            let uri = "\(pageSource)://\(filename)"

            do {
                // The Swift Book covers all platforms that ship Swift support.
                let isSwiftBook = pageSource == Shared.Constants.SourcePrefix.swiftBook
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

            if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                logger.info(
                    "   Progress: \(idx + 1)/\(docFiles.count)", category: .search
                )
            }
        }

        logger.info(
            "   \(scopeLabel): \(indexed) indexed, \(skipped) skipped",
            category: .search
        )
        return Search.IndexStats(source: summarySource, indexed: indexed, skipped: skipped)
    }
}
