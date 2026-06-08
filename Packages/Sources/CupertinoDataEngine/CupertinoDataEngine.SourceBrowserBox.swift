import SearchModels

// MARK: - CupertinoDataEngine.SourceBrowserBox

extension CupertinoDataEngine {
    struct SourceBrowserBox: SourceBrowser {
        let base: any Search.Database & Search.DocumentBrowsing

        private var reader: SourceReaderBox {
            SourceReaderBox(base: base)
        }

        func listDocuments(
            source: String,
            framework: String,
            offset: Int,
            limit: Int
        ) async throws -> Search.DocumentListPage {
            try await base.listDocuments(source: source, framework: framework, offset: offset, limit: limit)
        }

        func listChildren(
            source: String,
            uri: String
        ) async throws -> Search.DocumentChildrenPage {
            try await base.listChildren(source: source, uri: uri)
        }

        // swiftlint:disable:next function_parameter_count
        func search(
            query: String,
            source: String?,
            framework: String?,
            language: String?,
            limit: Int,
            includeArchive: Bool,
            minIOS: String?,
            minMacOS: String?,
            minTvOS: String?,
            minWatchOS: String?,
            minVisionOS: String?,
            minSwift: String?
        ) async throws -> [Search.Result] {
            try await reader.search(
                query: query,
                source: source,
                framework: framework,
                language: language,
                limit: limit,
                includeArchive: includeArchive,
                minIOS: minIOS,
                minMacOS: minMacOS,
                minTvOS: minTvOS,
                minWatchOS: minWatchOS,
                minVisionOS: minVisionOS,
                minSwift: minSwift
            )
        }

        func getDocumentContent(uri: String, format: Search.DocumentFormat) async throws -> String? {
            try await reader.getDocumentContent(uri: uri, format: format)
        }

        func listFrameworks() async throws -> [String: Int] {
            try await reader.listFrameworks()
        }

        func documentCount() async throws -> Int {
            try await reader.documentCount()
        }

        func disconnect() async {
            await reader.disconnect()
        }

        func searchSymbols(
            query: String?,
            kind: String?,
            isAsync: Bool?,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchSymbols(query: query, kind: kind, isAsync: isAsync, framework: framework, limit: limit)
        }

        func searchPropertyWrappers(
            wrapper: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchPropertyWrappers(wrapper: wrapper, framework: framework, limit: limit)
        }

        func searchConcurrencyPatterns(
            pattern: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchConcurrencyPatterns(pattern: pattern, framework: framework, limit: limit)
        }

        func searchConformances(
            protocolName: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchConformances(protocolName: protocolName, framework: framework, limit: limit)
        }

        func searchByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await reader.searchByGenericConstraint(constraint: constraint, framework: framework, limit: limit)
        }

        func resolveSymbolURIs(title: String) async throws -> [Search.InheritanceCandidate] {
            try await reader.resolveSymbolURIs(title: title)
        }

        func walkInheritance(
            startURI: String,
            direction: Search.InheritanceDirection,
            maxDepth: Int
        ) async throws -> Search.InheritanceTree {
            try await reader.walkInheritance(startURI: startURI, direction: direction, maxDepth: maxDepth)
        }

        func fetchPlatformMinima(uris: [String]) async throws -> [String: Search.PlatformMinima] {
            try await reader.fetchPlatformMinima(uris: uris)
        }

        func getFrameworkAvailability(framework: String) async -> Search.FrameworkAvailability {
            await reader.getFrameworkAvailability(framework: framework)
        }

        func listResourceEntries(mode: Search.ResourceListMode) async throws -> [Search.URIResource] {
            try await reader.listResourceEntries(mode: mode)
        }
    }
}
