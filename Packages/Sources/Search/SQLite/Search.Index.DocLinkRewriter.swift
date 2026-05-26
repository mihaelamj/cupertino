import Foundation

/// #113 — index-time `doc://` → `https://` link rewriter.
///
/// Apple's DocC uses internal URIs of the form
/// `doc://<bundleID>/documentation/<framework>/<path>` for cross-references
/// inside the rendered HTML pages cupertino crawls. The DocC renderer is
/// supposed to translate these to public
/// `https://developer.apple.com/documentation/<framework>/<path>` URLs, but
/// the translation sometimes fails — raw `doc://` URIs leak into the served
/// content, get stored verbatim, and surface in search snippets and
/// `read_document` payloads where AI clients can't follow them.
///
/// Per the #113 decision (issue body, "Decision" section): **index-time
/// rewrite during `cupertino save`** (Option 1), with **total rewrite
/// policy** and **edge-case (a)** for unresolved targets.
///
/// The rewrite is purely mechanical text substitution — URI path components
/// correspond directly to public URL path components, regardless of the
/// `<bundleID>` host segment, regardless of whether cupertino crawled the
/// target page. No DB lookup needed; the URL is real even when the target
/// wasn't indexed (`AI clients can choose to follow it; the link is
/// correct`).
///
/// Pattern: `doc://<any-host>/documentation/<rest>` → `https://developer.apple.com/documentation/<rest>`.
/// Preserves anchors (`#fragment`), query strings, and trailing path
/// segments. Idempotent: input with no `doc://` returns identical-string
/// (and `count: 0`); running twice yields the same output as running once.
///
/// The function is JSON-safe: the substring being replaced (`doc://...`)
/// and its replacement (`https://...`) contain no characters JSON cares
/// about (no `"`, `\\`, control chars), so the rewriter can run against a
/// serialised JSON document without breaking syntax. That lets
/// `indexStructuredDocument` rewrite both the FTS-side `content` blob AND
/// the `json_data` payload through the same primitive.
public enum DocLinkRewriter {
    /// The `doc://` URI prefix Apple's DocC emits before the host segment.
    static let docSchemePrefix = "doc://"

    /// The path segment that anchors a docs URI inside the DocC tree —
    /// anything before this we drop; anything from this onward we keep
    /// (re-prefixed with the public host).
    static let documentationAnchor = "/documentation/"

    /// The canonical public root every rewritten URI points at. Hardcoded
    /// because the issue body fixes the target as Apple's public docs site;
    /// when cupertino learns a non-Apple DocC source we'll need a router,
    /// but that's a separate ticket.
    static let publicRoot = "https://developer.apple.com"

    /// Rewrite every `doc://<host>/documentation/<rest>` occurrence in
    /// `input` to `https://developer.apple.com/documentation/<rest>`.
    ///
    /// - Parameter input: arbitrary stored content (markdown body,
    ///   serialised JSON, summary blob — anything the indexer holds in
    ///   string form). Pre-rewrite shape is preserved byte-for-byte for
    ///   substrings outside the `doc://...` match.
    /// - Returns: rewritten string + the number of substitutions performed
    ///   (the audit count for the save-log emission). Returns
    ///   `(input, 0)` unchanged when no `doc://` substring exists.
    public static func rewrite(_ input: String) -> (output: String, count: Int) {
        // Cheap pre-flight — vast majority of indexed pages have no
        // `doc://` at all (the DocC renderer succeeds most of the time).
        // Short-circuit the substring scan in that case.
        guard input.contains(docSchemePrefix) else {
            return (input, 0)
        }

        var output = ""
        output.reserveCapacity(input.count)
        var remaining = Substring(input)
        var count = 0

        while let docRange = remaining.range(of: docSchemePrefix) {
            // Emit everything before the match verbatim.
            output += remaining[remaining.startIndex..<docRange.lowerBound]

            // Look for the `/documentation/` anchor inside what follows
            // the `doc://`. The DocC bundle ID lives between the two,
            // but we don't care what it is — we drop it.
            let afterScheme = remaining[docRange.upperBound...]
            guard let anchorRange = afterScheme.range(of: documentationAnchor) else {
                // No `/documentation/` after this `doc://`. Treat the
                // `doc://` as not a real link (some other use of the
                // scheme prefix in prose, e.g. a literal quoted URI in
                // an explainer page). Emit verbatim + advance past the
                // scheme prefix so we don't loop on the same match.
                output += remaining[docRange.lowerBound..<docRange.upperBound]
                remaining = remaining[docRange.upperBound...]
                continue
            }

            // Emit the public-root replacement + the `/documentation/...`
            // tail. Everything after `/documentation/` flows through
            // unchanged — anchors (`#fragment`), trailing segments
            // (`/init(_:)-abc12`), nothing special.
            output += publicRoot
            output += documentationAnchor

            // Advance past the anchor; the tail starts at anchor's upper
            // bound. We'll keep consuming the URI body until we hit a
            // character that can't legally appear in a URL path (so the
            // next iteration's scan picks up cleanly from there).
            let tailStart = anchorRange.upperBound
            var tailEnd = tailStart
            while tailEnd < afterScheme.endIndex,
                  isAllowedInURIBody(afterScheme[tailEnd]) {
                tailEnd = afterScheme.index(after: tailEnd)
            }
            output += afterScheme[tailStart..<tailEnd]
            remaining = afterScheme[tailEnd...]
            count += 1
        }

        // Emit any trailing content past the last `doc://` match.
        output += remaining
        return (output, count)
    }

    /// Characters we accept inside the URI body (path + fragment + query).
    /// Deliberately permissive — RFC 3986 reserves a handful of characters
    /// (`<`, `>`, `"`, whitespace) that should never appear inside a URL
    /// because they terminate it in HTML / markdown / prose contexts; we
    /// stop scanning at any of those so the rewriter doesn't accidentally
    /// swallow a closing markdown bracket or whitespace that follows the
    /// link.
    private static func isAllowedInURIBody(_ char: Character) -> Bool {
        // Whitespace + structural punctuation that conventionally terminates
        // a URL in surrounding markup.
        if char.isWhitespace { return false }
        switch char {
        case "<", ">", "\"", "`", "(", ")", "[", "]", "{", "}":
            return false
        default:
            return true
        }
    }
}
