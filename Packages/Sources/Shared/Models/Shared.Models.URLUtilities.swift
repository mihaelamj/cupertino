import Foundation

// MARK: - URL Utilities

/// Utilities for URL manipulation
extension Shared.Models {
    public enum URLUtilities {
        /// Returns a normalized copy of `url` with fragment and query stripped,
        /// path lowercased, and underscores replaced with dashes in sub-page
        /// segments within `/documentation/` paths.
        ///
        /// Applies underscore-to-dash replacement only to path segments at depth
        /// ≥ 3 (sub-page level). Framework slugs at depth 2 are preserved because
        /// at least two Apple frameworks (`installer_js`,
        /// `professional_video_applications`) use underscores canonically and
        /// their dash forms return 404. This resolves the 31 duplicate URI
        /// clusters in search.db (#285).
        ///
        /// - Parameter url: The URL to normalize.
        /// - Returns: The normalized URL, or `nil` if `url` cannot be decomposed
        ///   into URL components.
        public static func normalize(_ url: URL) -> URL? {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            components?.query = nil
            if let path = components?.path {
                components?.path = normalizeDocPath(path.lowercased())
            }
            return components?.url
        }

        /// Replace underscores with dashes in sub-page path segments only.
        /// Framework slugs at depth 2 after /documentation/ use underscores
        /// canonically (installer_js, professional_video_applications) and must
        /// be left untouched.
        ///
        /// Operator-bearing segments (`_=(_:_:)`, `operator-_`, etc.) are
        /// also skipped because Apple's URL encoding deliberately uses
        /// `_` to encode distinct operator characters: `_=` is the URL
        /// slug for `>=`, `_(_:_:)` is the URL slug for the `/` operator,
        /// `operator__` is `operator[]`, `operator-_` is `operator->`.
        /// Conflating those with the literal `-` form would fuse two
        /// distinct Apple pages into one URI (issue #588).
        private static func normalizeDocPath(_ path: String) -> String {
            let parts = path.components(separatedBy: "/")
            guard let docIdx = parts.firstIndex(of: "documentation"),
                  docIdx + 2 < parts.count else { return path }

            let normalizeFromIdx = docIdx + 2
            return parts
                .enumerated()
                .map { index, part -> String in
                    guard index >= normalizeFromIdx, !isOperatorBearing(part) else { return part }
                    return String(part.map { $0 == "_" ? "-" : $0 })
                }
                .joined(separator: "/")
        }

        /// A path segment is operator-bearing if it contains punctuation
        /// Apple preserves verbatim in its URL slugs, or starts with the
        /// C++ `operator` keyword. Such segments encode Swift / C++
        /// symbol identities where `_` and `-` mean different things
        /// (`_=` is `>=`, `-=` is `-=`); the blanket `_→-` collapse
        /// from #285 must not run on them.
        ///
        /// The punctuation set comes from Apple's observed URL slugs:
        /// `(` `)` `[` `]` `<` `>` `=` `+` `*` `/` `%` `!` `&` `|` `^`
        /// `~` `?`. Plain prose slugs (`integrating_accessibility_into_your_app`)
        /// carry none of these and remain subject to `_→-` so the
        /// originally-#285-targeted prose dedup still works.
        private static func isOperatorBearing(_ segment: String) -> Bool {
            let operatorPunctuation: Set<Character> = [
                "(", ")", "[", "]", "<", ">", "=",
                "+", "*", "/", "%", "!", "&", "|", "^", "~", "?",
            ]
            if segment.contains(where: { operatorPunctuation.contains($0) }) {
                return true
            }
            return segment.hasPrefix("operator")
        }

