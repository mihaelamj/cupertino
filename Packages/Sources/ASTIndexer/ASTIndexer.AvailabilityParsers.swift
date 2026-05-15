import Foundation
import SwiftParser
import SwiftSyntax

extension ASTIndexer {
    /// Parsers that pull availability metadata out of Swift package source.
    ///
    /// Public surface is two pure functions:
    ///
    /// - ``parsePlatforms(from:)`` reads the `platforms: [...]` block of a
    ///   `Package.swift` manifest. Regex-based; multi-line declarations are
    ///   fine since the regex is multi-line capable.
    /// - ``extractAvailability(from:)`` finds every `@available(...)`
    ///   attribute in arbitrary Swift source. Pre-#221 this was a per-line
    ///   regex/string scan that silently dropped multi-line attributes;
    ///   it now walks a SwiftSyntax tree so multi-line attrs, attrs split
    ///   across continuation lines, and attrs inside macro/string-adjacent
    ///   contexts all index correctly.
    ///
    /// Used by both ``Core/PackageIndexing/PackageAvailabilityAnnotator``
    /// (#219) and SampleIndex's indexer (#228). Lifted here from Core so
    /// SampleIndex can reuse without depending on the heavier Core target.
    public enum AvailabilityParsers {
        /// One `@available(...)` occurrence in a source file.
        public struct Attribute: Codable, Sendable, Equatable {
            public let line: Int
            public let raw: String
            public let platforms: [String]

            public init(line: Int, raw: String, platforms: [String]) {
                self.line = line
                self.raw = raw
                self.platforms = platforms
            }
        }

        /// Extract the platform → version mapping from a `Package.swift`
        /// source string. Matches `.iOS(.v16)`, `.macOS(.v10_15)`, etc.
        /// inside the first `platforms: [...]` block. Multi-line declarations
        /// are fine; nested array literals other than `platforms:` are
        /// ignored.
        public static func parsePlatforms(from packageSwift: String) -> [String: String] {
            guard let blockMatch = packageSwift.range(
                of: #"platforms\s*:\s*\[([\s\S]*?)\]"#,
                options: .regularExpression
            ) else {
                return [:]
            }
            let block = String(packageSwift[blockMatch])

            var targets: [String: String] = [:]
            let entryPattern = #"\.([A-Za-z]+)\s*\(\s*\.v([0-9_]+)\s*\)"#
            guard let regex = try? NSRegularExpression(pattern: entryPattern) else { return [:] }
            let nsBlock = block as NSString
            let matches = regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length))
            for match in matches where match.numberOfRanges == 3 {
                let platform = nsBlock.substring(with: match.range(at: 1))
                let raw = nsBlock.substring(with: match.range(at: 2))
                let normalized = raw.replacingOccurrences(of: "_", with: ".")
                let version = normalized.contains(".") ? normalized : "\(normalized).0"
                targets[platform] = version
            }
            return targets
        }

        /// Find every `@available(...)` attribute in a Swift source string.
        ///
        /// Walks a SwiftSyntax tree, so:
        /// - Multi-line attrs are captured (the #221 fix). `raw` collapses
        ///   internal newlines and runs of whitespace to a single space so
        ///   downstream consumers see one shape regardless of formatting.
        /// - `line` is the 1-indexed source line of the leading `@` token.
        /// - `platforms` is the first whitespace-/colon-separated token of
        ///   each comma-separated argument (e.g. `iOS 16.0` → `iOS`,
        ///   `message: "..."` → `message`). Matches the pre-#221 contract
        ///   so existing callers (`PackageAvailabilityAnnotator`,
        ///   `SampleIndex`) need no changes.
        /// - `@available` occurrences inside string literals, comments, or
        ///   trivia no longer false-match — the previous regex scan caught
        ///   those; the AST does not.
        public static func extractAvailability(from source: String) -> [Attribute] {
            let tree = Parser.parse(source: source)
            let converter = SourceLocationConverter(fileName: "", tree: tree)
            let visitor = AvailabilityVisitor(converter: converter)
            visitor.walk(tree)
            return visitor.attributes
        }
    }
}

// MARK: - Availability Visitor

/// `SyntaxVisitor` that collects every `@available(...)` attribute
/// occurrence — see ``ASTIndexer/AvailabilityParsers/extractAvailability(from:)``.
/// File-scoped so it can be referenced from the parser's nested enum
/// without leaking into the public surface.
private final class AvailabilityVisitor: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private(set) var attributes: [ASTIndexer.AvailabilityParsers.Attribute] = []

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        guard node.attributeName.trimmedDescription == "available" else {
            return .visitChildren
        }
        guard let args = node.arguments else { return .visitChildren }

        // `args.trimmedDescription` preserves internal whitespace including
        // newlines for multi-line attrs; collapse to a single space so the
        // emitted `raw` is one-line regardless of formatting.
        let argsText = args.trimmedDescription
        let normalized = collapseWhitespace(argsText)
        let raw = "(\(normalized))"

        // Line of the leading `@` token, 1-indexed.
        let lineNo = node.atSign.startLocation(converter: converter).line

        // Match the pre-#221 platform-token contract exactly so existing
        // callers see no behaviour change on already-supported single-line
        // forms.
        let parts = normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var platforms: [String] = []
        for part in parts where !part.isEmpty {
            let firstToken = part.split(whereSeparator: { $0 == " " || $0 == ":" })
                .first.map(String.init) ?? part
            platforms.append(firstToken)
        }

        attributes.append(ASTIndexer.AvailabilityParsers.Attribute(
            line: lineNo,
            raw: raw,
            platforms: platforms
        ))
        return .visitChildren
    }

    /// Collapse every run of whitespace (including newlines + indentation
    /// inside the trimmed args description) to a single ASCII space.
    private func collapseWhitespace(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        var lastWasSpace = false
        for scalar in input.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
