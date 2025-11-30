import Foundation
import Shared

/// Converts Apple documentation markdown files to StructuredDocumentationPage
public enum MarkdownToStructuredPage {
    // MARK: - Public API

    /// Convert markdown content to a StructuredDocumentationPage
    /// - Parameters:
    ///   - markdown: The markdown content
    ///   - url: Optional URL (extracted from frontmatter if not provided)
    /// - Returns: A StructuredDocumentationPage if extraction succeeds
    public static func convert(_ markdown: String, url: URL? = nil) -> StructuredDocumentationPage? {
        // Parse frontmatter
        let (frontmatter, content) = parseFrontmatter(markdown)

        // Get URL from parameter or frontmatter
        let pageURL: URL
        if let url {
            pageURL = url
        } else if let sourceString = frontmatter["source"],
                  let parsedURL = URL(string: sourceString) {
            pageURL = parsedURL
        } else {
            return nil
        }

        // Extract title
        guard let title = extractTitle(from: content) else {
            return nil
        }

        // Extract kind
        let kind = extractKind(from: content)

        // Extract declaration (first code block after title)
        let declaration = extractDeclaration(from: content)

        // Extract abstract (text between kind line and declaration)
        let abstract = extractAbstract(from: content)

        // Extract overview
        let overview = extractOverview(from: content)

        // Extract code examples from overview
        let codeExamples = extractCodeExamples(from: content)

        // Extract sections (Topics)
        let sections = extractSections(from: content)

        // Extract platforms as strings
        let platforms = extractPlatforms(from: content)

        // Extract module from URL path
        let module = extractModule(from: pageURL)

        // Extract conformance
        let conformsTo = extractConformsTo(from: content)

        // Compute content hash
        let contentHash = HashUtilities.sha256(of: markdown)

        // Get crawled date from frontmatter
        let crawledAt: Date
        if let crawledString = frontmatter["crawled"],
           let date = ISO8601DateFormatter().date(from: crawledString) {
            crawledAt = date
        } else {
            crawledAt = Date()
        }

        return StructuredDocumentationPage(
            url: pageURL,
            title: title,
            kind: kind,
            source: .appleWebKit, // Markdown files are from WebKit crawler
            abstract: abstract,
            declaration: declaration,
            overview: overview,
            sections: sections,
            codeExamples: codeExamples,
            platforms: platforms,
            module: module,
            conformsTo: conformsTo,
            rawMarkdown: markdown,
            crawledAt: crawledAt,
            contentHash: contentHash
        )
    }

    // MARK: - Frontmatter Parsing

    private static func parseFrontmatter(_ markdown: String) -> ([String: String], String) {
        var frontmatter: [String: String] = [:]
        var content = markdown

        // Check for YAML frontmatter
        if markdown.hasPrefix("---\n") {
            let parts = markdown.dropFirst(4).split(separator: "---", maxSplits: 1)
            if parts.count == 2 {
                let yamlContent = String(parts[0])
                content = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Parse YAML (simple key: value format)
                for line in yamlContent.split(separator: "\n") {
                    let keyValue = line.split(separator: ":", maxSplits: 1)
                    if keyValue.count == 2 {
                        let key = String(keyValue[0]).trimmingCharacters(in: .whitespaces)
                        let value = String(keyValue[1]).trimmingCharacters(in: .whitespaces)
                        frontmatter[key] = value
                    }
                }
            }
        }

        return (frontmatter, content)
    }

    // MARK: - Title Extraction

    private static func extractTitle(from content: String) -> String? {
        // Find first # header
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                var title = String(trimmed.dropFirst(2))
                // Remove " | Apple Developer Documentation" suffix
                if let range = title.range(of: " | Apple Developer Documentation") {
                    title = String(title[..<range.lowerBound])
                }
                return title.trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }

    // MARK: - Kind Extraction

    private static func extractKind(from content: String) -> StructuredDocumentationPage.Kind {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        // Look for pattern: "Kind# Title" on a single line
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("# "), !trimmed.hasPrefix("#") {
                // Extract the kind before "# "
                if let hashIndex = trimmed.firstIndex(of: "#") {
                    let kindString = String(trimmed[..<hashIndex]).lowercased()
                    return parseKind(kindString)
                }
            }
        }

