import Foundation
import Shared

// MARK: - Apple Documentation JSON to Markdown Converter

/// Converts Apple's documentation JSON API response to Markdown
/// This is a lightweight alternative to WKWebView rendering that avoids memory issues
/// with large index pages like lapack-functions (1600+ items)
public struct AppleJSONToMarkdown: ContentTransformer, @unchecked Sendable {
    public typealias RawContent = Data

    public init() {}

    // MARK: - ContentTransformer Protocol

    /// Transform JSON content to Markdown (protocol conformance)
    public func transform(_ content: Data, url: URL) -> String? {
        Self.convert(content, url: url)
    }

    /// Extract links from JSON content (protocol conformance)
    public func extractLinks(from content: Data) -> [URL] {
        Self.extractLinks(from: content)
    }

    // MARK: - Static API (backwards compatible)

    /// Convert Apple documentation JSON to Markdown
    public static func convert(_ json: Data, url: URL) -> String? {
        guard let doc = try? JSONDecoder().decode(AppleDocumentation.self, from: json) else {
            return nil
        }

        var markdown = ""

        // Add front matter with metadata
        markdown += "---\n"
        markdown += "source: \(url.absoluteString)\n"
        markdown += "crawled: \(ISO8601DateFormatter().string(from: Date()))\n"
        markdown += "---\n\n"

        // Title
        markdown += "# \(doc.metadata.title)\n\n"

        // Role heading (e.g., "Protocol", "Structure", "API Collection")
        if let roleHeading = doc.metadata.roleHeading {
            markdown += "**\(roleHeading)**\n\n"
        }

        // Abstract
        if !doc.abstract.isEmpty {
            markdown += renderInlineContent(doc.abstract)
            markdown += "\n\n"
        }

        // Primary content sections (declarations, parameters, return values, etc.)
        if let sections = doc.primaryContentSections {
            for section in sections {
                markdown += renderPrimaryContentSection(section)
            }
        }

        // Topic sections (grouped APIs)
        if let topics = doc.topicSections {
            for topic in topics {
                markdown += renderTopicSection(topic, references: doc.references)
            }
        }

        // See Also sections
        if let seeAlso = doc.seeAlsoSections {
            for section in seeAlso {
                markdown += renderTopicSection(section, references: doc.references)
            }
        }

        // Relationships
        if let relationships = doc.relationshipsSections {
            for section in relationships {
                markdown += renderRelationshipSection(section, references: doc.references)
            }
        }

        return markdown
    }

    /// Get the JSON API URL from a documentation URL
    public static func jsonAPIURL(from documentationURL: URL) -> URL? {
        // Web: https://developer.apple.com/documentation/accelerate/lapack-functions
        // JSON: https://developer.apple.com/tutorials/data/documentation/accelerate/lapack-functions.json
        let path = documentationURL.path
        guard path.hasPrefix("/documentation") else { return nil }
        return URL(string: "https://developer.apple.com/tutorials/data\(path).json")
    }

    /// Extract linked documentation URLs from the JSON response
    public static func extractLinks(from json: Data) -> [URL] {
        guard let doc = try? JSONDecoder().decode(AppleDocumentation.self, from: json) else {
            return []
        }

        var urls: [URL] = []

        // Extract from topic sections
        if let topics = doc.topicSections {
            for topic in topics {
                for identifier in topic.identifiers {
                    if let url = documentationURLFromIdentifier(identifier) {
                        urls.append(url)
                    }
                }
            }
        }

        // Extract from see also sections
        if let seeAlso = doc.seeAlsoSections {
            for section in seeAlso {
                for identifier in section.identifiers {
                    if let url = documentationURLFromIdentifier(identifier) {
                        urls.append(url)
                    }
                }
            }
        }

        // Extract from relationships
        if let relationships = doc.relationshipsSections {
            for section in relationships {
                for identifier in section.identifiers {
                    if let url = documentationURLFromIdentifier(identifier) {
                        urls.append(url)
                    }
                }
            }
        }

        return urls
    }

    // MARK: - Private Rendering Methods

