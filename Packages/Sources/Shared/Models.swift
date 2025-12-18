import CryptoKit
import Foundation

// MARK: - Structured Documentation Page

/// Represents a fully structured documentation page with rich content
/// This model is designed to be populated from both Apple JSON API and HTML sources
/// and is suitable for database storage and querying
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

    // Raw markdown from original source (HTML conversion)
    public let rawMarkdown: String?

    // Crawl metadata
    public let crawledAt: Date
    public let contentHash: String

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
        contentHash: String = ""
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
    }

    // MARK: - Codable

    /// Custom decoder to handle missing "id" field in old JSON files
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID if id is missing (for backwards compatibility)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try container.decode(URL.self, forKey: .url)
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, title, kind, source
        case abstract, declaration, overview, sections, codeExamples
        case language, platforms, module
        case conformsTo, inheritedBy, conformingTypes
        case rawMarkdown, crawledAt, contentHash
    }

    // MARK: - Nested Types

    /// The kind/type of documentation page
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
        if decl.hasPrefix("init(") || decl.hasPrefix("init?") || decl.hasPrefix("init!") || decl.hasPrefix("init<") { return .method }
        if decl.contains(" init(") || decl.contains(" init?") || decl.contains(" init!") || decl.contains(" init<") { return .method }
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
}

// MARK: - Documentation Page (Crawl Metadata)

/// Represents a single documentation page
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

// MARK: - Crawl Metadata

/// Metadata tracking crawl state and statistics
public struct CrawlMetadata: Codable, Sendable {
    public var pages: [String: PageMetadata] // URL -> metadata
    public var frameworks: [String: FrameworkStats] // framework name -> stats
    public var lastCrawl: Date?
    public var stats: CrawlStatistics
    public var crawlState: CrawlSessionState? // Resume state

    public init(
        pages: [String: PageMetadata] = [:],
        frameworks: [String: FrameworkStats] = [:],
        lastCrawl: Date? = nil,
        stats: CrawlStatistics = CrawlStatistics(),
        crawlState: CrawlSessionState? = nil
    ) {
        self.pages = pages
        self.frameworks = frameworks
        self.lastCrawl = lastCrawl
        self.stats = stats
        self.crawlState = crawlState
    }

    /// Save metadata to file
    public func save(to url: URL) throws {
        try JSONCoding.encode(self, to: url)
    }

    /// Load metadata from file
    public static func load(from url: URL) throws -> CrawlMetadata {
        try JSONCoding.decode(CrawlMetadata.self, from: url)
    }

    /// Get statistics grouped by framework
    public func statsByFramework() -> [String: FrameworkStats] {
        // If frameworks dict is populated, return it
        if !frameworks.isEmpty {
            return frameworks
        }

        // Otherwise compute from pages
        var stats: [String: FrameworkStats] = [:]
        for (_, page) in pages {
            let framework = page.framework.lowercased()
            if var existing = stats[framework] {
                existing.pageCount += 1
                existing.lastCrawled = max(existing.lastCrawled ?? .distantPast, page.lastCrawled)
                stats[framework] = existing
            } else {
                stats[framework] = FrameworkStats(
                    name: page.framework,
                    pageCount: 1,
                    lastCrawled: page.lastCrawled
                )
            }
        }
        return stats
    }

    // MARK: - Codable

    /// Custom decoder to handle missing fields in old metadata files
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode with defaults for missing fields
        pages = try container.decodeIfPresent([String: PageMetadata].self, forKey: .pages) ?? [:]
        frameworks = try container.decodeIfPresent([String: FrameworkStats].self, forKey: .frameworks) ?? [:]
        lastCrawl = try container.decodeIfPresent(Date.self, forKey: .lastCrawl)
        stats = try container.decodeIfPresent(CrawlStatistics.self, forKey: .stats) ?? CrawlStatistics()
        crawlState = try container.decodeIfPresent(CrawlSessionState.self, forKey: .crawlState)
    }

    private enum CodingKeys: String, CodingKey {
        case pages, frameworks, lastCrawl, stats, crawlState
    }
}

// MARK: - Framework Stats

/// Statistics for a single framework
public struct FrameworkStats: Codable, Sendable {
    public var name: String
    public var pageCount: Int
    public var newPages: Int
    public var updatedPages: Int
    public var errors: Int
    public var lastCrawled: Date?
    public var crawlStatus: CrawlStatus