        return .unknown
    }

    private static func parseKind(_ kindString: String) -> StructuredDocumentationPage.Kind {
        let kind = kindString.lowercased().trimmingCharacters(in: .whitespaces)

        switch kind {
        case "protocol": return .protocol
        case "class": return .class
        case "structure", "struct": return .struct
        case "enumeration", "enum": return .enum
        case "function", "func": return .function
        case "property", "instance property", "type property": return .property
        case "method", "instance method", "type method": return .method
        case "operator": return .operator
        case "type alias", "typealias": return .typeAlias
        case "macro": return .macro
        case "module", "framework": return .framework
        case "article": return .article
        case "tutorial": return .tutorial
        case "collection", "api collection": return .collection
        default: return .unknown
        }
    }

    // MARK: - Declaration Extraction

    private static func extractDeclaration(from content: String) -> StructuredDocumentationPage.Declaration? {
        // Find first fenced code block after title
        let pattern = #"```(?:swift)?\n([\s\S]*?)```"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let codeRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        let code = String(content[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it looks like a declaration (not an example)
        if code.contains("struct ") || code.contains("class ") ||
            code.contains("func ") || code.contains("var ") ||
            code.contains("let ") || code.contains("enum ") ||
            code.contains("protocol ") || code.contains("init(") ||
            code.contains("typealias ") || code.hasPrefix("@") ||
            code.hasPrefix("nonisolated") {
            return StructuredDocumentationPage.Declaration(code: code, language: "swift")
        }

        // Return first code block anyway as declaration
        return StructuredDocumentationPage.Declaration(code: code, language: "swift")
    }

    // MARK: - Abstract Extraction

    private static func extractAbstract(from content: String) -> String? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var foundKindLine = false
        var abstract = ""

        // Known kinds that appear before "# Title"
        let knownKinds = Set([
            "structure", "struct", "class", "protocol", "enumeration", "enum",
            "function", "func", "property", "instance property", "type property",
            "method", "instance method", "type method", "operator", "type alias",
            "typealias", "macro", "module", "framework", "article", "tutorial",
            "collection", "api collection", "sample code", "initializer", "case",
        ])

        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)

            // Look for "Kind# Title" line
            if !trimmed.hasPrefix("#"), let hashRange = trimmed.range(of: "# ") {
                let beforeHash = String(trimmed[..<hashRange.lowerBound]).lowercased()
                // Check if text before # is a known kind
                if knownKinds.contains(beforeHash) {
                    foundKindLine = true
                    continue
                }
            }

            if foundKindLine {
                // Stop at code block
                if trimmed.hasPrefix("```") {
                    break
                }

                // WebKit concatenates abstract with ## [Topics] on same line
                // Split off the section header if present
                if let sectionRange = trimmed.range(of: "## [") {
                    trimmed = String(trimmed[..<sectionRange.lowerBound])
                } else if let sectionRange = trimmed.range(of: "## "), !trimmed.hasPrefix("## ") {
                    trimmed = String(trimmed[..<sectionRange.lowerBound])
                }

                // Stop at standalone section header
                if trimmed.hasPrefix("## ") {
                    break
                }

                // Skip empty lines at the start
                if abstract.isEmpty && trimmed.isEmpty {
                    continue
                }

                // Skip breadcrumb-like lines
                if trimmed.hasPrefix("- [") || trimmed.hasPrefix("-  ") {
                    continue
                }

                // Collect non-empty content
                if !trimmed.isEmpty {
                    // Remove platform info suffix (iOS 17.0+iPadOS...)
                    let cleaned = removePlatformSuffix(trimmed)
                    if !cleaned.isEmpty {
                        abstract += (abstract.isEmpty ? "" : " ") + cleaned
                    }
                }
            }
        }

        return abstract.isEmpty ? nil : abstract.trimmingCharacters(in: .whitespaces)
    }

    private static func removePlatformSuffix(_ text: String) -> String {
        // Remove platform version strings like "iOS 17.0+iPadOS 17.0+..."
        // swiftlint:disable:next line_length
        let platformPattern = #"(?:iOS|iPadOS|macOS|tvOS|watchOS|visionOS|Mac Catalyst)\s*\d+\.\d+(?:\+|–[^+]+\+?)?(?:Deprecated)?"#

        guard let regex = try? NSRegularExpression(pattern: platformPattern, options: []) else {
            return text
        }

        var result = text
        let range = NSRange(result.startIndex..., in: result)
        result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")

        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Overview Extraction

    private static func extractOverview(from content: String) -> String? {
        // Find content between ## [Overview] and next ## section
        guard let overviewStart = content.range(of: "## [Overview]") ??
            content.range(of: "## Overview") else {
            // Try ## [Discussion] as alternative
            guard let discussionStart = content.range(of: "## [Discussion]") ??
                content.range(of: "## Discussion") else {
                return nil
            }
            return extractSectionContent(from: content, startingAfter: discussionStart.upperBound)
        }

        return extractSectionContent(from: content, startingAfter: overviewStart.upperBound)
    }

    private static func extractSectionContent(from content: String, startingAfter start: String.Index) -> String? {
        let remaining = String(content[start...])
        let lines = remaining.split(separator: "\n", omittingEmptySubsequences: false)
        var result = ""

        for line in lines.dropFirst() { // Skip the header line
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop at next ## section
            if trimmed.hasPrefix("## ") {
                break
            }

            result += String(line) + "\n"
        }

        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Code Examples Extraction

    private static func extractCodeExamples(from content: String) -> [StructuredDocumentationPage.CodeExample] {
        var examples: [StructuredDocumentationPage.CodeExample] = []

        // Extract ALL code blocks from the document
        let pattern = #"```(?:swift)?\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return examples
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        // Skip the first code block if it looks like a declaration
        var isFirst = true
        for match in matches {
            if let codeRange = Range(match.range(at: 1), in: content) {
                let code = String(content[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if code.isEmpty { continue }

                // Skip first block if it's a declaration (single-line struct/class/func/etc.)
                if isFirst {
                    isFirst = false
                    if isDeclaration(code) {
                        continue
                    }
                }

                examples.append(StructuredDocumentationPage.CodeExample(
                    code: code,
                    language: "swift"
                ))
            }
        }

        return examples
    }

    /// Check if a code block looks like a declaration rather than an example
    private static func isDeclaration(_ code: String) -> Bool {
        let lines = code.split(separator: "\n")
        // Short blocks that start with struct/class/func/etc. are likely declarations
        if lines.count <= 3 {
            let firstLine = code.trimmingCharacters(in: .whitespaces)
            if firstLine.hasPrefix("struct ") || firstLine.hasPrefix("class ") ||
                firstLine.hasPrefix("enum ") || firstLine.hasPrefix("protocol ") ||
                firstLine.hasPrefix("func ") || firstLine.hasPrefix("var ") ||
                firstLine.hasPrefix("let ") || firstLine.hasPrefix("typealias ") ||
                firstLine.hasPrefix("@frozen ") || firstLine.hasPrefix("@available") ||
                firstLine.hasPrefix("nonisolated") || firstLine.hasPrefix("init(") {
                return true
            }
        }
        return false
    }

    // MARK: - Sections Extraction

    private static func extractSections(from content: String) -> [StructuredDocumentationPage.Section] {
        // Try traditional Topics-based extraction first
        var sections = extractTopicsSections(from: content)

        // If no Topics sections found, try H2-based extraction (JSON markdown format)
        if sections.isEmpty {
            sections = extractH2Sections(from: content)
        }

        return sections
    }

    /// Extract sections from ## [Topics] / ### [Section] format (WebKit HTML)
    private static func extractTopicsSections(from content: String) -> [StructuredDocumentationPage.Section] {
        var sections: [StructuredDocumentationPage.Section] = []

        // Find ## [Topics] section
        guard let topicsStart = content.range(of: "## [Topics]") ??
            content.range(of: "## Topics") else {
            return sections
        }

        // Find end of Topics section
        let afterTopics = String(content[topicsStart.upperBound...])

        // Find next major section (## [Relationships], ## [See Also], etc.)
        let topicsEnd = afterTopics.range(of: "## [Relationships]")?.lowerBound ??
            afterTopics.range(of: "## [See Also]")?.lowerBound ??
            afterTopics.range(of: "## Relationships")?.lowerBound ??
            afterTopics.range(of: "## See Also")?.lowerBound ??
            afterTopics.endIndex

        let topicsContent = String(afterTopics[..<topicsEnd])

        // Parse ### sections
        let lines = topicsContent.split(separator: "\n", omittingEmptySubsequences: false)
        var currentSection: String?
        var currentItems: [StructuredDocumentationPage.Section.Item] = []
        var currentContent: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### ") {
                // Save previous section
                if let section = currentSection {
                    sections.append(StructuredDocumentationPage.Section(
                        title: section,
                        content: currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                        items: currentItems.isEmpty ? nil : currentItems
                    ))
                }

                // Start new section
                currentSection = extractLinkText(from: String(trimmed.dropFirst(4)))
                currentItems = []
                currentContent = []
            } else if trimmed.contains("[`") {
                // Parse ALL items on this line: [`name`](url)Desc[`name2`](url)Desc2
                // WebKit format puts multiple items on single line
                let items = parseAllTopicItems(trimmed)
                currentItems.append(contentsOf: items)
                currentContent.append(String(line))
            } else if !trimmed.isEmpty {
                currentContent.append(String(line))
            }
        }

        // Save last section
        if let section = currentSection {
            sections.append(StructuredDocumentationPage.Section(
                title: section,
                content: currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                items: currentItems.isEmpty ? nil : currentItems
            ))
        }

        return sections
    }

    /// Extract sections from ## Header / - **item**: format (JSON API markdown)
    private static func extractH2Sections(from content: String) -> [StructuredDocumentationPage.Section] {
        var sections: [StructuredDocumentationPage.Section] = []

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var currentSection: String?
        var currentItems: [StructuredDocumentationPage.Section.Item] = []
        var currentContent: [String] = []
        var inTopicsArea = false

        // Sections to skip (not API topics)
        let skipSections = Set([
            "Declaration",
            "Overview",
            "Discussion",
            "Mentioned in",
            "Relationships",
            "See Also",
            "Conforms To",
            "Inherits From",
            "Default Implementations",
            "Parameters",
        ])

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Look for ## headers (section titles)
            if trimmed.hasPrefix("## ") {
                // Save previous section if it had items
                if let section = currentSection, !currentItems.isEmpty {
                    sections.append(StructuredDocumentationPage.Section(
                        title: section,
                        content: currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                        items: currentItems
                    ))
                }

                // Get section name (remove brackets if present)
                var sectionName = String(trimmed.dropFirst(3))
                if sectionName.hasPrefix("[") {
                    sectionName = extractLinkText(from: sectionName)
                }

                // Skip non-topic sections
                if skipSections.contains(sectionName) {
                    currentSection = nil
                    currentItems = []
                    currentContent = []
                    inTopicsArea = false
                    continue
                }

                // Start new section
                currentSection = sectionName
                currentItems = []
                currentContent = []
                inTopicsArea = true

            } else if inTopicsArea, trimmed.hasPrefix("- **") {
                // Parse item: - **name**: Description
                if let item = parseBoldItem(trimmed) {
                    currentItems.append(item)
                }
                currentContent.append(String(line))
            }
        }

        // Save last section
        if let section = currentSection, !currentItems.isEmpty {
            sections.append(StructuredDocumentationPage.Section(
                title: section,
                content: currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                items: currentItems
            ))
        }

        return sections
    }

    /// Parse - **name**: Description format
    private static func parseBoldItem(_ line: String) -> StructuredDocumentationPage.Section.Item? {
        // Pattern: - **name**: Description or - **name**
        let pattern = #"- \*\*([^*]+)\*\*(?::?\s*(.*))?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let nameRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let name = String(line[nameRange])
        var description: String?

        if match.range(at: 2).location != NSNotFound,
           let descRange = Range(match.range(at: 2), in: line) {
            let desc = String(line[descRange]).trimmingCharacters(in: .whitespaces)
            if !desc.isEmpty {
                description = desc
            }
        }

        return StructuredDocumentationPage.Section.Item(name: name, description: description)
    }

    private static func extractLinkText(from text: String) -> String {
        // Extract text from [text](link) format
        if let start = text.firstIndex(of: "["),
           let end = text.firstIndex(of: "]") {
            return String(text[text.index(after: start)..<end])
        }
        return text
    }

    /// Parse ALL topic items from a line (WebKit puts multiple items on one line)
    /// Format: [`name`](url)Description[`name2`](url2)Description2
    private static func parseAllTopicItems(_ line: String) -> [StructuredDocumentationPage.Section.Item] {
        var items: [StructuredDocumentationPage.Section.Item] = []

        // Pattern matches: [`name`](url) followed by description (until next [` or end)
        // The description is everything up to the next [`
        let pattern = #"\[`([^`]+)`\]\(([^)]+)\)([^\[]*)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return items
        }

        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, options: [], range: range)

        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: line) else {
                continue
            }

            let name = String(line[nameRange])
            var description: String?
            var url: URL?

            if let urlRange = Range(match.range(at: 2), in: line) {
                let urlString = String(line[urlRange])
                url = URL(string: urlString)
            }

            if let descRange = Range(match.range(at: 3), in: line) {
                let desc = String(line[descRange]).trimmingCharacters(in: .whitespaces)
                if !desc.isEmpty {
                    description = desc
                }
            }

            items.append(StructuredDocumentationPage.Section.Item(name: name, description: description, url: url))
        }

        return items
    }

    private static func parseTopicItem(_ line: String) -> StructuredDocumentationPage.Section.Item? {
        // Pattern: [`name`](link)Description
        let pattern = #"\[`([^`]+)`\]\(([^)]+)\)(.*)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let nameRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let name = String(line[nameRange])
        var description: String?
        var url: URL?

        if let urlRange = Range(match.range(at: 2), in: line) {
            let urlString = String(line[urlRange])
            url = URL(string: urlString)
        }

        if let descRange = Range(match.range(at: 3), in: line) {
            let desc = String(line[descRange]).trimmingCharacters(in: .whitespaces)
            if !desc.isEmpty {
                description = desc
            }
        }

        return StructuredDocumentationPage.Section.Item(name: name, description: description, url: url)
    }

    // MARK: - Platform Extraction

    private static func extractPlatforms(from content: String) -> [String]? {
        var platforms: [String] = []

        // Pattern: iOS 17.0+, macOS 14.0+, etc. or iOS 3.0–18.0Deprecated
        // swiftlint:disable:next line_length
        let pattern = #"(iOS|iPadOS|macOS|tvOS|watchOS|visionOS|Mac Catalyst)\s*(\d+\.\d+)(?:–(\d+\.\d+))?(Deprecated|\+)?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        var seen = Set<String>()
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: content),
                  let versionRange = Range(match.range(at: 2), in: content) else {
                continue
            }

            let platformName = String(content[nameRange])
            let version = String(content[versionRange])
            let platformString = "\(platformName) \(version)+"

            if !seen.contains(platformString) {
                seen.insert(platformString)
                platforms.append(platformString)
            }
        }

        return platforms.isEmpty ? nil : platforms
    }

    // MARK: - Module Extraction

    private static func extractModule(from url: URL) -> String? {
        // Extract from URL path: /documentation/SwiftUI/Text -> SwiftUI
        let components = url.pathComponents
        if let docIndex = components.firstIndex(of: "documentation"),
           docIndex + 1 < components.count {
            return components[docIndex + 1]
        }
        return nil
    }

    // MARK: - Conformance Extraction

    private static func extractConformsTo(from content: String) -> [String]? {
        // Find "### [Conforms To]" or "### Conforms To" section
        guard let conformsStart = content.range(of: "### [Conforms To]") ??
            content.range(of: "### Conforms To") else {
            return nil
        }

        var protocols: [String] = []
        let afterConforms = String(content[conformsStart.upperBound...])
        let lines = afterConforms.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop at next section
            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                break
            }

            // Parse - [`Protocol`](link) format
            if trimmed.hasPrefix("- [`") {
                let pattern = #"\[`([^`]+)`\]"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(trimmed.startIndex..., in: trimmed)
                    if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                       let nameRange = Range(match.range(at: 1), in: trimmed) {
                        protocols.append(String(trimmed[nameRange]))
                    }
                }
            }
        }

        return protocols.isEmpty ? nil : protocols
    }
}
