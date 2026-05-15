import CryptoKit
import Foundation

// MARK: - Structured Documentation Page

/// Represents a fully structured documentation page with rich content
/// This model is designed to be populated from both Apple JSON API and HTML sources
/// and is suitable for database storage and querying
// swiftlint:disable:next type_body_length
extension Shared.Models {
    public struct StructuredDocumentationPage: Codable, Sendable, Identifiable, Hashable {
        public let id: UUID
        public let url: URL
        public let title: String
        public let kind: Kind
        public let source: Source

        // Content
        public let abstract: String?
        public let declaration: Declaration?
        public let overview: String?
        public let sections: [Section]
        public let codeExamples: [CodeExample]

        // Apple-specific metadata (nil for non-Apple sources)
        public let language: String? // Programming language (swift, objc, etc.)
        public let platforms: [String]?
        public let module: String?
        public let conformsTo: [String]? // Protocols this type conforms to
        public let inheritedBy: [String]? // Types that inherit from this
        public let conformingTypes: [String]? // Types that conform to this protocol

        /// Raw markdown from original source (HTML conversion)
        public let rawMarkdown: String?

        // Crawl metadata
        public let crawledAt: Date
        public let contentHash: String
        /// Hops from the start URL when this page was discovered. nil for
        /// pages saved by binaries that pre-date depth stamping.
        public let crawlDepth: Int?

        public init(
            id: UUID = UUID(),
            url: URL,
            title: String,
            kind: Kind,
            source: Source,
            abstract: String? = nil,
            declaration: Declaration? = nil,
            overview: String? = nil,
            sections: [Section] = [],
            codeExamples: [CodeExample] = [],
            language: String? = nil,
            platforms: [String]? = nil,
            module: String? = nil,
            conformsTo: [String]? = nil,
            inheritedBy: [String]? = nil,
            conformingTypes: [String]? = nil,
            rawMarkdown: String? = nil,
            crawledAt: Date = Date(),
            contentHash: String = "",
            crawlDepth: Int? = nil
        ) {
            self.id = id
            self.url = url
            self.title = title
            self.kind = kind
            self.source = source
            self.abstract = abstract
            self.declaration = declaration
            self.overview = overview
            self.sections = sections
            self.codeExamples = codeExamples
            self.language = language
            self.platforms = platforms
            self.module = module
            self.conformsTo = conformsTo
            self.inheritedBy = inheritedBy
            self.conformingTypes = conformingTypes
            self.rawMarkdown = rawMarkdown
            self.crawledAt = crawledAt
            self.contentHash = contentHash
            self.crawlDepth = crawlDepth
        }

        // MARK: - Codable

        /// Custom decoder to handle missing "id" field in old JSON files
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            url = try container.decode(URL.self, forKey: .url)
            // Derive a deterministic id if missing (older records lack this field).
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? Self.deterministicID(for: url)
            title = try container.decode(String.self, forKey: .title)
            kind = try container.decode(Kind.self, forKey: .kind)
            source = try container.decode(Source.self, forKey: .source)
            abstract = try container.decodeIfPresent(String.self, forKey: .abstract)
            declaration = try container.decodeIfPresent(Declaration.self, forKey: .declaration)
            overview = try container.decodeIfPresent(String.self, forKey: .overview)
            sections = try container.decode([Section].self, forKey: .sections)
            codeExamples = try container.decode([CodeExample].self, forKey: .codeExamples)
            language = try container.decodeIfPresent(String.self, forKey: .language)
            platforms = try container.decodeIfPresent([String].self, forKey: .platforms)
            module = try container.decodeIfPresent(String.self, forKey: .module)
            conformsTo = try container.decodeIfPresent([String].self, forKey: .conformsTo)
            inheritedBy = try container.decodeIfPresent([String].self, forKey: .inheritedBy)
            conformingTypes = try container.decodeIfPresent([String].self, forKey: .conformingTypes)
            rawMarkdown = try container.decodeIfPresent(String.self, forKey: .rawMarkdown)
            crawledAt = try container.decode(Date.self, forKey: .crawledAt)
            contentHash = try container.decode(String.self, forKey: .contentHash)
            crawlDepth = try container.decodeIfPresent(Int.self, forKey: .crawlDepth)
        }

