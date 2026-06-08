import SearchModels

// MARK: - CupertinoDataEngine.SourceReaderBox

extension CupertinoDataEngine {
    struct SourceReaderBox: SourceReader {
        let base: any Search.Database

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
            try await base.search(
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
            try await base.getDocumentContent(uri: uri, format: format)
        }

        func listFrameworks() async throws -> [String: Int] {
            try await base.listFrameworks()
        }

        func documentCount() async throws -> Int {
            try await base.documentCount()
        }

        func disconnect() async {
            await base.disconnect()
        }

        func searchSymbols(
            query: String?,
            kind: String?,
            isAsync: Bool?,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await base.searchSymbols(query: query, kind: kind, isAsync: isAsync, framework: framework, limit: limit)
        }

        func searchPropertyWrappers(
            wrapper: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await base.searchPropertyWrappers(wrapper: wrapper, framework: framework, limit: limit)
        }

        func searchConcurrencyPatterns(
            pattern: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await base.searchConcurrencyPatterns(pattern: pattern, framework: framework, limit: limit)
        }

        func searchConformances(
            protocolName: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await base.searchConformances(protocolName: protocolName, framework: framework, limit: limit)
        }

        func searchByGenericConstraint(
            constraint: String,
            framework: String?,
            limit: Int
        ) async throws -> [Search.SymbolSearchResult] {
            try await base.searchByGenericConstraint(constraint: constraint, framework: framework, limit: limit)
        }

        func resolveSymbolURIs(title: String) async throws -> [Search.InheritanceCandidate] {
            try await base.resolveSymbolURIs(title: title)
        }

        func walkInheritance(
            startURI: String,
            direction: Search.InheritanceDirection,
            maxDepth: Int
        ) async throws -> Search.InheritanceTree {
            try await base.walkInheritance(startURI: startURI, direction: direction, maxDepth: maxDepth)
        }

        func fetchPlatformMinima(uris: [String]) async throws -> [String: Search.PlatformMinima] {
            try await base.fetchPlatformMinima(uris: uris)
        }

        func getFrameworkAvailability(framework: String) async -> Search.FrameworkAvailability {
            await base.getFrameworkAvailability(framework: framework)
        }

        func listResourceEntries(mode: Search.ResourceListMode) async throws -> [Search.URIResource] {
            try await base.listResourceEntries(mode: mode)
        }
    }
}
