import Foundation
import SearchModels
import SharedConstants
import SQLite3

// MARK: - Search.DocumentChildrenListing

extension Search.Index: Search.DocumentChildrenListing {
    public func listChildren(
        source: String,
        uri: String
    ) async throws -> Search.DocumentChildrenPage {
        guard let database else {
            throw Search.Error.databaseNotInitialized
        }

        let effectiveSource = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Shared.Constants.SourcePrefix.appleDocs
            : source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard effectiveSource == Shared.Constants.SourcePrefix.appleDocs else {
            throw Search.Error.invalidQuery("Document children currently support only apple-docs")
        }

        let normalized = try Self.normalizedAppleDocsInputURI(uri)
        guard let parent = try loadDocument(database: database, uri: normalized.baseURI) else {
            throw Search.Error.invalidQuery("Document not found: \(normalized.baseURI)")
        }

        let topics = Self.parseTopics(markdown: parent.rawMarkdown, parentURI: normalized.baseURI)
        let children: [Search.DocumentChild]
        let parentURI: String
        if let fragment = normalized.fragment {
            guard let group = topics.group(matching: fragment, parentURI: normalized.baseURI) else {
                children = []
                return Search.DocumentChildrenPage(
                    source: effectiveSource,
                    parentURI: normalized.fullURI,
                    children: children
                )
            }
            parentURI = group.uri
            children = try documentChildren(
                database: database,
                parentURI: normalized.baseURI,
                links: Self.extractDocumentLinks(from: group.segment)
            )
        } else if !topics.groups.isEmpty {
            parentURI = normalized.fullURI
            children = try topics.groups.map { group in
                let readableChildren = try documentChildren(
                    database: database,
                    parentURI: normalized.baseURI,
                    links: Self.extractDocumentLinks(from: group.segment)
                )
                return Search.DocumentChild(
                    uri: group.uri,
                    title: group.title,
                    kind: "topic-group",
                    hasChildren: !readableChildren.isEmpty
                )
            }
        } else {
            parentURI = normalized.fullURI
            children = try documentChildren(
                database: database,
                parentURI: normalized.baseURI,
                links: topics.links
            )
        }

        return Search.DocumentChildrenPage(
            source: effectiveSource,
            parentURI: parentURI,
            children: children
        )
    }

    private func documentChildren(
        database: OpaquePointer,
        parentURI: String,
        links: [MarkdownLink]
    ) throws -> [Search.DocumentChild] {
        var seen: Set<String> = []
        var children: [Search.DocumentChild] = []

        for link in links {
            guard seen.insert(link.uri).inserted,
                  link.uri != parentURI,
                  let document = try loadDocument(database: database, uri: link.uri) else {
                continue
            }

            children.append(Search.DocumentChild(
                uri: document.uri,
                title: link.title.isEmpty ? document.title : link.title,
                kind: document.kind,
                hasChildren: Self.parseTopics(
                    markdown: document.rawMarkdown,
                    parentURI: document.uri
                ).hasChildren
            ))
        }

        return children
    }