    public enum CrawlStatus: String, Codable, Sendable {
        case notStarted = "not_started"
        case inProgress = "in_progress"
        case complete
        case partial
        case failed
    }

    public init(
        name: String,
        pageCount: Int = 0,
        newPages: Int = 0,
        updatedPages: Int = 0,
        errors: Int = 0,
        lastCrawled: Date? = nil,
        crawlStatus: CrawlStatus = .notStarted
    ) {
        self.name = name
        self.pageCount = pageCount
        self.newPages = newPages
        self.updatedPages = updatedPages
        self.errors = errors
        self.lastCrawled = lastCrawled
        self.crawlStatus = crawlStatus
    }

    // MARK: - Codable

    /// Custom decoder to handle missing fields in old metadata files
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Provide defaults for missing fields
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 0
        newPages = try container.decodeIfPresent(Int.self, forKey: .newPages) ?? 0
        updatedPages = try container.decodeIfPresent(Int.self, forKey: .updatedPages) ?? 0
        errors = try container.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        lastCrawled = try container.decodeIfPresent(Date.self, forKey: .lastCrawled)
        crawlStatus = try container.decodeIfPresent(CrawlStatus.self, forKey: .crawlStatus) ?? .notStarted
    }

    private enum CodingKeys: String, CodingKey {
        case name, pageCount, newPages, updatedPages, errors, lastCrawled, crawlStatus
    }
}

// MARK: - Page Metadata

/// Metadata for a single crawled page
public struct PageMetadata: Codable, Sendable {
    public let url: String
    public let framework: String
    public let filePath: String
    public let contentHash: String
    public let depth: Int
    public let lastCrawled: Date

    public init(
        url: String,
        framework: String,
        filePath: String,
        contentHash: String,
        depth: Int,
        lastCrawled: Date = Date()
    ) {
        self.url = url
        self.framework = framework
        self.filePath = filePath
        self.contentHash = contentHash
        self.depth = depth
        self.lastCrawled = lastCrawled
    }

    // MARK: - Codable

    /// Custom decoder to handle missing fields in old metadata files
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Provide defaults for missing fields
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        framework = try container.decodeIfPresent(String.self, forKey: .framework) ?? "unknown"
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath) ?? ""
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash) ?? ""
        depth = try container.decodeIfPresent(Int.self, forKey: .depth) ?? 0
        lastCrawled = try container.decodeIfPresent(Date.self, forKey: .lastCrawled) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case url, framework, filePath, contentHash, depth, lastCrawled
    }
}

// MARK: - Crawl Statistics

/// Statistics for a crawl session
public struct CrawlStatistics: Codable, Sendable {
    public var totalPages: Int
    public var newPages: Int
    public var updatedPages: Int
    public var skippedPages: Int
    public var errors: Int
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalPages: Int = 0,
        newPages: Int = 0,
        updatedPages: Int = 0,
        skippedPages: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalPages = totalPages
        self.newPages = newPages
        self.updatedPages = updatedPages
        self.skippedPages = skippedPages
        self.errors = errors
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Duration of the crawl in seconds
    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else {
            return nil
        }
        return end.timeIntervalSince(start)
    }

    // MARK: - Codable

    /// Custom decoder to handle missing fields in old metadata files
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Provide defaults for missing fields
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages) ?? 0
        newPages = try container.decodeIfPresent(Int.self, forKey: .newPages) ?? 0
        updatedPages = try container.decodeIfPresent(Int.self, forKey: .updatedPages) ?? 0
        skippedPages = try container.decodeIfPresent(Int.self, forKey: .skippedPages) ?? 0
        errors = try container.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
    }

    private enum CodingKeys: String, CodingKey {
        case totalPages, newPages, updatedPages, skippedPages, errors, startTime, endTime
    }
}

// MARK: - Hash Utilities

