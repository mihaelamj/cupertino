import Foundation
import Shared
import SQLite3

extension Search.Index {
    func extractSourcePrefix(_ query: String) -> (source: String?, remainingQuery: String) {
        let lowercased = query.lowercased()

        for prefix in Self.knownSourcePrefixes where lowercased.hasPrefix(prefix) {
            // Check if it's followed by whitespace or end of string
            let afterPrefix = query.dropFirst(prefix.count)
            if afterPrefix.isEmpty || afterPrefix.first?.isWhitespace == true {
                let remaining = String(afterPrefix).trimmingCharacters(in: .whitespaces)
                return (prefix, remaining)
            }
        }

        return (nil, query)
    }

    /// Known Swift attributes that can be searched with or without @ prefix
    /// Based on attributes actually present in Apple documentation declarations
    /// TODO(#81): When SwiftSyntax AST indexing is implemented, this list should be
    /// replaced with attributes extracted directly from parsed declarations
    static let knownAttributes: Set<String> = [
        // Concurrency
        "MainActor", "Sendable", "preconcurrency",
        // Memory/copying
        "NSCopying", "frozen",
        // Objective-C interop
        "objc", "objcMembers", "nonobjc", "IBAction", "IBOutlet",
        // Function attributes
        "discardableResult", "warn_unqualified_access", "inlinable", "usableFromInline",
        // Type attributes
        "dynamicMemberLookup", "dynamicCallable", "propertyWrapper", "resultBuilder",
        // SwiftUI builders
        "ViewBuilder", "ToolbarContentBuilder", "CommandsBuilder", "SceneBuilder",
        // Macros
        "freestanding", "attached",
        // Availability
        "backDeployed", "available",
        // SwiftUI property wrappers (for future use)
        "State", "Binding", "Environment", "Published",
        "ObservedObject", "StateObject", "EnvironmentObject",
        "AppStorage", "SceneStorage", "FocusState",
        // SwiftData
        "Model", "Query", "Attribute", "Relationship",
    ]

    /// Extract @attribute patterns from query for filtering
    /// - Parameter query: User's search query (e.g., "@MainActor View" or "MainActor View")
    /// - Returns: Tuple of (attributes to filter, query for FTS with @ stripped)
    /// - Example: "@MainActor View" -> (["@MainActor"], "MainActor View")
    /// - Example: "MainActor View" -> (["@MainActor"], "MainActor View")
    func extractAttributeFilters(_ query: String) -> (attributes: [String], ftsQuery: String) {
        var attributes: [String] = []
        var ftsQuery = query

        // First, handle explicit @Attribute patterns (including those with arguments)
        let explicitPattern = #"@[A-Z][a-zA-Z0-9]*(?:\([^)]*\))?"#
        if let regex = try? NSRegularExpression(pattern: explicitPattern) {
            let range = NSRange(query.startIndex..., in: query)
            let matches = regex.matches(in: query, range: range)

            for match in matches.reversed() {
                if let matchRange = Range(match.range, in: query) {
                    let attribute = String(query[matchRange])
                    attributes.insert(attribute, at: 0)

                    // Strip @ from FTS query but keep the name for searchability
                    let withoutAt = attribute.dropFirst()
                    ftsQuery.replaceSubrange(matchRange, with: withoutAt)
                }
            }
        }

        // Then, check for known attribute names without @ prefix
        let words = ftsQuery.components(separatedBy: .whitespaces)
        for word in words {
            let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
            if Self.knownAttributes.contains(trimmed), !attributes.contains("@\(trimmed)") {
                attributes.append("@\(trimmed)")
            }
        }

        return (attributes, ftsQuery)
    }

    /// Sanitize a search query for FTS5
    /// - Splits on whitespace and hyphens (except for known framework prefixes)
    /// - Quotes each term to avoid FTS5 operator interpretation
    /// - Example: "concurrency actors" -> "\"concurrency\" \"actors\""
    func sanitizeFTS5Query(_ query: String) -> String {
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-"))
        let terms = query
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }
        return terms.joined(separator: " ")
    }
}