    private func loadDocument(
        database: OpaquePointer,
        uri: String
    ) throws -> StoredDocument? {
        let sql = """
        SELECT
            m.uri,
            COALESCE(NULLIF(s.title, ''), NULLIF(json_extract(m.json_data, '$.title'), ''), m.uri) AS title,
            COALESCE(
                NULLIF(s.kind, ''),
                NULLIF(json_extract(m.json_data, '$.kind'), ''),
                NULLIF(m.kind, ''),
                'unknown'
            ) AS kind,
            COALESCE(NULLIF(json_extract(m.json_data, '$.rawMarkdown'), ''), '') AS raw_markdown
        FROM docs_metadata m
        LEFT JOIN docs_structured s ON s.uri = m.uri
        WHERE m.uri = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            throw Search.Error.searchFailed("Load document failed: \(errorMessage)")
        }

        sqlite3_bind_text(statement, 1, (uri as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let resolvedURI = Self.childrenTextColumn(statement, 0) else {
            return nil
        }

        return StoredDocument(
            uri: resolvedURI,
            title: Self.childrenTextColumn(statement, 1) ?? resolvedURI,
            kind: Self.childrenTextColumn(statement, 2) ?? "unknown",
            rawMarkdown: Self.childrenTextColumn(statement, 3) ?? ""
        )
    }

    private static func childrenTextColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }
}

// MARK: - Markdown Topic Parsing

private struct StoredDocument {
    let uri: String
    let title: String
    let kind: String
    let rawMarkdown: String
}

private struct NormalizedDocumentURI {
    let baseURI: String
    let fragment: String?

    var fullURI: String {
        guard let fragment, !fragment.isEmpty else { return baseURI }
        return "\(baseURI)#\(fragment)"
    }
}

private struct MarkdownLink {
    let uri: String
    let title: String
}

private struct TopicGroup {
    let uri: String
    let title: String
    let anchor: String
    let segment: String
}

private struct ParsedTopics {
    let groups: [TopicGroup]
    let links: [MarkdownLink]

    var hasChildren: Bool {
        !groups.isEmpty || !links.isEmpty
    }

    func group(matching fragment: String, parentURI: String) -> TopicGroup? {
        let normalizedFragment = Self.normalizedAnchor(fragment)
        let fullURI = "\(parentURI)#\(fragment)"
        return groups.first { group in
            group.uri.caseInsensitiveCompare(fullURI) == .orderedSame
                || Self.normalizedAnchor(group.anchor) == normalizedFragment
                || Self.normalizedAnchor(group.title) == normalizedFragment
        }
    }

    private static func normalizedAnchor(_ value: String) -> String {
        (value.removingPercentEncoding ?? value)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }
}

private extension Search.Index {
    static func normalizedAppleDocsInputURI(_ raw: String) throws -> NormalizedDocumentURI {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Search.Error.invalidQuery("Document URI is required")
        }

        let parts = splitFragment(trimmed)
        let base = parts.base
        let normalizedBase: String?
        if base.hasPrefix(Shared.Constants.Search.appleDocsScheme) {
            normalizedBase = base.lowercased()
        } else {
            normalizedBase = Shared.Models.URLUtilities.appleDocsURI(fromString: base)
        }

        guard let normalizedBase else {
            throw Search.Error.invalidQuery("Expected an apple-docs URI or Apple documentation URL")
        }
        return NormalizedDocumentURI(baseURI: normalizedBase, fragment: parts.fragment)
    }

    static func parseTopics(
        markdown: String,
        parentURI: String
    ) -> ParsedTopics {
        guard let topicsRange = markdown.range(of: "## [Topics]", options: [.caseInsensitive])
            ?? markdown.range(of: "## Topics", options: [.caseInsensitive]) else {
            return ParsedTopics(groups: [], links: [])
        }

        let sectionStart = markdown[topicsRange.upperBound...].firstIndex(of: "\n")
            .map { markdown.index(after: $0) }
            ?? topicsRange.upperBound
        let remaining = markdown[sectionStart...]
        let sectionEnd = remaining.range(of: "\n## ")?.lowerBound ?? markdown.endIndex
        let section = String(markdown[sectionStart..<sectionEnd])

        let groups = parseTopicGroups(section: section, parentURI: parentURI)
        if groups.isEmpty {
            return ParsedTopics(
                groups: [],
                links: extractDocumentLinks(from: section)
            )
        }
        return ParsedTopics(groups: groups, links: [])
    }

    static func extractDocumentLinks(from section: String) -> [MarkdownLink] {
        var links: [MarkdownLink] = []
        for link in scanMarkdownLinks(section) {
            guard let uri = resolveLinkTargetToAppleDocsURI(link.target) else { continue }
            links.append(MarkdownLink(
                uri: uri,
                title: cleanedLinkTitle(link.title)
            ))
        }
        return links
    }

    private static func parseTopicGroups(
        section: String,
        parentURI: String
    ) -> [TopicGroup] {
        let pattern = #"###\s+(?:\[([^\]]+)\]\(([^\)]*)\)|([^\n#]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(section.startIndex..<section.endIndex, in: section)
        let matches = regex.matches(in: section, range: range)
        guard !matches.isEmpty else { return [] }

        return matches.enumerated().compactMap { index, match in
            guard let fullRange = Range(match.range, in: section) else { return nil }
            let title = groupTitle(match: match, in: section)
            guard !title.isEmpty else { return nil }
            let anchor = groupAnchor(match: match, in: section, title: title)
            let nextStart = matches.indices.contains(index + 1)
                ? Range(matches[index + 1].range, in: section)?.lowerBound ?? section.endIndex
                : section.endIndex
            let segment = String(section[fullRange.upperBound..<nextStart])
            return TopicGroup(
                uri: "\(parentURI)#\(anchor)",
                title: title,
                anchor: anchor,
                segment: segment
            )
        }
    }

    private static func groupTitle(
        match: NSTextCheckingResult,
        in section: String
    ) -> String {
        if match.range(at: 1).location != NSNotFound,
           let range = Range(match.range(at: 1), in: section) {
            return cleanedLinkTitle(String(section[range]))
        }
        if match.range(at: 3).location != NSNotFound,
           let range = Range(match.range(at: 3), in: section) {
            return cleanedLinkTitle(String(section[range]))
        }
        return ""
    }

    private static func groupAnchor(
        match: NSTextCheckingResult,
        in section: String,
        title: String
    ) -> String {
        if match.range(at: 2).location != NSNotFound,
           let range = Range(match.range(at: 2), in: section) {
            let target = String(section[range])
            if let hash = target.firstIndex(of: "#") {
                return String(target[target.index(after: hash)...])
            }
        }
        return title.replacingOccurrences(of: " ", with: "-")
    }

    private static func scanMarkdownLinks(_ markdown: String) -> [(title: String, target: String)] {
        var result: [(title: String, target: String)] = []
        var cursor = markdown.startIndex

        while let openBracket = markdown[cursor...].firstIndex(of: "[") {
            if openBracket > markdown.startIndex {
                let previous = markdown.index(before: openBracket)
                if markdown[previous] == "!" {
                    cursor = markdown.index(after: openBracket)
                    continue
                }
            }

            guard let boundary = markdown[openBracket...].range(of: "](") else {
                cursor = markdown.index(after: openBracket)
                continue
            }

            let targetStart = boundary.upperBound
            guard let targetEnd = balancedTargetEnd(in: markdown, from: targetStart) else {
                cursor = boundary.upperBound
                continue
            }

            let title = String(markdown[markdown.index(after: openBracket)..<boundary.lowerBound])
            let target = String(markdown[targetStart..<targetEnd])
            if !target.isEmpty {
                result.append((title, target))
            }
            cursor = markdown.index(after: targetEnd)
        }

        return result
    }

    private static func balancedTargetEnd(
        in markdown: String,
        from start: String.Index
    ) -> String.Index? {
        var cursor = start
        var depth = 1
        while cursor < markdown.endIndex {
            let character = markdown[cursor]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor = markdown.index(after: cursor)
        }
        return nil
    }

    private static func cleanedLinkTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitFragment(_ uri: String) -> (base: String, fragment: String?) {
        guard let hash = uri.firstIndex(of: "#") else {
            return (uri, nil)
        }
        let base = String(uri[..<hash])
        let fragment = String(uri[uri.index(after: hash)...])
        return (base, fragment.isEmpty ? nil : fragment)
    }

    private static func resolveLinkTargetToAppleDocsURI(_ target: String) -> String? {
        let withoutFragment: String
        if let hashIdx = target.firstIndex(of: "#") {
            withoutFragment = String(target[..<hashIdx])
        } else {
            withoutFragment = target
        }

        let absoluteString: String
        if withoutFragment.hasPrefix("/") {
            absoluteString = "\(Shared.Constants.BaseURL.appleDeveloper)\(withoutFragment)"
        } else if withoutFragment.hasPrefix("http://") || withoutFragment.hasPrefix("https://") {
            absoluteString = withoutFragment
        } else {
            return nil
        }
        return Shared.Models.URLUtilities.appleDocsURI(fromString: absoluteString)
    }
}