    private static func renderInlineContent(_ content: [InlineContent]) -> String {
        content.map { item -> String in
            switch item.type {
            case "text":
                return item.text ?? ""
            case "codeVoice":
                return "`\(item.code ?? "")`"
            case "reference":
                if let identifier = item.identifier {
                    let title = item.title ?? identifier
                    return "[\(title)]"
                }
                return ""
            case "emphasis":
                if let inlineContent = item.inlineContent {
                    return "*\(renderInlineContent(inlineContent))*"
                }
                return ""
            case "strong":
                if let inlineContent = item.inlineContent {
                    return "**\(renderInlineContent(inlineContent))**"
                }
                return ""
            default:
                return item.text ?? ""
            }
        }.joined()
    }

    private static func renderPrimaryContentSection(_ section: PrimaryContentSection) -> String {
        var result = ""

        switch section.kind {
        case "declarations":
            if let declarations = section.declarations {
                result += "## Declaration\n\n"
                for declaration in declarations {
                    if let tokens = declaration.tokens {
                        result += "```swift\n"
                        result += tokens.map(\.text).joined()
                        result += "\n```\n\n"
                    }
                }
            }

        case "parameters":
            if let parameters = section.parameters {
                result += "## Parameters\n\n"
                for param in parameters {
                    result += "- **\(param.name)**: "
                    if let content = param.content {
                        result += renderContentBlocks(content)
                    }
                    result += "\n"
                }
                result += "\n"
            }

        case "content":
            if let content = section.content {
                result += renderContentBlocks(content)
                result += "\n\n"
            }

        default:
            break
        }

        return result
    }

    private static func renderContentBlocks(_ blocks: [ContentBlock]) -> String {
        blocks.map { block -> String in
            switch block.type {
            case "paragraph":
                if let inlineContent = block.inlineContent {
                    return renderInlineContent(inlineContent)
                }
                return ""

            case "codeListing":
                var code = "```"
                if let syntax = block.syntax {
                    code += syntax
                }
                code += "\n"
                if let lines = block.code {
                    code += lines.joined(separator: "\n")
                }
                code += "\n```"
                return code

            case "unorderedList":
                if let items = block.items {
                    return items.map { item -> String in
                        if let content = item.content {
                            return "- " + renderContentBlocks(content)
                        }
                        return ""
                    }.joined(separator: "\n")
                }
                return ""

            case "orderedList":
                if let items = block.items {
                    return items.enumerated().map { index, item -> String in
                        if let content = item.content {
                            return "\(index + 1). " + renderContentBlocks(content)
                        }
                        return ""
                    }.joined(separator: "\n")
                }
                return ""

            case "heading":
                let level = block.level ?? 2
                let prefix = String(repeating: "#", count: level)
                if let text = block.text {
                    return "\(prefix) \(text)"
                }
                return ""

            default:
                return ""
            }
        }.joined(separator: "\n\n")
    }

    private static func renderTopicSection(
        _ section: TopicSection,
        references: [String: Reference]?
    ) -> String {
        var result = "## \(section.title)\n\n"

        for identifier in section.identifiers {
            if let ref = references?[identifier] {
                let title = ref.title ?? identifier
                let abstract = ref.abstract.map { renderInlineContent($0) } ?? ""
                result += "- **\(title)**"
                if !abstract.isEmpty {
                    result += ": \(abstract)"
                }
                result += "\n"
            } else {
                // Just show the identifier if no reference found
                let shortName = identifier.components(separatedBy: "/").last ?? identifier
                result += "- \(shortName)\n"
            }
        }

        result += "\n"
        return result
    }

    private static func renderRelationshipSection(
        _ section: RelationshipSection,
        references: [String: Reference]?
    ) -> String {
        var result = "## \(section.title)\n\n"

        for identifier in section.identifiers {
            if let ref = references?[identifier] {
                result += "- \(ref.title ?? identifier)\n"
            } else {
                let shortName = identifier.components(separatedBy: "/").last ?? identifier
                result += "- \(shortName)\n"
            }
        }

        result += "\n"
        return result
    }

    private static func documentationURLFromIdentifier(_ identifier: String) -> URL? {
        // Identifier format: doc://com.apple.SwiftUI/documentation/SwiftUI/View
        // Output: https://developer.apple.com/documentation/SwiftUI/View
        guard identifier.hasPrefix("doc://") else { return nil }

        let components = identifier
            .replacingOccurrences(of: "doc://", with: "")
            .components(separatedBy: "/documentation/")

        guard components.count == 2 else { return nil }

        let path = components[1]
        return URL(string: "https://developer.apple.com/documentation/\(path)")
    }
}