        private enum CodingKeys: String, CodingKey {
            case id, url, title, kind, source
            case abstract, declaration, overview, sections, codeExamples
            case language, platforms, module
            case conformsTo, inheritedBy, conformingTypes
            case rawMarkdown, crawledAt, contentHash, crawlDepth
        }

        // MARK: - Nested Types

        /// The kind/type of documentation page
        ///
        /// Raw values match `parseKind`'s normalised dispatch tokens; the
        /// search ranker's `canonicalTypeKinds` and `propertyMethodKinds`
        /// sets read these values verbatim, so any new case must be
        /// reflected there as well.
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case `protocol`
            case `class`
            case `struct`
            case `enum`
            case function
            case property
            case method
            case `operator`
            case typeAlias = "typealias"
            case macro
            case article
            case tutorial
            case collection // API collection (index page)
            case framework
            // #626 — pre-existing dispatch returned `.unknown` for these
            // four Apple `roleHeading` values plus the matching markdown-
            // fallback shapes. Adding them surfaces ~30k `kind=unknown`
            // rows on the next reindex with a meaningful kind, and lets
            // the canonical-prepend filter (#630) and HEURISTIC 1.6 (#616)
            // tiebreak on the right signal for member pages.
            case enumCase = "case" // enum case (Apple roleHeading "Case")
            case initializer
            case `subscript`
            case actor
            case sampleCode = "sample code"
            case unknown
        }

        /// The source of the documentation
        public enum Source: String, Codable, Sendable {
            case appleJSON // Apple's JSON API
            case appleWebKit // WKWebView rendered HTML
            case swiftOrg // Swift.org documentation
            case github // GitHub README/docs
            case custom // Other sources
        }

        /// A code declaration with optional language
        public struct Declaration: Codable, Sendable, Hashable {
            public let code: String
            public let language: String?

            public init(code: String, language: String? = "swift") {
                self.code = code
                self.language = language
            }
        }

        /// A documentation section with title and content
        public struct Section: Codable, Sendable, Hashable {
            public let title: String
            public let content: String
            public let items: [Item]?

            public init(title: String, content: String = "", items: [Item]? = nil) {
                self.title = title
                self.content = content
                self.items = items
            }

            /// An item within a section (e.g., a method in "Instance Methods")
            public struct Item: Codable, Sendable, Hashable {
                public let name: String
                public let description: String?
                public let url: URL?

                public init(name: String, description: String? = nil, url: URL? = nil) {
                    self.name = name
                    self.description = description
                    self.url = url
                }
            }
        }

        /// A code example with optional syntax highlighting
        public struct CodeExample: Codable, Sendable, Hashable {
            public let code: String
            public let language: String?
            public let caption: String?

            public init(code: String, language: String? = "swift", caption: String? = nil) {
                self.code = code
                self.language = language
                self.caption = caption
            }
        }

        // MARK: - Computed Properties

        /// Generate markdown representation of this page
        public var markdown: String {
            var result = "---\n"
            result += "source: \(url.absoluteString)\n"
            result += "crawled: \(ISO8601DateFormatter().string(from: crawledAt))\n"
            result += "kind: \(kind.rawValue)\n"
            result += "---\n\n"

            result += "# \(title)\n\n"

            if kind != .article, kind != .tutorial, kind != .collection {
                result += "**\(kind.rawValue.capitalized)**\n\n"
            }

            if let abstract, !abstract.isEmpty {
                result += "\(abstract)\n\n"
            }

            if let declaration {
                result += "## Declaration\n\n"
                result += "```\(declaration.language ?? "")\n"
                result += "\(declaration.code)\n"
                result += "```\n\n"
            }

            if let overview, !overview.isEmpty {
                result += "## Overview\n\n"
                result += "\(overview)\n\n"
            }

            for example in codeExamples {
                if let caption = example.caption {
                    result += "\(caption)\n\n"
                }
                result += "```\(example.language ?? "")\n"
                result += "\(example.code)\n"
                result += "```\n\n"
            }

            for section in sections {
                result += "## \(section.title)\n\n"
                if !section.content.isEmpty {
                    result += "\(section.content)\n\n"
                }
                if let items = section.items {
                    for item in items {
                        result += "- **\(item.name)**"
                        if let desc = item.description {
                            result += ": \(desc)"
                        }
                        result += "\n"
                    }
                    result += "\n"
                }
            }

            if let conforms = conformsTo, !conforms.isEmpty {
                result += "## Conforms To\n\n"
                for proto in conforms {
                    result += "- \(proto)\n"
                }
                result += "\n"
            }

            if let inheritedBy, !inheritedBy.isEmpty {
                result += "## Inherited By\n\n"
                for type in inheritedBy {
                    result += "- \(type)\n"
                }
                result += "\n"
            }

            if let conforming = conformingTypes, !conforming.isEmpty {
                result += "## Conforming Types\n\n"
                for type in conforming {
                    result += "- \(type)\n"
                }
                result += "\n"
            }

            return result
        }

        // MARK: - Declaration Parsing Helpers

        /// Extracts @attributes from a declaration string
        /// Returns array of attributes like ["@MainActor", "@Sendable", "@available(iOS 15.0, *)"]
        public var extractedAttributes: [String] {
            guard let decl = declaration?.code else { return [] }

            var attributes: [String] = []
            var index = decl.startIndex

            while index < decl.endIndex {
                // Skip whitespace and newlines
                while index < decl.endIndex, decl[index].isWhitespace || decl[index].isNewline {
                    index = decl.index(after: index)
                }

                guard index < decl.endIndex, decl[index] == "@" else { break }

                // Found an attribute, extract it
                let attrStart = index
                index = decl.index(after: index)

                // Read attribute name
                while index < decl.endIndex, decl[index].isLetter || decl[index].isNumber || decl[index] == "_" {
                    index = decl.index(after: index)
                }

                // Handle parenthesized arguments like @available(iOS 15.0, *)
                if index < decl.endIndex, decl[index] == "(" {
                    var parenDepth = 1
                    index = decl.index(after: index)
                    while index < decl.endIndex, parenDepth > 0 {
                        if decl[index] == "(" { parenDepth += 1 } else if decl[index] == ")" { parenDepth -= 1 }
                        index = decl.index(after: index)
                    }
                }

                let attr = String(decl[attrStart..<index])
                if !attr.isEmpty {
                    attributes.append(attr)
                }
            }

            return attributes
        }

        /// Returns the declaration with @attributes stripped and collapsed to single line
        /// Used for kind inference pattern matching
        public var normalizedDeclaration: String? {
            guard let decl = declaration?.code.trimmingCharacters(in: .whitespacesAndNewlines),
                  !decl.isEmpty else {
                return nil
            }

            // Collapse multi-line to single line
            var normalized = decl
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")

            // Strip leading @attributes
            while true {
                normalized = normalized.trimmingCharacters(in: .whitespaces)
                guard normalized.hasPrefix("@") else { break }

                // Find end of attribute (including parenthesized args)
                var index = normalized.index(after: normalized.startIndex)

                // Skip attribute name
                while index < normalized.endIndex,
                      normalized[index].isLetter || normalized[index].isNumber || normalized[index] == "_" {
                    index = normalized.index(after: index)
                }

                // Skip parenthesized arguments
                if index < normalized.endIndex, normalized[index] == "(" {
                    var parenDepth = 1
                    index = normalized.index(after: index)
                    while index < normalized.endIndex, parenDepth > 0 {
                        if normalized[index] == "(" { parenDepth += 1 } else if normalized[index] == ")" { parenDepth -= 1 }
                        index = normalized.index(after: index)
                    }
                }

                normalized = String(normalized[index...])
            }

            // Collapse multiple spaces to single space
            while normalized.contains("  ") {
                normalized = normalized.replacingOccurrences(of: "  ", with: " ")
            }

            return normalized.trimmingCharacters(in: .whitespaces)
        }

        // MARK: - Heuristic Kind Inference

        /// Infers the correct kind from declaration code when Apple's API returns "unknown"
        /// This heuristic improves search ranking by correctly classifying docs marked as "unknown"
        public var inferredKind: Kind {
            // Stage 1: Trust Apple's kind if not unknown
            guard kind == .unknown else { return kind }

            // Stage 2: No declaration = article (guides, tutorials, conceptual docs)
            guard let decl = normalizedDeclaration, !decl.isEmpty else {
                return .article
            }

            // Stage 3: Pattern matching on normalized declaration
            // Order matters: check most specific patterns first

            // Macros (Swift 5.9+) - check before stripping @ since these ARE the declaration
            if let rawDecl = declaration?.code,
               rawDecl.contains("@freestanding") || rawDecl.contains("@attached") {
                return .macro
            }

            // Type declarations (handle modifiers like public, final, open, etc.)
            if decl.hasPrefix("protocol ") || decl.contains(" protocol ") { return .protocol }
            if decl.hasPrefix("struct ") || decl.contains(" struct ") { return .struct }
            if decl.hasPrefix("class ") || decl.contains(" class ") { return .class }
            if decl.hasPrefix("enum ") || decl.contains(" enum ") { return .enum }
            if decl.hasPrefix("actor ") || decl.contains(" actor ") { return .class } // actors are class-like

            // Enum cases (often appear as separate docs)
            if decl.hasPrefix("case ") || decl.contains(" case ") { return .enum }

            // Associated types (protocol requirements)
            if decl.hasPrefix("associatedtype ") || decl.contains(" associatedtype ") { return .typeAlias }

            // Properties (var/let) - including static
            if decl.hasPrefix("var ") || decl.hasPrefix("let ") { return .property }
            if decl.hasPrefix("static var ") || decl.hasPrefix("static let ") { return .property }
            if decl.hasPrefix("class var ") || decl.hasPrefix("class let ") { return .property }
            if decl.contains(" var ") || decl.contains(" let ") { return .property }

            // Subscripts
            if decl.hasPrefix("subscript") || decl.contains(" subscript") { return .method }

            // Methods and initializers
            if decl.hasPrefix("func ") || decl.contains(" func ") { return .method }
            // Initializers: init(, init?(, init!(, init<T>
            if decl.hasPrefix("init(") || decl.hasPrefix("init?")
                || decl.hasPrefix("init!") || decl.hasPrefix("init<") { return .method }
            if decl.contains(" init(") || decl.contains(" init?")
                || decl.contains(" init!") || decl.contains(" init<") { return .method }
            if decl.hasPrefix("deinit") { return .method }
            if decl.hasPrefix("static func ") || decl.hasPrefix("class func ") { return .method }

            // REST API types (OpenAPI object declarations)
            if decl.hasPrefix("object ") { return .struct }

            // Type aliases (can have public/internal modifiers)
            if decl.hasPrefix("typealias ") || decl.contains(" typealias ") { return .typeAlias }

            // Operators
            if decl.hasPrefix("operator ") || decl.contains(" operator ") { return .operator }
            if decl.hasPrefix("prefix ") || decl.contains(" prefix ") { return .operator }
            if decl.hasPrefix("postfix ") || decl.contains(" postfix ") { return .operator }
            if decl.hasPrefix("infix ") || decl.contains(" infix ") { return .operator }

            // Still unknown after all heuristics
            return .unknown
        }

        // MARK: - Deterministic Identity & Content Hashing

        /// Derive a stable UUID from the page URL.
        /// Same URL → same UUID across runs and machines. Use this anywhere a
        /// `StructuredDocumentationPage` is constructed so persisted records are
        /// reproducible.
        public static func deterministicID(for url: URL) -> UUID {
            let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            let bytes = Array(digest.prefix(16))
            let hex = bytes.map { String(format: "%02x", $0) }.joined()
            var formatted = hex
            formatted.insert("-", at: formatted.index(formatted.startIndex, offsetBy: 8))
            formatted.insert("-", at: formatted.index(formatted.startIndex, offsetBy: 13))
            formatted.insert("-", at: formatted.index(formatted.startIndex, offsetBy: 18))
            formatted.insert("-", at: formatted.index(formatted.startIndex, offsetBy: 23))
            return UUID(uuidString: formatted) ?? UUID()
        }

        /// SHA-256 over the page's semantic content fields, in a stable encoding.
        /// Excludes `id`, `crawledAt`, `contentHash`, and `rawMarkdown` (the last
        /// is derived from the structured fields and embeds `crawledAt`).
        /// Two crawls of the same Apple-side content produce the same hash.
        public var canonicalContentHash: String {
            let payload = CanonicalPayload(
                url: url,
                title: title,
                kind: kind,
                source: source,
                abstract: abstract,
                declaration: declaration,
                overview: overview,
                sections: sections,
                codeExamples: codeExamples,
                language: language,
                platforms: platforms,
                module: module,
                conformsTo: conformsTo,
                inheritedBy: inheritedBy,
                conformingTypes: conformingTypes
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(payload) else { return "" }
            return HashUtilities.sha256(of: data)
        }

        private struct CanonicalPayload: Encodable {
            let url: URL
            let title: String
            let kind: Kind
            let source: Source
            let abstract: String?
            let declaration: Declaration?
            let overview: String?
            let sections: [Section]
            let codeExamples: [CodeExample]
            let language: String?
            let platforms: [String]?
            let module: String?
            let conformsTo: [String]?
            let inheritedBy: [String]?
            let conformingTypes: [String]?
        }

        /// Return a copy with `contentHash` replaced. Use after constructing a
        /// page with `contentHash: ""` to stamp `canonicalContentHash` in one step.
        public func with(contentHash newHash: String) -> StructuredDocumentationPage {
            StructuredDocumentationPage(
                id: id,
                url: url,
                title: title,
                kind: kind,
                source: source,
                abstract: abstract,
                declaration: declaration,
                overview: overview,
                sections: sections,
                codeExamples: codeExamples,
                language: language,
                platforms: platforms,
                module: module,
                conformsTo: conformsTo,
                inheritedBy: inheritedBy,
                conformingTypes: conformingTypes,
                rawMarkdown: rawMarkdown,
                crawledAt: crawledAt,
                contentHash: newHash,
                crawlDepth: crawlDepth
            )
        }
    }
}

// MARK: - Documentation Page (Crawl Metadata)

/// Represents a single documentation page
extension Shared.Models {
    public struct DocumentationPage: Codable, Sendable, Identifiable {
        public let id: UUID
        public let url: URL
        public let framework: String
        public let title: String
        public let filePath: URL
        public let contentHash: String
        public let depth: Int
        public let lastCrawled: Date

        public init(
            id: UUID = UUID(),
            url: URL,
            framework: String,
            title: String,
            filePath: URL,
            contentHash: String,
            depth: Int,
            lastCrawled: Date = Date()
        ) {
            self.id = id
            self.url = url
            self.framework = framework
            self.title = title
            self.filePath = filePath
            self.contentHash = contentHash
            self.depth = depth
            self.lastCrawled = lastCrawled
        }
    }
}
