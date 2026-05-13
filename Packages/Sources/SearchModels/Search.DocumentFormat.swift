import Foundation

/// Output format for document content fetched out of the search-index
/// database.
///
/// Lifted out of `Search.Index.DocumentFormat` (the indexer-internal
/// enum) into the SearchModels target so resource-rendering consumers
/// (Services, MCPSupport, CLI) can pass a format value to the indexer
/// without taking a behavioural dependency on the Search target.
extension Search {
    public enum DocumentFormat: Sendable {
        /// Return the full structured JSON serialization of the page.
        case json
        /// Return the rendered markdown out of the `rawMarkdown` field.
        case markdown
    }
}
