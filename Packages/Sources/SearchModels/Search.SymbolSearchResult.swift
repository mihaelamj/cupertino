import Foundation

/// Symbol search result with document context.
///
/// Lifted out of `Search.Index.SymbolSearchResult` (the nested type
/// inside the Search.Index actor in the Search target) to top-level
/// `Search.SymbolSearchResult` in SearchModels so consumers
/// (SearchToolProvider, MCP responders) can decode + render semantic-
/// search hits without taking a behavioural dependency on the Search
/// target.
extension Search {
    public struct SymbolSearchResult: Sendable {
        public let docUri: String
        public let docTitle: String
        public let framework: String
        public let symbolName: String
        public let symbolKind: String
        public let signature: String?
        public let attributes: String?
        public let conformances: String?
        public let isAsync: Bool
        public let isPublic: Bool

        public init(
            docUri: String,
            docTitle: String,
            framework: String,
            symbolName: String,
            symbolKind: String,
            signature: String?,
            attributes: String?,
            conformances: String?,
            isAsync: Bool,
            isPublic: Bool
        ) {
            self.docUri = docUri
            self.docTitle = docTitle
            self.framework = framework
            self.symbolName = symbolName
            self.symbolKind = symbolKind
            self.signature = signature
            self.attributes = attributes
            self.conformances = conformances
            self.isAsync = isAsync
            self.isPublic = isPublic
        }
    }
}
