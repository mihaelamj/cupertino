import Foundation

/// A symbol extracted from documentation that matched the search query.
///
/// Lifted into SearchModels so result-consuming layers (Services formatters,
/// MCP responders, CLI) can decode + render matched-symbol entries without
/// importing the Search target's behavioural surface.
extension Search {
    public struct MatchedSymbol: Codable, Sendable, Hashable {
        /// Symbol kind label as emitted by the indexer
        /// (e.g. `struct`, `class`, `actor`, `enum`, `protocol`, `function`, `property`).
        public let kind: String
        public let name: String
        /// Full signature for functions / methods; `nil` for non-callable
        /// kinds (types, properties).
        public let signature: String?
        public let isAsync: Bool

        public init(kind: String, name: String, signature: String? = nil, isAsync: Bool = false) {
            self.kind = kind
            self.name = name
            self.signature = signature
            self.isAsync = isAsync
        }

        /// Compact display format
        /// (e.g., `"class UIFontMetrics"` or `"func scaledFont(for:)"`).
        public var displayString: String {
            if let sig = signature, !sig.isEmpty {
                return "\(kind) \(sig)"
            }
            return "\(kind) \(name)"
        }
    }
}