        /// Convert an Apple Developer Documentation URL into the canonical
        /// `apple-docs://` URI the search index stores. The URI is a
        /// **lossless mirror** of the URL's path under `/documentation/`:
        /// the framework name, then every remaining path segment joined
        /// by `/`. Lowercased + fragment / query stripped + sub-page
        /// underscores → dashes per the existing `normalize(_:)`
        /// canonicalisation (#283, #285). No hashing, no truncation, no
        /// special-char sanitisation.
        ///
        /// Returns `nil` for any URL that isn't a recognisable Apple
        /// Developer documentation URL: different host, no
        /// `/documentation/` segment, missing framework segment.
        ///
        /// ## Examples
        ///
        ///     /documentation/swiftui/view
        ///       → apple-docs://swiftui/view
        ///
        ///     /documentation/swiftui/toolbarrole/navigationstack
        ///       → apple-docs://swiftui/toolbarrole/navigationstack
        ///
        ///     /documentation/accelerate/sparsepreconditioner_t/init(rawvalue:)
        ///       → apple-docs://accelerate/sparsepreconditioner-t/init(rawvalue:)
        ///
        ///     /documentation/swiftui  (framework root)
        ///       → apple-docs://swiftui
        ///
        /// ## Why lossless
        ///
        /// Two different Apple URLs always produce two different URIs
        /// because the URI literally encodes the URL path. The
        /// pre-#293 `.lastPathComponent` shape collapsed siblings
        /// sharing a leaf name (e.g. `swiftui/NavigationStack` and
        /// `swiftui/ToolbarRole/navigationStack` both → `apple-docs://swiftui/navigationstack`)
        /// and the `INSERT OR REPLACE` dedup picked one winner, losing
        /// the other from the index entirely. The post-#293
        /// `filename(from:)` shape avoided most collisions by adding
        /// an 8-byte SHA-256 disambiguator suffix, but at the cost of
        /// opaque URIs and a probabilistic collision floor
        /// (~9 expected pairwise collisions in a 285K-doc corpus at
        /// 32-bit hash width). The lossless path-mirror shape removes
        /// the collision class at the URI layer — no probabilistic
        /// disambiguator, no truncation cap, no reverse mapping
        /// needed.
        ///
        /// ## URI ↔ URL is reversible
        ///
        /// A URI consumer that wants the source URL back can do
        /// `uri.replacingOccurrences(of: \"apple-docs://\", with: \"https://developer.apple.com/documentation/\")`.
        /// No index lookup required.
        ///
        /// ## Where it's used
        ///
        /// - Indexer (`Search.Strategies.AppleDocs.swift`) — URI stored
        ///   in `docs_metadata.uri` for every indexed page.
        /// - `MCP.Support.DocsResourceProvider.listResources` — URI
        ///   returned in MCP `resources/list` entries.
        /// - `Services.ReadService` (CLI `cupertino read`) — entry-
        ///   point normalisation accepts web URLs.
        /// - `CompositeToolProvider.handleReadDocument` (MCP tool) —
        ///   same entry-point normalisation.
        public static func appleDocsURI(from url: URL) -> String? {
            // Host check, if present. Bare URL strings handed in by
            // crawl metadata may have already been stripped down to
            // path-only — that's fine; we still try to interpret the
            // path. We just reject explicitly-non-Apple hosts.
            if let host = url.host, host != Shared.Constants.HostDomain.appleDeveloper {
                return nil
            }
            guard let canonical = normalize(url) else { return nil }
            let parts = canonical.pathComponents
            guard let docIdx = parts.firstIndex(of: "documentation"),
                  docIdx + 1 < parts.count
            else { return nil }
            let framework = parts[docIdx + 1]
            if docIdx + 2 >= parts.count {
                // Framework root URL — no path beyond the framework.
                return "\(Shared.Constants.Search.appleDocsScheme)\(framework)"
            }
            let rest = parts[(docIdx + 2)...].joined(separator: "/")
            return "\(Shared.Constants.Search.appleDocsScheme)\(framework)/\(rest)"
        }

        /// Convenience overload: parse a string-form URL and forward to
        /// `appleDocsURI(from:)`. Returns nil if the string doesn't
        /// parse as a URL or doesn't pass `appleDocsURI(from:)`'s URL
        /// shape check.
        public static func appleDocsURI(fromString string: String) -> String? {
            guard let url = URL(string: string) else { return nil }
            return appleDocsURI(from: url)
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

        /// Generate filename from URL.
        ///
        /// Output is the basename only (no `.json` extension, no framework dir).
        /// Length is capped at `maxFilenameBytes` so that `<filename>.json` fits
        /// within the 255-byte filesystem limit on macOS HFS+/APFS. Long
        /// auto-generated DocC slugs (e.g. Metal shader encoders with dozens of
        /// named parameters) get truncated and appended with an 8-char SHA-1
        /// suffix to keep collision-resistant uniqueness.
        public static func filename(from url: URL) -> String {
            // Canonicalize first so case-variant URLs collapse to identical filenames.
            // Without this, the disambiguator hash below (computed from
            // `originalCleaned`) diverges for case-variants like
            // `/documentation/Swift/withTaskGroup(...)` vs the all-lowercase form,
            // producing two distinct URIs in the index for the same Apple page (#283).
            let canonical = URLUtilities.normalize(url) ?? url
            var cleaned = canonical.absoluteString
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

            // Cap length so that `<filename>.json` (5-byte extension) fits within
            // the 255-byte filesystem basename limit. Without this, deeply-named
            // Apple symbols (e.g. MPSSVGF.encodeReprojection(...) with 12+ named
            // parameters) generate 280+ char filenames that fail to save with
            // POSIX errno 63 "File name too long".
            let maxFilenameBytes = 240
            if cleaned.utf8.count > maxFilenameBytes {
                let hash = HashUtilities.sha256(of: originalCleaned)
                let shortHash = String(hash.prefix(8))
                let suffix = "_\(shortHash)"

                // Strip any prior hash suffix so we don't end up with two
                let withoutPriorSuffix: String = if hasSpecialChars, cleaned.hasSuffix(suffix) {
                    String(cleaned.dropLast(suffix.count))
                } else {
                    cleaned
                }

                // Slugs are ASCII-only after the regex normalization above, so
                // String.prefix on character count == byte count.
                let availableBytes = maxFilenameBytes - suffix.utf8.count
                var truncated = String(withoutPriorSuffix.prefix(availableBytes))

                // Don't end on a trailing underscore — looks ugly, complicates
                // collision behavior with the suffix separator.
                while truncated.hasSuffix("_") {
                    truncated = String(truncated.dropLast())
                }

                cleaned = truncated + suffix
            }

            return cleaned.isEmpty ? "index" : cleaned
        }
    }
}