/// Utilities for content hashing
public enum HashUtilities {
    /// Compute SHA-256 hash of a string
    public static func sha256(of string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Compute SHA-256 hash of data
    public static func sha256(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - URL Utilities

/// Utilities for URL manipulation
public enum URLUtilities {
    /// Normalize a URL (remove hash, query params)
    public static func normalize(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.query = nil
        return components?.url
    }

    /// Extract framework name from documentation URL (Apple or Swift.org)
    public static func extractFramework(from url: URL) -> String {
        let pathComponents = url.pathComponents

        // Handle docs.swift.org URLs (e.g., /swift-book/documentation/the-swift-programming-language/*)
        if url.host?.contains(Shared.Constants.HostDomain.swiftOrg) == true {
            if pathComponents.contains(Shared.Constants.PathComponent.swiftBook) {
                return Shared.Constants.PathComponent.swiftBook
            }
            return Shared.Constants.PathComponent.swiftOrgFramework
        }

        // Handle developer.apple.com URLs (e.g., /documentation/swiftui/*)
        if let docIndex = pathComponents.firstIndex(of: "documentation"),
           docIndex + 1 < pathComponents.count {
            return pathComponents[docIndex + 1].lowercased()
        }

        return "root"
    }

    /// Generate filename from URL
    public static func filename(from url: URL) -> String {
        var cleaned = url.absoluteString
        let originalCleaned = cleaned

        // Remove known domain prefixes
        cleaned = cleaned
            .replacingOccurrences(of: "\(Shared.Constants.BaseURL.appleDeveloper)/", with: "")
            .replacingOccurrences(of: "\(Shared.Constants.BaseURL.swiftOrg)", with: "")
            .replacingOccurrences(of: Shared.Constants.URLCleanupPattern.swiftOrgWWW, with: "")

        // Check if URL contains special characters that would cause collisions
        // (operators, subscripts, etc.)
        let hasSpecialChars = cleaned.rangeOfCharacter(from: CharacterSet(charactersIn: "()[]<>:,")) != nil

        // Normalize to safe filename
        cleaned = cleaned
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "^_+|_+$", with: "", options: .regularExpression)

        // If special characters were present, append a hash to ensure uniqueness
        // This prevents collisions like:
        //   - .../Text → documentation_swiftui_text
        //   - .../Text/+(_:_:) → documentation_swiftui_text (collision!)
        // With hash:
        //   - .../Text → documentation_swiftui_text
        //   - .../Text/+(_:_:) → documentation_swiftui_text_a1b2c3d4
        if hasSpecialChars {
            let hash = HashUtilities.sha256(of: originalCleaned)
            let shortHash = String(hash.prefix(8))
            cleaned = "\(cleaned)_\(shortHash)"
        }

        return cleaned.isEmpty ? "index" : cleaned
    }
}

// MARK: - Crawl Session State

/// Represents the complete state of a crawl session for resuming
public struct CrawlSessionState: Codable, Sendable {
    public var visited: Set<String> // Visited URL strings
    public var queue: [QueuedURL] // Pending URLs to crawl
    public var startURL: String
    public var outputDirectory: String // Where files are being saved
    public var sessionStartTime: Date
    public var lastSaveTime: Date
    public var isActive: Bool

    public init(
        visited: Set<String> = [],
        queue: [QueuedURL] = [],
        startURL: String,
        outputDirectory: String,
        sessionStartTime: Date = Date(),
        lastSaveTime: Date = Date(),
        isActive: Bool = true
    ) {
        self.visited = visited
        self.queue = queue
        self.startURL = startURL
        self.outputDirectory = outputDirectory
        self.sessionStartTime = sessionStartTime
        self.lastSaveTime = lastSaveTime
        self.isActive = isActive
    }
}

/// Represents a URL in the crawl queue with depth information
public struct QueuedURL: Codable, Sendable, Hashable {
    public let url: String
    public let depth: Int

    public init(url: String, depth: Int) {
        self.url = url
        self.depth = depth
    }
}

// MARK: - Package Documentation Models

/// Reference to a Swift package for documentation download
public struct PackageReference: Codable, Sendable, Hashable {
    public let owner: String
    public let repo: String
    public let url: String
    public let priority: PackagePriority

    public init(owner: String, repo: String, url: String, priority: PackagePriority) {
        self.owner = owner
        self.repo = repo
        self.url = url
        self.priority = priority
    }
}

/// Priority level for package documentation
public enum PackagePriority: String, Codable, Sendable {
    case appleOfficial
    case ecosystem
    case community
}

/// Detected documentation site for a package
public struct DocumentationSite: Codable, Sendable, Hashable {
    public let type: DocumentationType
    public let baseURL: URL

    public init(type: DocumentationType, baseURL: URL) {
        self.type = type
        self.baseURL = baseURL
    }

    /// Type of documentation site
    public enum DocumentationType: String, Codable, Sendable {
        case githubPages
        case customDomain
        case githubWiki
        case readmeOnly
    }
}

/// Progress information for package documentation downloads
public struct PackageDownloadProgress: Sendable {
    public let currentPackage: String
    public let completed: Int
    public let total: Int
    public let status: String

    public init(currentPackage: String, completed: Int, total: Int, status: String) {
        self.currentPackage = currentPackage
        self.completed = completed
        self.total = total
        self.status = status
    }

    /// Progress percentage (0-100)
    public var percentage: Double {
        guard total > 0 else { return 0 }
        return (Double(completed) / Double(total)) * 100.0
    }
}

/// Statistics for package documentation downloads
public struct PackageDownloadStatistics: Sendable {
    public var totalPackages: Int
    public var newREADMEs: Int
    public var updatedREADMEs: Int
    public var successfulDocs: Int
    public var errors: Int
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalPackages: Int = 0,
        newREADMEs: Int = 0,
        updatedREADMEs: Int = 0,
        successfulDocs: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalPackages = totalPackages
        self.newREADMEs = newREADMEs
        self.updatedREADMEs = updatedREADMEs
        self.successfulDocs = successfulDocs
        self.errors = errors
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Total successful READMEs (new + updated)
    public var successfulREADMEs: Int {
        newREADMEs + updatedREADMEs
    }

    /// Duration of the download in seconds
    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else {
            return nil
        }
        return end.timeIntervalSince(start)
    }
}

// MARK: - Sample Code Cleanup Models

/// Progress update for sample code cleanup
public struct CleanupProgress: Sendable {
    public let current: Int
    public let total: Int
    public let currentFile: String
    public let originalSize: Int64
    public let cleanedSize: Int64

    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total) * 100.0
    }

    public init(
        current: Int,
        total: Int,
        currentFile: String,
        originalSize: Int64,
        cleanedSize: Int64
    ) {
        self.current = current
        self.total = total
        self.currentFile = currentFile
        self.originalSize = originalSize
        self.cleanedSize = cleanedSize
    }
}

