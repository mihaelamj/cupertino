import ASTIndexer
import Foundation
import SearchModels
import SharedConstants
import SQLite3

extension Search.Index {
    /// Index a document for searching.
    ///
    /// All per-page values flow through `Search.Index.IndexDocumentParams`
    /// so adding a new column (the indexer learns new sources / metadata
    /// over time) doesn't touch every call site — the struct's init
    /// gains a defaulted parameter and existing callers compile unchanged.
    public func indexDocument(_ params: IndexDocumentParams) async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Unpack params once at the top so the function body reads as it
        // did before the bundling. Avoids `params.` prefixing every site
        // in the ~130-line body below.
        let uri = params.uri
        let source = params.source
        let framework = params.framework
        let language = params.language
        let title = params.title
        // #113 — rewrite `doc://` references to public `https://` URLs
        // at the indexer boundary (total rewrite policy). Pre-fix, raw
        // `doc://` URIs that the DocC renderer failed to translate
        // leaked into stored content, where AI clients hit unfollowable
        // references. Substring substitution; idempotent; no DB lookup.
        let contentRewrite = DocLinkRewriter.rewrite(params.content)
        let content = contentRewrite.output
        let filePath = params.filePath
        let contentHash = params.contentHash
        let lastCrawled = params.lastCrawled
        let sourceType = params.sourceType
        let packageId = params.packageId
        // Apply the same rewrite to jsonData — the `read_document` MCP
        // tool + `cupertino read` both serve from `docs_metadata.json_data`,
        // so leaving `doc://` in the JSON blob would defeat the rewrite.
        // JSON-safe: the substituted substring contains no JSON-meta chars.
        let jsonRewrite = params.jsonData.map { DocLinkRewriter.rewrite($0) }
        let jsonData = jsonRewrite?.output
        // #113 audit-count follow-up: emit a debug record when the
        // rewriter substituted anything, so `cupertino save` logs carry
        // a per-page count for the audit trail the issue body asked
        // for. Zero-count case stays silent to avoid drowning logs in
        // no-op events (the vast majority of pages have no doc://).
        let totalRewrites = contentRewrite.count + (jsonRewrite?.count ?? 0)
        if totalRewrites > 0 {
            logger.debug(
                "doc-link-rewrite: \(totalRewrites) substitutions in \(uri) (content=\(contentRewrite.count), json=\(jsonRewrite?.count ?? 0))",
                category: .search
            )
        }
        let minIOS = params.minIOS
        let minMacOS = params.minMacOS
        let minTvOS = params.minTvOS
        let minWatchOS = params.minWatchOS
        let minVisionOS = params.minVisionOS
        let availabilitySource = params.availabilitySource

        // Extract summary (first 500 chars, stop at sentence).
        // Note: `content` is already post-rewrite, so the summary inherits
        // the rewrite automatically; no explicit summary pass needed.
        let summary = extractSummary(from: content)
        let wordCount = content.split(separator: " ").count

        // For non-apple-docs sources, framework can be nil or empty
        let effectiveFramework = framework ?? ""

        // Determine language with heuristics fallback
        let effectiveLanguage = language ?? detectLanguage(from: content)