// MARK: - JSON Models for Apple Documentation API

struct AppleDocumentation: Codable {
    let metadata: Metadata
    let abstract: [InlineContent]
    let primaryContentSections: [PrimaryContentSection]?
    let topicSections: [TopicSection]?
    let seeAlsoSections: [TopicSection]?
    let relationshipsSections: [RelationshipSection]?
    let references: [String: Reference]?

    struct Metadata: Codable {
        let title: String
        let role: String?
        let roleHeading: String?
        let modules: [Module]?

        struct Module: Codable {
            let name: String
        }
    }
}

struct InlineContent: Codable {
    let type: String
    let text: String?
    let code: String?
    let identifier: String?
    let title: String?
    let inlineContent: [InlineContent]?
}

struct PrimaryContentSection: Codable {
    let kind: String
    let declarations: [Declaration]?
    let parameters: [Parameter]?
    let content: [ContentBlock]?

    struct Declaration: Codable {
        let platforms: [String]?
        let tokens: [Token]?

        struct Token: Codable {
            let kind: String
            let text: String
        }
    }

    struct Parameter: Codable {
        let name: String
        let content: [ContentBlock]?
    }
}

struct ContentBlock: Codable {
    let type: String
    let inlineContent: [InlineContent]?
    let code: [String]?
    let syntax: String?
    let items: [ListItem]?
    let level: Int?
    let text: String?

    struct ListItem: Codable {
        let content: [ContentBlock]?
    }
}

struct TopicSection: Codable {
    let title: String
    let identifiers: [String]
}

struct RelationshipSection: Codable {
    let title: String
    let identifiers: [String]
    let kind: String?
}

struct Reference: Codable {
    let title: String?
    let abstract: [InlineContent]?
    let role: String?
    let url: String?
}

// MARK: - Apple JSON to StructuredDocumentationPage Converter

extension AppleJSONToMarkdown {
    /// Convert Apple documentation JSON to a StructuredDocumentationPage
    public static func toStructuredPage(_ json: Data, url: URL) -> StructuredDocumentationPage? {
        guard let doc = try? JSONDecoder().decode(AppleDocumentation.self, from: json) else {
            return nil
        }

        // Extract kind from roleHeading
        let kind = parseKind(from: doc.metadata.roleHeading, role: doc.metadata.role)

        // Extract abstract
        let abstract = doc.abstract.isEmpty ? nil : renderInlineContent(doc.abstract)

        // Extract declaration
        let declaration = extractDeclaration(from: doc.primaryContentSections)

        // Extract overview (content sections)
        let overview = extractOverview(from: doc.primaryContentSections)

        // Extract code examples
        let codeExamples = extractCodeExamples(from: doc.primaryContentSections)

        // Extract sections (topics, see also)
        var sections: [StructuredDocumentationPage.Section] = []

        if let topics = doc.topicSections {
            for topic in topics {
                sections.append(convertTopicSection(topic, references: doc.references))
            }
        }

        if let seeAlso = doc.seeAlsoSections {
            for section in seeAlso {
                sections.append(convertTopicSection(section, references: doc.references))
            }
        }

        // Extract relationships (conforms to, inherited by, conforming types)
        var conformsTo: [String]?
        var inheritedBy: [String]?
        var conformingTypes: [String]?

        if let relationships = doc.relationshipsSections {
            for section in relationships {
                let types = section.identifiers.compactMap { id -> String? in
                    if let ref = doc.references?[id] {
                        return ref.title
                    }
                    return id.components(separatedBy: "/").last
                }

                switch section.title.lowercased() {
                case "conforms to":
                    conformsTo = types
                case "inherited by":
                    inheritedBy = types
                case "conforming types":
                    conformingTypes = types
                default:
                    // Add as a section
                    sections.append(StructuredDocumentationPage.Section(
                        title: section.title,
                        items: types.map { .init(name: $0) }
                    ))
                }
            }
        }

        // Extract platforms from declarations
        let platforms = extractPlatforms(from: doc.primaryContentSections)

        // Extract module name
        let module = doc.metadata.modules?.first?.name

        // Compute content hash
        let contentHash = HashUtilities.sha256(of: json)

        // Also generate markdown representation
        let markdown = convert(json, url: url)

        return StructuredDocumentationPage(
            url: url,
            title: doc.metadata.title,
            kind: kind,
            source: .appleJSON,
            abstract: abstract,
            declaration: declaration,
            overview: overview,
            sections: sections,
            codeExamples: codeExamples,
            platforms: platforms,
            module: module,
            conformsTo: conformsTo,
            inheritedBy: inheritedBy,
            conformingTypes: conformingTypes,
            rawMarkdown: markdown,
            crawledAt: Date(),
            contentHash: contentHash
        )
    }

