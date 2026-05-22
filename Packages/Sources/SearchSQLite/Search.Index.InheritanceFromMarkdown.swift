import Foundation
import SearchModels
import SharedConstants

// MARK: - Inheritance fallback parser (#669)

extension Search.Index {
    /// Parse class-inheritance URIs from a page's `rawMarkdown` blob (#669).
    ///
    /// Defensive fallback for the case where the on-disk JSON predates PR #638's
    /// URI-resolution second-walk inside `Core.JSONParser.AppleJSONToMarkdown.toStructuredPage`
    /// and so the structured page has nil `inheritsFromURIs` / `inheritedByURIs`
    /// arrays. The Apple DocC-derived markdown that the crawler writes into
    /// `StructuredDocumentationPage.rawMarkdown` preserves the relationships
    /// section verbatim:
    ///
    /// ```markdown
    /// ### [Inherits From](/documentation/uikit/uibutton#inherits-from)
    ///
    /// - [`UIControl`](/documentation/uikit/uicontrol)
    ///
    /// ### [Conforms To](/documentation/uikit/uibutton#conforms-to)
    ///
    /// - [`CALayerDelegate`](/documentation/QuartzCore/CALayerDelegate)
    /// ```
    ///
    /// This parser scans for `### [Inherits From]` and `### [Inherited By]`
    /// section headers, walks the immediately following bullet list, and
    /// resolves each link target to an `apple-docs://<framework>/<rest>` URI
    /// via `Shared.Models.URLUtilities.appleDocsURI(fromString:)`.
    ///
    /// Same shape as the live extractor at `AppleJSONToMarkdown.toStructuredPage`
    /// lines 619-674 — the only difference is the input. The output URIs
    /// flow into the existing `writeInheritanceEdges` writer unchanged.
    ///
    /// Recovery for any bundle whose JSON corpus predates #638 is
    /// `cupertino save` against the existing docs directory (minutes-scale,
    /// no recrawl needed). Once a future crawl regenerates the JSON with the
    /// new fields populated, this fallback no-ops because the dedicated
    /// arrays will be non-nil.
    ///
    /// - Parameter rawMarkdown: The page's rendered markdown blob.
    /// - Returns: Tuple of two URI arrays. Either may be empty. Both empty
    ///   means the page had no recognisable inheritance sections (the
    ///   common case for properties, methods, articles, samples).
    static func extractInheritanceURIsFromMarkdown(
        _ rawMarkdown: String
    ) -> (inheritsFrom: [String], inheritedBy: [String]) {
        let inheritsFrom = parseURISection(
            markdown: rawMarkdown, sectionTitle: "Inherits From"
        )
        let inheritedBy = parseURISection(
            markdown: rawMarkdown, sectionTitle: "Inherited By"
        )
        return (inheritsFrom, inheritedBy)
    }

    /// Resolve the inheritance URI pair to write for a structured page,
    /// falling back to `extractInheritanceURIsFromMarkdown` when the
    /// dedicated `inheritsFromURIs` / `inheritedByURIs` arrays are nil but
    /// the page carries a `rawMarkdown` blob the relationships can be
    /// recovered from. Returns `(nil, nil)` for pages that genuinely have
    /// no inheritance edges (most properties, methods, articles, samples).
    ///
    /// Extracted as its own helper so `indexDocument`'s cyclomatic
    /// complexity stays inside swiftlint's threshold.
    func resolveInheritanceURIs(
        for page: Shared.Models.StructuredDocumentationPage
    ) -> (inheritsFrom: [String]?, inheritedBy: [String]?) {
        if page.inheritsFromURIs == nil,
           page.inheritedByURIs == nil,
           let rawMarkdown = page.rawMarkdown {
            let recovered = Search.Index.extractInheritanceURIsFromMarkdown(rawMarkdown)
            return (
                recovered.inheritsFrom.isEmpty ? nil : recovered.inheritsFrom,
                recovered.inheritedBy.isEmpty ? nil : recovered.inheritedBy
            )
        }
        return (page.inheritsFromURIs, page.inheritedByURIs)
    }

