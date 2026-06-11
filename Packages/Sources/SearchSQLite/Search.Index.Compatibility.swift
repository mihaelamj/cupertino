import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

// MARK: - Backward Compatibility Extension

/// Added to maintain backward compatibility with existing unit tests.
/// These methods delegate write/indexing operations to a temporary Search.Indexer.
extension Search.Index {
    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func indexDocument(_ params: Search.IndexDocumentParams) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.indexDocument(params)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
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
        overrideAvailabilitySource: String? = nil,
        implementationSwiftVersion: String? = nil
    ) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.indexStructuredDocument(
            uri: uri,
            source: source,
            framework: framework,
            page: page,
            jsonData: jsonData,
            overrideMinIOS: overrideMinIOS,
            overrideMinMacOS: overrideMinMacOS,
            overrideMinTvOS: overrideMinTvOS,
            overrideMinWatchOS: overrideMinWatchOS,
            overrideMinVisionOS: overrideMinVisionOS,
            overrideAvailabilitySource: overrideAvailabilitySource,
            implementationSwiftVersion: implementationSwiftVersion
        )
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func indexItem(_ item: Search.SourceItem, extractSymbols: Bool = true) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.indexItem(item, extractSymbols: extractSymbols)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    @discardableResult
    public func indexItems(
        _ items: [Search.SourceItem],
        extractSymbols: Bool = true,
        progress: (any Search.IndexingProgressReporting)? = nil
    ) async throws -> Int {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        return try await indexer.indexItems(items, extractSymbols: extractSymbols, progress: progress)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func registerFrameworkAlias(identifier: String, displayName: String) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.registerFrameworkAlias(identifier: identifier, displayName: displayName)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func updateFrameworkSynonyms(identifier: String, synonyms: String) async throws -> Int {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        return try await indexer.updateFrameworkSynonyms(identifier: identifier, synonyms: synonyms)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func clearIndex() async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.clearIndex()
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func indexPackage(
        owner: String,
        name: String,
        repositoryURL: String,
        description: String?,
        stars: Int,
        isAppleOfficial: Bool,
        lastUpdated: String?
    ) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.indexPackage(
            owner: owner,
            name: name,
            repositoryURL: repositoryURL,
            description: description,
            stars: stars,
            isAppleOfficial: isAppleOfficial,
            lastUpdated: lastUpdated
        )
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func indexSampleCode(
        url: String,
        framework: String,
        title: String,
        description: String,
        zipFilename: String,
        webURL: String,
        minIOS: String? = nil,
        minMacOS: String? = nil,
        minTvOS: String? = nil,
        minWatchOS: String? = nil,
        minVisionOS: String? = nil
    ) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.indexSampleCode(
            url: url,
            framework: framework,
            title: title,
            description: description,
            zipFilename: zipFilename,
            webURL: webURL,
            minIOS: minIOS,
            minMacOS: minMacOS,
            minTvOS: minTvOS,
            minWatchOS: minWatchOS,
            minVisionOS: minVisionOS
        )
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func indexCodeExamples(
        docUri: String,
        codeExamples: [(code: String, language: String)]
    ) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.indexCodeExamples(docUri: docUri, codeExamples: codeExamples)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    func indexDocSymbols(docUri: String, symbols: [ASTIndexer.Symbol]) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.indexDocSymbols(docUri: docUri, symbols: symbols)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func writeInheritanceEdges(
        pageURI: String,
        inheritsFromURIs: [String]?,
        inheritedByURIs: [String]?
    ) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.writeInheritanceEdges(
            pageURI: pageURI,
            inheritsFromURIs: inheritsFromURIs,
            inheritedByURIs: inheritedByURIs
        )
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    @discardableResult
    public func applyHIGPlatformInference(
        audit: (any Search.EnrichmentAuditObserver)? = nil,
        dbPath: String = ""
    ) async throws -> Int {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        return try await indexer.applyHIGPlatformInference(audit: audit, dbPath: dbPath)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    @discardableResult
    public func applyAppleStaticConformances(
        lookup: (any Search.StaticConformancesLookup)?,
        audit: (any Search.EnrichmentAuditObserver)? = nil,
        dbPath: String = ""
    ) async throws -> Int {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        return try await indexer.applyAppleStaticConformances(lookup: lookup, audit: audit, dbPath: dbPath)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    @discardableResult
    public func applyAppleStaticConstraints(
        lookup: (any Search.StaticConstraintsLookup)?,
        audit: (any Search.EnrichmentAuditObserver)? = nil,
        dbPath: String = ""
    ) async throws -> Int {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        return try await indexer.applyAppleStaticConstraints(lookup: lookup, audit: audit, dbPath: dbPath)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    @discardableResult
    public func propagateConstraintsFromParents(
        audit: (any Search.EnrichmentAuditObserver)? = nil,
        dbPath: String = ""
    ) async throws -> Int {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        return try await indexer.propagateConstraintsFromParents(audit: audit, dbPath: dbPath)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func stampUserVersionUnchecked(_ version: Int32) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.stampUserVersionUnchecked(version)
    }

    @available(*, deprecated, message: "Use Search.Indexer.extractInheritanceURIsFromMarkdown")
    public static func extractInheritanceURIsFromMarkdown(
        _ markdown: String
    ) -> (inheritsFrom: [String], inheritedBy: [String]) {
        Search.Indexer.extractInheritanceURIsFromMarkdown(markdown)
    }

    @available(*, deprecated, message: "Use Search.Indexer.combinedGenericConstraints")
    public static func combinedGenericConstraints(
        fromAST genericParameters: [String]
    ) -> String? {
        Search.Indexer.combinedGenericConstraints(fromAST: genericParameters)
    }

    @available(*, deprecated, message: "Use Search.Indexer.parentURI")
    public static func parentURI(of uri: String) -> String? {
        Search.Indexer.parentURI(of: uri)
    }

    @available(*, deprecated, message: "Use Search.Indexer.extractBareParamNames")
    public static func extractBareParamNames(from genericParams: String) -> [String] {
        Search.Indexer.extractBareParamNames(from: genericParams)
    }

    @available(*, deprecated, message: "Use Search.Indexer.signatureReferencesAnyParam")
    public static func signatureReferencesAnyParam(_ signature: String, paramNames: [String]) -> Bool {
        Search.Indexer.signatureReferencesAnyParam(signature, paramNames: paramNames)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func extractCodeExampleSymbols(
        docUri: String,
        codeExamples: [(code: String, language: String)]
    ) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.extractCodeExampleSymbols(docUri: docUri, codeExamples: codeExamples)
    }

    @available(*, deprecated, message: "Use Search.Indexer.splitCamelCaseIdentifier")
    public static func splitCamelCaseIdentifier(_ identifier: String) -> [String] {
        Search.Indexer.splitCamelCaseIdentifier(identifier)
    }

    @available(*, deprecated, message: "Use Search.Indexer.splitCamelCaseIdentifiers")
    public static func splitCamelCaseIdentifiers(_ identifiers: some Collection<String>) -> [String] {
        Search.Indexer.splitCamelCaseIdentifiers(identifiers)
    }

    @available(*, deprecated, message: "Use Search.Indexer for write operations")
    public func recomputeSymbolsBlob(docUri: String) async throws {
        let indexer = Search.Indexer(connection: connection, logger: logger, indexers: indexers, sourceLookup: sourceLookup)
        try await indexer.recomputeSymbolsBlob(docUri: docUri)
    }
}
