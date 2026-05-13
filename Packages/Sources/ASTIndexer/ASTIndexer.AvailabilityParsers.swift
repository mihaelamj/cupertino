import Foundation

extension ASTIndexer {
    /// Parsers that pull availability metadata out of Swift package source.
    /// Pure functions — no I/O, no AST, regex-based on raw strings. Used by
    /// both `Core.PackageAvailabilityAnnotator` (#219) and `SampleIndex`'s
    /// indexer (#228). Sat in Core originally; lifted here so SampleIndex
    /// can reuse without depending on the heavier Core target.
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
        /// Per-line scan; multi-line attributes (rare) are not handled and
        /// remain a follow-up under #221. Records line number (1-indexed),
        /// the raw paren content, and a list of platform tokens parsed from
        /// the args (first whitespace-delimited word per comma-separated
        /// entry, with `*` and named keywords like `deprecated` / `noasync`
        /// preserved verbatim).
        public static func extractAvailability(from source: String) -> [Attribute] {
            var attrs: [Attribute] = []
            var lineNo = 0
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                lineNo += 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let avRange = trimmed.range(of: "@available") else { continue }
                guard let openParen = trimmed.range(
                    of: "(",
                    range: avRange.upperBound..<trimmed.endIndex
                ) else { continue }

                var depth = 0
                var endIndex: String.Index?
                var idx = openParen.lowerBound
                while idx < trimmed.endIndex {
                    let char = trimmed[idx]
                    if char == "(" {
                        depth += 1
                    } else if char == ")" {
                        depth -= 1
                        if depth == 0 {
                            endIndex = trimmed.index(after: idx)
                            break
                        }
                    }
                    idx = trimmed.index(after: idx)
                }
                guard let close = endIndex else { continue }
                let raw = String(trimmed[openParen.lowerBound..<close])
                let innerStart = trimmed.index(after: openParen.lowerBound)
                let innerEnd = trimmed.index(before: close)
                guard innerStart <= innerEnd else { continue }
                let inner = String(trimmed[innerStart..<innerEnd])

                let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var platforms: [String] = []
                for part in parts where !part.isEmpty {
                    let firstToken = part.split(whereSeparator: { $0 == " " || $0 == ":" })
                        .first.map(String.init) ?? part
                    platforms.append(firstToken)
                }
                attrs.append(Attribute(line: lineNo, raw: raw, platforms: platforms))
            }
            return attrs
        }
    }
}
