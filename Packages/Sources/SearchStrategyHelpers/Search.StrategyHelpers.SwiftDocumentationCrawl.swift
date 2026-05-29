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
    // pre-#1084 baseline was 168 lines: file-walking + per-page
    // decoding + poison defence + URI derivation + indexer call;
    // each stage is short on its own and splitting across helpers
    // would obscure the linear page-processing flow. #1095 added
    // the optional `platformVersions` param as a per-strategy
    // override hook; #1103 added the swift-version path that piggy-
    // backs the same resolver.
    // swiftlint:disable:next function_body_length function_parameter_count
    public static func crawlSwiftDocumentation(
        swiftOrgDirectory: URL,
        markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
        logger: any LoggingModels.Logging.Recording,
        scope: SwiftDocumentationScope,
        summarySource: String,
        into index: any Search.Database & Search.IndexWriter,
        progress _: (any Search.IndexingProgressReporting)?,
        platformVersions: (any Search.PlatformVersionsResolver)? = nil
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

        // #1093: pre-split, swift-org's fetch dropped swift-book pages
        // into `swift-org/swift-book/` as a subdir, and the strategy
        // used `extractFrameworkFromPath` (first path component =
        // source-id) to scope-filter. Post-split each source's
        // corpus dir contains only its own content (flat layout), so
        // path-based scope is unreliable. Default to the strategy's
        // own source-id (`summarySource`) when the path doesn't give
        // a useful source-id, and skip scope-filtering for the
        // strategy-owned case.
        for (idx, file) in docFiles.enumerated() {
            // Legacy INPUT filter only — never a stored value. The pre-#1038
            // mixed corpus tagged each page's sub-source via the first path
            // component; a flat per-source corpus carries no such tag, so this
            // skip never fires there. It only selects which input files to
            // index. The stored source is determined from content below
            // (Principle 7: no stored value derived from filesystem layout).
            let legacyPathTag = Search.StrategyHelpers.extractFrameworkFromPath(
                file, relativeTo: swiftOrgDirectory
            )
            switch scope {
            case .both:
                break
            case .swiftOrgOnly:
                if legacyPathTag == Shared.Constants.SourcePrefix.swiftBook {
                    skipped += 1
                    continue
                }
            case .swiftBookOnly:
                if legacyPathTag == Shared.Constants.SourcePrefix.swiftOrg {
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

            // Stored sub-source comes from the strategy's own identity, never
            // the corpus folder. The legacy `.both` mixed mode disambiguates
            // from the document URL (swift-book pages live under
            // `/the-swift-programming-language/`), not the path.
            let pageSource: String
            switch scope {
            case .swiftOrgOnly:
                pageSource = Shared.Constants.SourcePrefix.swiftOrg
            case .swiftBookOnly:
                pageSource = Shared.Constants.SourcePrefix.swiftBook
            case .both:
                pageSource = structuredPage.url.path.contains("the-swift-programming-language")
                    ? Shared.Constants.SourcePrefix.swiftBook
                    : Shared.Constants.SourcePrefix.swiftOrg
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

            // #1084: derive the URI slug from the page's `url`
            // field (Apple's canonical URL), not from the on-disk
            // filename. Pre-fix the URI was
            // `swift-book://swift-book_documentation_the-swift-programming-language_closures`
            // — the URL-encoded filename leaked into the URI. Tests
            // (`CupertinoSearchTests`, `DocKindIntegrationTests`)
            // already pinned the clean shape `swift-book://closures`.
            // Apple's URL pattern is
            // `.../the-swift-programming-language/<slug>/` (or
            // `/documentation/<slug>/`), so the last non-empty path
            // component IS the canonical Apple slug. Fallback to the
            // on-disk filename only when the slug is empty
            // (defensive — production pages always have a slug).
            let uri: String = {
                var slug = structuredPage.url.lastPathComponent
                if slug.isEmpty {
                    // Trailing-slash URL: drop the empty tail and
                    // take the actual last component.
                    slug = structuredPage.url.deletingLastPathComponent().lastPathComponent
                }
                if slug.hasSuffix(".html") {
                    slug = String(slug.dropLast(".html".count))
                }
                if slug.isEmpty {
                    return "\(pageSource)://\(file.deletingPathExtension().lastPathComponent)"
                }
                return "\(pageSource)://\(slug.lowercased())"
            }()

            do {
                // #1088: both swift-org AND swift-book carry Swift-
                // language-level content that applies to every
                // platform Swift runs on.
                // #1095: per-page override seam — strategies that
                // need page-specific floors (e.g. swift-book's
                // chapter-version table for concurrency/macros)
                // supply a `PlatformVersionsResolver`. Default is
                // the universal Swift baseline (iOS 8.0 / macOS
                // 10.9 / tvOS 9.0 / watchOS 2.0 / visionOS 1.0).
                let versions = platformVersions?.versions(for: structuredPage.url) ?? .universalSwift
                // #1103: per-page Swift toolchain version when the
                // resolver opts in (today swift-book's per-chapter
                // table; default returns nil so other strategies
                // keep the column NULL).
                let swiftVersion = platformVersions?.implementationSwiftVersion(for: structuredPage.url)
                // #1116: source-specific availability_source tag.
                // Pre-fix this was hardcoded `"swift-book-chapter"`
                // whenever a resolver was supplied, mislabelling
                // swift-org rows that share the same code path.
                // Resolver now supplies its own tag (swift-book
                // returns "swift-book-chapter"; swift-org returns
                // "swift-org-universal" or "swift-org-linux-server"
                // per page). Falls back to "universal-swift" only
                // when no resolver is in play.
                let resolverTag = platformVersions?.availabilitySource(for: structuredPage.url)
                let availabilitySource = resolverTag
                    ?? (platformVersions == nil ? "universal-swift" : "per-page-resolver")
                try await index.indexStructuredDocument(
                    uri: uri,
                    source: pageSource,
                    framework: pageSource,
                    page: structuredPage,
                    jsonData: jsonString,
                    overrideMinIOS: versions.iOS,
                    overrideMinMacOS: versions.macOS,
                    overrideMinTvOS: versions.tvOS,
                    overrideMinWatchOS: versions.watchOS,
                    overrideMinVisionOS: versions.visionOS,
                    overrideAvailabilitySource: availabilitySource,
                    implementationSwiftVersion: swiftVersion
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
