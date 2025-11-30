import Foundation

// MARK: - XML Transformer

/// Transforms XML content (like sitemaps or RSS feeds) into structured data
/// Useful for parsing web crawled pages that return XML format
public struct XMLTransformer: ContentTransformer, @unchecked Sendable {
    public typealias RawContent = Data

    public init() {}

    // MARK: - ContentTransformer Protocol

    /// Transform XML content to Markdown (protocol conformance)
    public func transform(_ content: Data, url: URL) -> String? {
        Self.convert(content, url: url)
    }

    /// Extract links from XML content (protocol conformance)
    public func extractLinks(from content: Data) -> [URL] {
        Self.extractLinks(from: content)
    }

    // MARK: - Static API (consistent with other transformers)

    /// Convert XML data to Markdown
    public static func convert(_ data: Data, url: URL) -> String? {
        guard let parser = XMLToMarkdownParser(data: data, sourceURL: url) else {
            return nil
        }
        return parser.parse()
    }

    /// Extract links from XML content
    public static func extractLinks(from data: Data) -> [URL] {
        guard let parser = XMLLinkExtractor(data: data) else {
            return []
        }
        return parser.extractLinks()
    }
}

// MARK: - XML to Markdown Parser

/// Parses XML and converts to Markdown format
final class XMLToMarkdownParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let sourceURL: URL

    private var lines: [String] = []
    private var currentElement: String = ""
    private var currentText: String = ""
    private var elementStack: [String] = []
    private var attributes: [String: String] = [:]

    init?(data: Data, sourceURL: URL) {
        parser = XMLParser(data: data)
        self.sourceURL = sourceURL
        super.init()
        parser.delegate = self
    }

    func parse() -> String? {
        guard parser.parse() else { return nil }

        // Add source reference
        lines.append("")
        lines.append("---")
        lines.append("*Source: [\(sourceURL.absoluteString)](\(sourceURL.absoluteString))*")

        return lines.joined(separator: "\n")
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        elementStack.append(elementName)
        attributes = attributeDict
        currentText = ""

        // Handle specific XML elements
        switch elementName.lowercased() {
        case "item", "entry":
            lines.append("")
            lines.append("---")
            lines.append("")
        case "channel", "feed":
            if let title = attributeDict["title"] {
                lines.append("# \(title)")
                lines.append("")
            }
        case "url":
            // Sitemap URL entry
            break
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle specific XML elements
        switch elementName.lowercased() {
        case "title":
            if !text.isEmpty {
                let depth = elementStack.count
                let prefix = depth <= 2 ? "#" : "##"
                lines.append("\(prefix) \(text)")
                lines.append("")
            }
        case "description", "summary", "content":
            if !text.isEmpty {
                lines.append(text)
                lines.append("")
            }
        case "link":
            if !text.isEmpty {
                lines.append("[\(text)](\(text))")
                lines.append("")
            } else if let href = attributes["href"] {
                lines.append("[Link](\(href))")
                lines.append("")
            }
        case "loc":
            // Sitemap location
            if !text.isEmpty {
                lines.append("- [\(text)](\(text))")
            }
        case "lastmod":
            if !text.isEmpty {
                lines.append("  *Last modified: \(text)*")
            }
        case "pubdate", "published", "updated":
            if !text.isEmpty {
                lines.append("*Published: \(text)*")
                lines.append("")
            }
        case "author", "creator":
            if !text.isEmpty {
                lines.append("*Author: \(text)*")
                lines.append("")
            }
        case "category":
            if !text.isEmpty {
                lines.append("**Category**: \(text)")
            }
        default:
            break
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
        currentElement = elementStack.last ?? ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
}

// MARK: - XML Link Extractor

/// Extracts links from XML content (sitemaps, RSS feeds, etc.)
final class XMLLinkExtractor: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var links: [URL] = []
    private var currentElement: String = ""
    private var currentText: String = ""

    init?(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func extractLinks() -> [URL] {
        parser.parse()
        return links
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()
        currentText = ""

        // Check for href attribute
        if let href = attributeDict["href"], let url = URL(string: href) {
            links.append(url)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract URLs from link and loc elements
        if ["link", "loc", "url", "href"].contains(currentElement), !text.isEmpty {
            if let url = URL(string: text) {
                links.append(url)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
}