/// Statistics from sample code cleanup operation
public struct CleanupStatistics: Sendable {
    public let totalArchives: Int
    public let cleanedArchives: Int
    public let skippedArchives: Int
    public let errors: Int
    public let originalTotalSize: Int64
    public let cleanedTotalSize: Int64
    public let totalItemsRemoved: Int
    public var duration: TimeInterval?

    public var spaceSaved: Int64 {
        originalTotalSize - cleanedTotalSize
    }

    public var spaceSavedPercentage: Double {
        guard originalTotalSize > 0 else { return 0 }
        return Double(spaceSaved) / Double(originalTotalSize) * 100.0
    }

    public init(
        totalArchives: Int,
        cleanedArchives: Int,
        skippedArchives: Int,
        errors: Int,
        originalTotalSize: Int64,
        cleanedTotalSize: Int64,
        totalItemsRemoved: Int = 0,
        duration: TimeInterval? = nil
    ) {
        self.totalArchives = totalArchives
        self.cleanedArchives = cleanedArchives
        self.skippedArchives = skippedArchives
        self.errors = errors
        self.originalTotalSize = originalTotalSize
        self.cleanedTotalSize = cleanedTotalSize
        self.totalItemsRemoved = totalItemsRemoved
        self.duration = duration
    }
}

/// Result of cleaning a single archive
public struct CleanupResult: Sendable {
    public let filename: String
    public let originalSize: Int64
    public let cleanedSize: Int64
    public let itemsRemoved: Int
    public let success: Bool
    public let errorMessage: String?

    public init(
        filename: String,
        originalSize: Int64,
        cleanedSize: Int64,
        itemsRemoved: Int,
        success: Bool,
        errorMessage: String? = nil
    ) {
        self.filename = filename
        self.originalSize = originalSize
        self.cleanedSize = cleanedSize
        self.itemsRemoved = itemsRemoved
        self.success = success
        self.errorMessage = errorMessage
    }
}