    /// Walk `rawMarkdown` for a `### [<sectionTitle>]...` heading and return
    /// every `apple-docs://` URI found in the bullet list that immediately
    /// follows. The list ends at the next `###`/`##`/`# ` heading or the
    /// first blank line followed by a non-bullet line.
    ///
    /// Match is case-insensitive on the section title; tolerant of the
    /// optional `(/documentation/...)` anchor link Apple wraps the heading
    /// in. Link targets are accepted in three shapes:
    ///
    /// - Relative path: `/documentation/uikit/uicontrol` — prefixed with
    ///   `https://developer.apple.com` before resolution.
    /// - Full URL: `https://developer.apple.com/documentation/uikit/uicontrol`.
    /// - Lowercased / dashed / underscored variants — `URLUtilities.normalize`
    ///   handles canonicalisation inside `appleDocsURI(from:)`.
    ///
    /// Returns `[]` when the section isn't present. Returns a possibly-empty
    /// array when present-but-empty (zero bullet items, which Apple does emit
    /// for some abstract base classes).
    private static func parseURISection(
        markdown: String,
        sectionTitle: String
    ) -> [String] {
        // Split into lines so we can walk linearly. Performance is fine —
        // structured page rawMarkdown is bounded at a few hundred KB, and
        // this only fires on pages whose dedicated URI arrays are nil.
        let lines = markdown.components(separatedBy: "\n")

        // Locate the section heading. Apple emits both
        //   `### [Inherits From](/documentation/.../#inherits-from)`
        // and (rarer) plain
        //   `### Inherits From`
        // — accept both. Compare with case-insensitive prefix.
        var i = 0
        var foundIdx = -1
        let plainHeading = "### \(sectionTitle)"
        let bracketHeading = "### [\(sectionTitle)]"
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(plainHeading.lowercased())
                || trimmed.lowercased().hasPrefix(bracketHeading.lowercased()) {
                foundIdx = i
                break
            }
            i += 1
        }
        guard foundIdx >= 0 else { return [] }

        // Walk subsequent lines collecting bullet-item link targets until we
        // hit the next heading (any level) or two consecutive blank lines.
        var uris: [String] = []
        var blankRun = 0
        var cursor = foundIdx + 1
        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankRun += 1
                // A single blank line between heading and first item, or
                // between items, is normal — Apple emits one blank after
                // each item. Stop only on a run of two blanks (genuine
                // section break) or on the next heading.
                if blankRun >= 2 { break }
                cursor += 1
                continue
            }
            // Stop at next heading.
            if trimmed.hasPrefix("#") { break }
            // Reset blank-run counter on any non-blank content.
            blankRun = 0
            // Match a bullet item: `- [<text>](<target>)`. The bracketed
            // text usually wraps in backticks (`UIControl`); we don't need
            // it — only the target URL matters.
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if let target = extractMarkdownLinkTarget(from: trimmed) {
                    if let uri = resolveLinkTargetToAppleDocsURI(target) {
                        uris.append(uri)
                    }
                }
            }
            cursor += 1
        }
        return uris
    }

    /// Extract the `(...)` part of a markdown link `- [text](target)`.
    /// Returns nil when the line isn't a recognisable markdown link or the
    /// target part is empty.
    private static func extractMarkdownLinkTarget(from line: String) -> String? {
        // We allow leading whitespace + bullet marker stripped by caller.
        // Find the first `](` — the boundary between the link text and the
        // link target. Then the matching `)` (last one before any trailing
        // text, since Apple's targets contain no nested parens).
        guard let openParen = line.range(of: "](") else { return nil }
        let afterOpen = openParen.upperBound
        // Closing paren is the last `)` on the line — Apple's link targets
        // are well-formed URLs without embedded `)`.
        guard let closeParen = line.range(of: ")", options: .backwards, range: afterOpen..<line.endIndex) else {
            return nil
        }
        let target = String(line[afterOpen..<closeParen.lowerBound])
        return target.isEmpty ? nil : target
    }

    /// Convert a link target into an `apple-docs://` URI. Accepts relative
    /// (`/documentation/...`) and absolute (`https://developer.apple.com/...`)
    /// shapes. Strips fragments before resolution. Returns nil for any
    /// target that doesn't resolve to a documentation page (e.g. links to
    /// external sites or in-page anchors).
    private static func resolveLinkTargetToAppleDocsURI(_ target: String) -> String? {
        // Drop `#fragment` so URI normalisation matches what the crawler
        // stored. Apple uses fragments for "Conforms To" sub-anchors on the
        // same page; we want the page URI, not the fragment.
        let withoutFragment: String
        if let hashIdx = target.firstIndex(of: "#") {
            withoutFragment = String(target[..<hashIdx])
        } else {
            withoutFragment = target
        }
        // Build the absolute string. Relative `/documentation/...` paths
        // get prefixed with the Apple developer host; anything already
        // carrying a scheme is passed through verbatim.
        let absoluteString: String
        if withoutFragment.hasPrefix("/") {
            absoluteString = "\(Shared.Constants.BaseURL.appleDeveloper)\(withoutFragment)"
        } else if withoutFragment.hasPrefix("http://") || withoutFragment.hasPrefix("https://") {
            absoluteString = withoutFragment
        } else {
            // Not a doc link (could be an in-page anchor, mailto:, etc.).
            return nil
        }
        return Shared.Models.URLUtilities.appleDocsURI(fromString: absoluteString)
    }
}