    // MARK: - Private Helpers for Structured Page

    private static func parseKind(
        from roleHeading: String?,
        role: String?
    ) -> StructuredDocumentationPage.Kind {
        let heading = roleHeading?.lowercased() ?? ""
        let roleStr = role?.lowercased() ?? ""

        switch heading {
        case "protocol": return .protocol
        case "class": return .class
        case "structure": return .struct
        case "enumeration": return .enum
        case "function": return .function
        case "property", "instance property", "type property": return .property
        case "method", "instance method", "type method": return .method
        case "operator": return .operator
        case "type alias": return .typeAlias
        case "macro": return .macro
        case "article": return .article
        case "tutorial": return .tutorial
        case "api collection", "collection": return .collection
        case "framework": return .framework
        default:
            // Fallback to role
            if roleStr.contains("collection") { return .collection }
            if roleStr.contains("article") { return .article }
            return .unknown
        }
    }

    private static func extractDeclaration(
        from sections: [PrimaryContentSection]?
    ) -> StructuredDocumentationPage.Declaration? {
        guard let sections else { return nil }

        for section in sections where section.kind == "declarations" {
            if let declarations = section.declarations,
               let first = declarations.first,
               let tokens = first.tokens {
                let code = tokens.map(\.text).joined()
                return StructuredDocumentationPage.Declaration(code: code, language: "swift")
            }
        }
        return nil
    }

    private static func extractOverview(from sections: [PrimaryContentSection]?) -> String? {
        guard let sections else { return nil }

        var overviewParts: [String] = []

        for section in sections where section.kind == "content" {
            if let content = section.content {
                // Only include paragraphs and headings, not code listings
                let textContent = content.compactMap { block -> String? in
                    switch block.type {
                    case "paragraph":
                        if let inline = block.inlineContent {
                            return renderInlineContent(inline)
                        }
                    case "heading":
                        let level = block.level ?? 2
                        let prefix = String(repeating: "#", count: level)
                        if let text = block.text {
                            return "\(prefix) \(text)"
                        }
                    default:
                        return nil
                    }
                    return nil
                }
                overviewParts.append(contentsOf: textContent)
            }
        }

        return overviewParts.isEmpty ? nil : overviewParts.joined(separator: "\n\n")
    }

    private static func extractCodeExamples(
        from sections: [PrimaryContentSection]?
    ) -> [StructuredDocumentationPage.CodeExample] {
        guard let sections else { return [] }

        var examples: [StructuredDocumentationPage.CodeExample] = []

        for section in sections where section.kind == "content" {
            if let content = section.content {
                for block in content where block.type == "codeListing" {
                    if let code = block.code {
                        examples.append(StructuredDocumentationPage.CodeExample(
                            code: code.joined(separator: "\n"),
                            language: block.syntax
                        ))
                    }
                }
            }
        }

        return examples
    }

    private static func extractPlatforms(from sections: [PrimaryContentSection]?) -> [String]? {
        guard let sections else { return nil }

        for section in sections where section.kind == "declarations" {
            if let declarations = section.declarations,
               let first = declarations.first,
               let platforms = first.platforms, !platforms.isEmpty {
                return platforms
            }
        }
        return nil
    }

    private static func convertTopicSection(
        _ section: TopicSection,
        references: [String: Reference]?
    ) -> StructuredDocumentationPage.Section {
        let items = section.identifiers.compactMap { identifier -> StructuredDocumentationPage.Section.Item? in
            let ref = references?[identifier]
            let name = ref?.title ?? identifier.components(separatedBy: "/").last ?? identifier
            let description = ref?.abstract.map { renderInlineContent($0) }
            let itemURL = documentationURLFromIdentifier(identifier)
            return StructuredDocumentationPage.Section.Item(
                name: name,
                description: description,
                url: itemURL
            )
        }
        return StructuredDocumentationPage.Section(title: section.title, items: items)
    }
}