        // Insert into FTS5 table (db should be deleted before full re-index).
        // `symbols` + `symbol_components` start empty; the AST pass
        // (#192 section D, #77 component split) UPDATEs both after
        // `doc_code_examples` has been populated.
        let ftsSql = """
        INSERT INTO docs_fts (uri, source, framework, language, title, content, summary, symbols, symbol_components)
        VALUES (?, ?, ?, ?, ?, ?, ?, '', '');
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, ftsSql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.prepareFailed("FTS insert: \(errorMessage)")
        }

        sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (effectiveFramework as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (effectiveLanguage as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 6, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (summary as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.insertFailed("FTS insert: \(errorMessage)")
        }

        // Create minimal JSON wrapper if no jsonData provided.
        //
        // #607: callers that pass `jsonData: nil` (the string-content
        // strategies — SwiftEvolution / HIG / AppleArchive) used to land
        // a wrapper with literal `"rawMarkdown":null` here, leaving the
        // body reachable only through `docs_fts.content`. `read_document`
        // (MCP tool) and `cupertino read` (default JSON) both read from
        // `docs_metadata.json_data`, so those 3 sources returned empty
        // wrappers to AI agents. Inline `content` into `rawMarkdown` at
        // this central seam so the fix benefits every nil-jsonData caller
        // (current + future) without each strategy growing its own wrapper.
        //
        // JSON-serialise via Foundation rather than the previous hand-
        // rolled string concat: title escape was the only field handled
        // pre-#607 and adding markdown bodies (newlines, backticks, embedded
        // quotes, backslashes) would have broken the hand-rolled path.
        let finalJsonData: String
        if let jsonData {
            finalJsonData = jsonData
        } else {
            let payload: [String: Any] = [
                "title": title,
                "url": uri,
                "rawMarkdown": content,
                "source": source,
                "framework": effectiveFramework,
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys]
            ),
                let json = String(data: data, encoding: .utf8) {
                finalJsonData = json
            } else {
                // Fall back to a structurally-valid empty wrapper rather
                // than crashing the indexer on a malformed payload.
                // Foundation rejects only NaN / Infinity / non-string keys;
                // none of the params above can produce those.
                finalJsonData = "{\"title\":\"\",\"url\":\"\(uri)\",\"rawMarkdown\":null,\"source\":\"\(source)\",\"framework\":\"\"}"
            }
        }

        // Classify (#192 C1). Direct `indexDocument` callers don't have a
        // structured-kind hint, so the classifier uses `source` + `uri`.
        let classifiedKind = Search.Classify.kind(source: source, uriPath: uri).rawValue

        // Insert metadata with JSON data, availability, and kind (#192 C).
        // `kind` appended at end so existing bind indexes 1-17 stay stable.
        let metaSql = """
        INSERT OR REPLACE INTO docs_metadata \
        (uri, source, framework, language, file_path, content_hash, last_crawled, word_count, \
        source_type, package_id, json_data, min_ios, min_macos, min_tvos, min_watchos, \
        min_visionos, availability_source, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var metaStatement: OpaquePointer?
        defer { sqlite3_finalize(metaStatement) }

        guard sqlite3_prepare_v2(database, metaSql, -1, &metaStatement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.prepareFailed("Metadata insert: \(errorMessage)")
        }

        sqlite3_bind_text(metaStatement, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 2, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 3, (effectiveFramework as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 4, (effectiveLanguage as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 5, (filePath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 6, (contentHash as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(metaStatement, 7, Int64(lastCrawled.timeIntervalSince1970))
        sqlite3_bind_int(metaStatement, 8, Int32(wordCount))
        sqlite3_bind_text(metaStatement, 9, (sourceType as NSString).utf8String, -1, nil)

        if let packageId {
            sqlite3_bind_int(metaStatement, 10, Int32(packageId))
        } else {
            sqlite3_bind_null(metaStatement, 10)
        }

        sqlite3_bind_text(metaStatement, 11, (finalJsonData as NSString).utf8String, -1, nil)

        // Bind availability columns
        bindOptionalText(metaStatement, 12, minIOS)
        bindOptionalText(metaStatement, 13, minMacOS)
        bindOptionalText(metaStatement, 14, minTvOS)
        bindOptionalText(metaStatement, 15, minWatchOS)
        bindOptionalText(metaStatement, 16, minVisionOS)
        bindOptionalText(metaStatement, 17, availabilitySource)
        sqlite3_bind_text(metaStatement, 18, (classifiedKind as NSString).utf8String, -1, nil)

        guard sqlite3_step(metaStatement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.insertFailed("Metadata insert: \(errorMessage)")
        }
    }

    // MARK: - Protocol-Based Indexing

    /// Index a source item using the appropriate SourceIndexer
    /// This provides a unified interface for indexing content from any source.
    /// - Parameters:
    ///   - item: The source item to index
    ///   - extractSymbols: Whether to extract and index AST symbols (default: true)
    /// - Throws: Search.Error if indexing fails
    public func indexItem(_ item: Search.SourceItem, extractSymbols: Bool = true) async throws {
        // Get the indexer for this source
        guard let indexer = Search.IndexerRegistry.indexer(for: item.source) else {
            // Fall back to generic indexing if no specific indexer
            try await indexDocument(IndexDocumentParams(
                uri: item.uri,
                source: item.source,
                framework: item.framework,
                language: item.language,
                title: item.title,
                content: item.content,
                filePath: item.filePath,
                contentHash: item.contentHash,
                lastCrawled: item.lastCrawled,
                sourceType: item.sourceType,
                packageId: item.packageId,
                jsonData: item.jsonData,
                minIOS: item.minIOS,
                minMacOS: item.minMacOS,
                minTvOS: item.minTvOS,
                minWatchOS: item.minWatchOS,
                minVisionOS: item.minVisionOS,
                availabilitySource: item.availabilitySource
            ))
            return
        }

        // Validate the item
        guard indexer.validate(item) else {
            throw Search.Error.invalidQuery("Item failed validation for source: \(item.source)")
        }

        // Preprocess the item
        let processedItem = indexer.preprocess(item)

        // Index the document
        try await indexDocument(IndexDocumentParams(
            uri: processedItem.uri,
            source: processedItem.source,
            framework: processedItem.framework,
            language: processedItem.language,
            title: processedItem.title,
            content: processedItem.content,
            filePath: processedItem.filePath,
            contentHash: processedItem.contentHash,
            lastCrawled: processedItem.lastCrawled,
            sourceType: processedItem.sourceType,
            packageId: processedItem.packageId,
            jsonData: processedItem.jsonData,
            minIOS: processedItem.minIOS,
            minMacOS: processedItem.minMacOS,
            minTvOS: processedItem.minTvOS,
            minWatchOS: processedItem.minWatchOS,
            minVisionOS: processedItem.minVisionOS,
            availabilitySource: processedItem.availabilitySource
        ))

        // Extract and index AST symbols if enabled
        if extractSymbols {
            let extracted = indexer.extractCode(from: processedItem)
            if !extracted.symbols.isEmpty {
                try await indexDocSymbols(
                    docUri: processedItem.uri,
                    symbols: extracted.symbols
                )
            }
            if !extracted.imports.isEmpty {
                try await indexDocImports(
                    docUri: processedItem.uri,
                    imports: extracted.imports
                )
            }
        }

        // Postprocess
        indexer.postprocess(processedItem)
    }

    /// Batch index multiple source items
    /// - Parameters:
    ///   - items: Array of source items to index
    ///   - extractSymbols: Whether to extract AST symbols
    ///   - progress: Optional progress reporter (called with `(processed, total)`)
    /// - Returns: Number of successfully indexed items
    @discardableResult
    public func indexItems(
        _ items: [Search.SourceItem],
        extractSymbols: Bool = true,
        progress: (any Search.IndexingProgressReporting)? = nil
    ) async throws -> Int {
        var successCount = 0

        for (index, item) in items.enumerated() {
            do {
                try await indexItem(item, extractSymbols: extractSymbols)
                successCount += 1
            } catch {
                // Log error but continue with other items
                // In production, could collect errors and report at end
            }
            progress?.report(processed: index + 1, total: items.count)
        }

        return successCount
    }

    /// Extract optimized FTS content based on document kind
    /// Core types get focused content (title, abstract, overview) without member noise
    /// Members get title + abstract + declaration for quick matching
    func extractOptimizedContent(from page: Shared.Models.StructuredDocumentationPage) -> String {
        let kind = page.inferredKind
        var parts: [String] = []

        switch kind {
        case .protocol, .class, .struct, .enum, .typeAlias, .actor:
            // Core types: high-signal content only
            // Repeat title multiple times to boost title matching in BM25
            parts.append(page.title)
            parts.append(page.title)
            parts.append(page.title)

            if let abstract = page.abstract {
                parts.append(abstract)
            }

            if let declaration = page.declaration?.code {
                parts.append(declaration)
            }

            if let overview = page.overview {
                // Take first 2000 chars of overview to avoid noise
                let truncated = String(overview.prefix(2000))
                parts.append(truncated)
            }

        case .method, .property, .operator, .macro,
             .enumCase, .initializer, .subscript:
            // Members: focused on identity and usage
            parts.append(page.title)
            parts.append(page.title)

            if let abstract = page.abstract {
                parts.append(abstract)
            }

            if let declaration = page.declaration?.code {
                parts.append(declaration)
            }

        case .article, .tutorial, .collection, .sampleCode:
            // Articles + sample-code landings: full content for
            // comprehensive search (sample-code pages benefit from the
            // same shape as articles — code excerpts in body, no symbol
            // declaration to lean on).
            if let raw = page.rawMarkdown {
                return raw
            }
            return page.markdown

        case .unknown, .framework, .function:
            // Unknown/framework/function: use raw content as fallback
            if let raw = page.rawMarkdown {
                return raw
            }
            return page.markdown
        }

        return parts.joined(separator: "\n\n")
    }

    /// Index a structured documentation page with full JSON data
    /// - Parameters:
    ///   - uri: Document URI
    ///   - source: High-level source category (apple-docs, swift-evolution, swift-org, swift-book)
    ///   - framework: Specific framework (swiftui, foundation, etc.) - for apple-docs only
    ///   - page: The structured documentation page
    ///   - jsonData: JSON representation of the page
    public func indexStructuredDocument(
        uri: String,
        source: String,
        framework: String,
        page: Shared.Models.StructuredDocumentationPage,
        jsonData: String,
        overrideMinIOS: String? = nil,
        overrideMinMacOS: String? = nil,
        overrideMinTvOS: String? = nil,
        overrideMinWatchOS: String? = nil,
        overrideMinVisionOS: String? = nil,
        overrideAvailabilitySource: String? = nil
    ) async throws {
        // Register framework alias if module is available
        if let module = page.module, !module.isEmpty {
            try await registerFrameworkAlias(identifier: framework, displayName: module)
        }

        // First, index the basic document (FTS + metadata with json_data)
        // Extract optimized content based on document kind to improve BM25 ranking
        var content = extractOptimizedContent(from: page)

        // Append @attributes to content for FTS searchability
        // This allows searching for @MainActor, @Sendable, @available etc.
        let attributes = page.extractedAttributes
        if !attributes.isEmpty {
            content += "\n\n" + attributes.joined(separator: " ")
        }

        // #113 — total-rewrite policy: kill every `doc://` link at the
        // indexer boundary. Same pattern as `indexDocument`. Applies to
        // both the FTS-side content blob and the JSON payload that
        // `read_document` / `cupertino read` serve back. JSON-safe.
        let contentRewrite = DocLinkRewriter.rewrite(content)
        content = contentRewrite.output
        let jsonRewrite = DocLinkRewriter.rewrite(jsonData)
        let rewrittenJsonData = jsonRewrite.output
        // #113 audit-count follow-up — emit per-page debug record when
        // any substitution happened. Same shape as `indexDocument`.
        let totalRewrites = contentRewrite.count + jsonRewrite.count
        if totalRewrites > 0 {
            logger.debug(
                "doc-link-rewrite: \(totalRewrites) substitutions in \(uri) (content=\(contentRewrite.count), json=\(jsonRewrite.count))",
                category: .search
            )
        }

        let summary = extractSummary(from: content)
        let wordCount = content.split(separator: " ").count

        // Get language from page or use heuristics
        let effectiveLanguage = page.language ?? detectLanguage(from: content)

        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        // Insert into FTS5 table (db should be deleted before full re-index).
        // `symbols` + `symbol_components` start empty; the AST pass
        // (#192 section D, #77 component split) UPDATEs both after
        // `doc_code_examples` has been populated.
        let ftsSql = """
        INSERT INTO docs_fts (uri, source, framework, language, title, content, summary, symbols, symbol_components)
        VALUES (?, ?, ?, ?, ?, ?, ?, '', '');
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, ftsSql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.prepareFailed("FTS insert: \(errorMessage)")
        }

        sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (framework as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (effectiveLanguage as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 5, (page.title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 6, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (summary as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.insertFailed("FTS insert: \(errorMessage)")
        }

        // Extract availability from JSON data, with optional overrides
        let jsonAvailability = extractAvailabilityFromJSON(jsonData)
        let finalIOS = overrideMinIOS ?? jsonAvailability.iOS
        let finalMacOS = overrideMinMacOS ?? jsonAvailability.macOS
        let finalTvOS = overrideMinTvOS ?? jsonAvailability.tvOS
        let finalWatchOS = overrideMinWatchOS ?? jsonAvailability.watchOS
        let finalVisionOS = overrideMinVisionOS ?? jsonAvailability.visionOS
        let finalSource = overrideAvailabilitySource ?? jsonAvailability.source

        // Classify (#192 C1). Structured path has `page.kind` available —
        // pass it plus the URI path for sample-code disambiguation.
        let classifiedKind = Search.Classify.kind(
            source: source,
            structuredKind: page.kind.rawValue,
            uriPath: uri
        ).rawValue

        // Insert metadata with json_data, availability, and kind (#192 C).
        // `kind` appended at end so existing bind indexes 1-16 stay stable.
        let metaSql = """
        INSERT OR REPLACE INTO docs_metadata \
        (uri, source, framework, language, file_path, content_hash, last_crawled, word_count, \
        source_type, json_data, min_ios, min_macos, min_tvos, min_watchos, min_visionos, \
        availability_source, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var metaStatement: OpaquePointer?
        defer { sqlite3_finalize(metaStatement) }

        guard sqlite3_prepare_v2(database, metaSql, -1, &metaStatement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.prepareFailed("Metadata insert: \(errorMessage)")
        }

        sqlite3_bind_text(metaStatement, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 2, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 3, (framework as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 4, (effectiveLanguage as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 5, (page.url.absoluteString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(metaStatement, 6, (page.contentHash as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(metaStatement, 7, Int64(page.crawledAt.timeIntervalSince1970))
        sqlite3_bind_int(metaStatement, 8, Int32(wordCount))
        sqlite3_bind_text(metaStatement, 9, (page.source.rawValue as NSString).utf8String, -1, nil)
        // #113 — bind the rewritten JSON blob (doc:// → https://) so the
        // `read_document` MCP tool + `cupertino read` serve clean links.
        // `extractAvailabilityFromJSON` above runs against the original
        // jsonData because it reads platform version numbers, not links.
        sqlite3_bind_text(metaStatement, 10, (rewrittenJsonData as NSString).utf8String, -1, nil)

        // Bind availability columns (use final values with overrides)
        bindOptionalText(metaStatement, 11, finalIOS)
        bindOptionalText(metaStatement, 12, finalMacOS)
        bindOptionalText(metaStatement, 13, finalTvOS)
        bindOptionalText(metaStatement, 14, finalWatchOS)
        bindOptionalText(metaStatement, 15, finalVisionOS)
        bindOptionalText(metaStatement, 16, finalSource)
        sqlite3_bind_text(metaStatement, 17, (classifiedKind as NSString).utf8String, -1, nil)

        guard sqlite3_step(metaStatement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.insertFailed("Metadata insert: \(errorMessage)")
        }

        // Insert structured fields for querying
        // swiftlint:disable:next line_length
        let structSql = "INSERT OR REPLACE INTO docs_structured (uri, url, title, kind, abstract, declaration, overview, module, platforms, conforms_to, inherited_by, conforming_types, attributes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"

        var structStatement: OpaquePointer?
        defer { sqlite3_finalize(structStatement) }

        guard sqlite3_prepare_v2(database, structSql, -1, &structStatement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.prepareFailed("Structured insert: \(errorMessage)")
        }

        sqlite3_bind_text(structStatement, 1, (uri as NSString).utf8String, -1, nil)
        sqlite3_bind_text(structStatement, 2, (page.url.absoluteString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(structStatement, 3, (page.title as NSString).utf8String, -1, nil)
        // Use inferredKind to correctly classify ~16,500 docs currently marked as "unknown"
        sqlite3_bind_text(structStatement, 4, (page.inferredKind.rawValue as NSString).utf8String, -1, nil)

        if let abstract = page.abstract {
            sqlite3_bind_text(structStatement, 5, (abstract as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 5)
        }

        if let declaration = page.declaration {
            sqlite3_bind_text(structStatement, 6, (declaration.code as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 6)
        }

        if let overview = page.overview {
            sqlite3_bind_text(structStatement, 7, (overview as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 7)
        }

        if let module = page.module {
            sqlite3_bind_text(structStatement, 8, (module as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 8)
        }

        if let platforms = page.platforms {
            let value = (platforms.joined(separator: ",") as NSString).utf8String
            sqlite3_bind_text(structStatement, 9, value, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 9)
        }

        if let conformsTo = page.conformsTo {
            let value = (conformsTo.joined(separator: ",") as NSString).utf8String
            sqlite3_bind_text(structStatement, 10, value, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 10)
        }

        if let inheritedBy = page.inheritedBy {
            let value = (inheritedBy.joined(separator: ",") as NSString).utf8String
            sqlite3_bind_text(structStatement, 11, value, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 11)
        }

        if let conformingTypes = page.conformingTypes {
            let value = (conformingTypes.joined(separator: ",") as NSString).utf8String
            sqlite3_bind_text(structStatement, 12, value, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 12)
        }

        // Store @attributes for filtering (reuse variable from FTS content extraction above)
        if !attributes.isEmpty {
            let value = (attributes.joined(separator: ",") as NSString).utf8String
            sqlite3_bind_text(structStatement, 13, value, -1, nil)
        } else {
            sqlite3_bind_null(structStatement, 13)
        }

        guard sqlite3_step(structStatement) == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.insertFailed("Structured insert: \(errorMessage)")
        }

        // Extract symbols from declaration using SwiftSyntax (#81). Re-running
        // the indexer over the same uri must not double rows, so clear first.
        if let declaration = page.declaration?.code {
            let extractor = ASTIndexer.Extractor()
            let result = extractor.extract(from: declaration)
            try await clearDocSymbols(docUri: uri)
            try await clearDocImports(docUri: uri)
            if !result.symbols.isEmpty {
                try await indexDocSymbols(docUri: uri, symbols: result.symbols)
            }
            if !result.imports.isEmpty {
                try await indexDocImports(docUri: uri, imports: result.imports)
            }
        }

        // #192 D extension: keep `docs_metadata.symbols` + `docs_fts.symbols`
        // in sync with whatever is in `doc_symbols` for this uri, regardless
        // of whether the names came from the declaration line or a code
        // example block. Earlier this pass only fired for code blocks, so
        // declaration-only symbol pages (the common case) missed the bm25
        // boost on type names.
        try await recomputeSymbolsBlob(docUri: uri)

        // #274 — write class-inheritance edges for the page. The
        // resolved URIs come from `page.inheritsFromURIs` and
        // `page.inheritedByURIs` (parallel to the title arrays;
        // populated by `AppleJSONToMarkdown.toStructuredPage` from
        // `doc.references`). Each row is one directed edge:
        // `child inherits from parent`. The same page contributes
        // edges in two directions: `inheritsFrom` rows put `page.uri`
        // in the child slot (with each ancestor as parent), while
        // `inheritedBy` rows put `page.uri` in the parent slot (with
        // each descendant as child). The composite primary key on
        // the inheritance table dedups overlapping edges seen from
        // both ends (e.g. UIControl's `inheritedBy: [UIButton]` and
        // UIButton's `inheritsFrom: [UIControl]` produce the same
        // row, written from whichever page is indexed first).
        //
        // #669 fallback: when the structured page predates PR #638
        // (which introduced the URI second-walk inside the JSON
        // parser), both arrays are nil and `writeInheritanceEdges`
        // no-ops, leaving the `inheritance` table empty for the
        // whole bundle. `resolveInheritanceURIs` re-derives them
        // from `page.rawMarkdown` (which crawlers of every vintage
        // preserve, including the 2026-05-09 corpus the v1.2.0
        // bundle was built from) so existing bundles can be
        // repaired with `cupertino save` alone — no recrawl. Once
        // a future crawl writes fresh JSON with the dedicated
        // arrays populated, the fallback no-ops because the
        // `nil && nil` guard fails inside the helper.
        let resolved = resolveInheritanceURIs(for: page)
        try await writeInheritanceEdges(
            pageURI: uri,
            inheritsFromURIs: resolved.inheritsFrom,
            inheritedByURIs: resolved.inheritedBy
        )
    }

    // MARK: - Symbol Indexing (#81)

    /// Index symbols extracted from Swift code in documentation
    func indexDocSymbols(
        docUri: String,
        symbols: [ASTIndexer.Symbol]
    ) async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = """
        INSERT INTO doc_symbols
        (doc_uri, name, kind, line, column, signature, is_async, is_throws,
         is_public, is_static, attributes, conformances, generic_params)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        for symbol in symbols {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                continue
            }

            sqlite3_bind_text(statement, 1, (docUri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (symbol.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (symbol.kind.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 4, Int32(symbol.line))
            sqlite3_bind_int(statement, 5, Int32(symbol.column))

            if let signature = symbol.signature {
                sqlite3_bind_text(statement, 6, (signature as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 6)
            }

            sqlite3_bind_int(statement, 7, symbol.isAsync ? 1 : 0)
            sqlite3_bind_int(statement, 8, symbol.isThrows ? 1 : 0)
            // #409 Layer 1 — repurpose `is_public`. The literal-keyword
            // extractor populated this from a `public` modifier on the
            // declaration, but Apple's doc code snippets never write
            // `public` explicitly (it's redundant; everything documented
            // IS public). Pre-fix the column read `1` for ~0% of rows
            // (24 of 168,259 in the v1.0.3 snapshot, all from
            // sample-code blocks or framework-design articles that
            // happened to include modifiers). The column carried no
            // useful signal for our corpus and confused anyone reading
            // the schema. Post-fix: for apple-docs-sourced pages, the
            // column reads `1` tautologically (every documented Apple
            // API is public). Any future internal sample-code blocks
            // (where `private` / `internal` actually appears in source)
            // fall through to the original literal-keyword interpretation
            // so a future "exclude internal helpers" query has the
            // signal it needs.
            let isPublic = docUri.hasPrefix(Shared.Constants.SourcePrefix.appleDocs + "://")
                ? true
                : symbol.isPublic
            sqlite3_bind_int(statement, 9, isPublic ? 1 : 0)
            sqlite3_bind_int(statement, 10, symbol.isStatic ? 1 : 0)

            let attributesStr = symbol.attributes.isEmpty
                ? nil : symbol.attributes.joined(separator: ",")
            let conformancesStr = symbol.conformances.isEmpty
                ? nil : symbol.conformances.joined(separator: ",")
            let genericParamsStr = symbol.genericParameters.isEmpty
                ? nil : symbol.genericParameters.joined(separator: ",")

            if let attrs = attributesStr {
                sqlite3_bind_text(statement, 11, (attrs as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 11)
            }

            if let confs = conformancesStr {
                sqlite3_bind_text(statement, 12, (confs as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 12)
            }

            if let generics = genericParamsStr {
                sqlite3_bind_text(statement, 13, (generics as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 13)
            }

            _ = sqlite3_step(statement)

            // Insert into FTS
            try await indexDocSymbolFTS(symbol: symbol)
        }
    }

    /// Index symbol into FTS table
    func indexDocSymbolFTS(symbol: ASTIndexer.Symbol) async throws {
        guard let database else { return }

        let sql = """
        INSERT INTO doc_symbols_fts (name, signature, attributes, conformances)
        VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        sqlite3_bind_text(statement, 1, (symbol.name as NSString).utf8String, -1, nil)

        if let signature = symbol.signature {
            sqlite3_bind_text(statement, 2, (signature as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 2)
        }

        let attributesStr = symbol.attributes.joined(separator: " ")
        let conformancesStr = symbol.conformances.joined(separator: " ")

        sqlite3_bind_text(statement, 3, (attributesStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (conformancesStr as NSString).utf8String, -1, nil)

        _ = sqlite3_step(statement)
    }

    /// Index imports extracted from Swift code in documentation
    func indexDocImports(
        docUri: String,
        imports: [ASTIndexer.Import]
    ) async throws {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let sql = """
        INSERT INTO doc_imports (doc_uri, module_name, line, is_exported)
        VALUES (?, ?, ?, ?);
        """

        for imp in imports {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                continue
            }

            sqlite3_bind_text(statement, 1, (docUri as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (imp.moduleName as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 3, Int32(imp.line))
            sqlite3_bind_int(statement, 4, imp.isExported ? 1 : 0)

            _ = sqlite3_step(statement)
        }
    }
}
