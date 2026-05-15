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
        private static func normalizeDocPath(_ path: String) -> String {
            let parts = path.components(separatedBy: "/")
            guard let docIdx = parts.firstIndex(of: "documentation"),
                  docIdx + 2 < parts.count else { return path }

            let normalizeFromIdx = docIdx + 2
            return parts
                .enumerated()
                .map { index, part in
                    index >= normalizeFromIdx ? String(part.map { $0 == "_" ? "-" : $0 }) : part
                }
                .joined(separator: "/")
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
