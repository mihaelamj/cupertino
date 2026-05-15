import Foundation
import SearchModels
import SharedConstants
// MARK: - StrategyHelpers

extension Search {
    /// Pure utility helpers shared across all ``SourceIndexingStrategy`` implementations.
    ///
    /// All members are `static` and side-effect-free: they read from disk or parse strings
    /// but never write to the search index.  Centralising these helpers keeps each strategy
    /// type focused on orchestration while ensuring a single, well-tested implementation
    /// of every shared concern (file discovery, deduplication, front-matter parsing, etc.).
    public enum StrategyHelpers {
        // MARK: - File Discovery

        /// Recursively find all `.json` and `.md` documentation files under `directory`.
        ///
        /// JSON files are preferred over Markdown: when both `foo.json` and `foo.md` exist
        /// in the same directory only the JSON file is returned.  `metadata.json` files are
        /// excluded because they are crawl-manifest files, not documentation pages (fix #110).
        ///
        /// The two-pass approach (collect JSONs first, then MDs) ensures `jsonFiles` is
        /// fully populated before Markdown files are considered, regardless of filesystem
        /// enumeration order.
        ///
        /// - Parameter directory: The root directory to scan recursively.
        /// - Returns: A list of matching file URLs (order is filesystem-defined).
        public static func findDocFiles(in directory: URL) throws -> [URL] {
            var jsonFiles: Set<String> = []
            var docFiles: [URL] = []

            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return docFiles
            }

            var allFiles: [URL] = []
            while let element = enumerator.nextObject() {
                guard let fileURL = element as? URL else { continue }
                let ext = fileURL.pathExtension.lowercased()
                guard ext == "json" || ext == "md" else { continue }
                // Skip crawl-manifest files (fix #110).
                if fileURL.lastPathComponent == "metadata.json" { continue }
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                   !isDirectory.boolValue {
                    allFiles.append(fileURL)
                }
            }

            // First pass: collect JSON files and record their base names.
            for file in allFiles where file.pathExtension.lowercased() == "json" {
                let basename = file.deletingPathExtension().lastPathComponent
                let dir = file.deletingLastPathComponent().path
                jsonFiles.insert("\(dir)/\(basename)")
                docFiles.append(file)
            }
            // Second pass: add Markdown files only when no JSON sibling was found.
            for file in allFiles where file.pathExtension.lowercased() == "md" {
                let basename = file.deletingPathExtension().lastPathComponent
                let dir = file.deletingLastPathComponent().path
                if !jsonFiles.contains("\(dir)/\(basename)") {
                    docFiles.append(file)
                }
            }

            return docFiles
        }

        /// Recursively find all `.md` files under `directory`.
        ///
        /// Used by sources such as Archive and HIG that only ship Markdown, not JSON.
        ///
        /// - Parameter directory: The root directory to scan recursively.
        /// - Returns: A list of matching `.md` file URLs (order is filesystem-defined).
        public static func findMarkdownFiles(in directory: URL) throws -> [URL] {
            var markdownFiles: [URL] = []
            if let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    guard fileURL.pathExtension == "md" else { continue }
                    let attrs = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if attrs?.isRegularFile == true {
                        markdownFiles.append(fileURL)
                    }
                }
            }
            return markdownFiles
        }

        // MARK: - Path Utilities

        /// Extract the first path component of `file` relative to `baseDir`.
        ///
        /// Used to derive the framework name from paths of the form
        /// `<baseDir>/{framework}/...`.  Both paths are standardised before comparison to
        /// handle `/private/var` vs `/var` symlink discrepancies on macOS.
        ///
        /// - Parameters:
        ///   - file: A file URL that must be a descendant of `baseDir`.
        ///   - baseDir: The root directory to strip.
        /// - Returns: The first path component after stripping `baseDir`, or `nil` when
        ///   `file` is not beneath `baseDir` or the relative path has no components.
        public static func extractFrameworkFromPath(_ file: URL, relativeTo baseDir: URL) -> String? {
            let basePath = baseDir.standardizedFileURL.path
            let filePath = file.standardizedFileURL.path
            guard filePath.hasPrefix(basePath) else { return nil }
            let relativePath = String(filePath.dropFirst(basePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = relativePath.split(separator: "/")
            guard let framework = components.first else { return nil }
            return String(framework)
        }

        /// Lowercase a single path component for canonical comparison.
        ///
        /// Mirrors `URLUtilities.normalize`, which deliberately does **not** collapse
        /// underscore → dash because at least one Apple framework (`installer_js`) uses
        /// underscores in its path and Apple does not redirect the dash variant.
        ///
        /// - Parameter component: A raw path component string.
        /// - Returns: The lowercased component.
        public static func canonicalPathComponent(_ component: String) -> String {
            component.lowercased()
        }

        // MARK: - Content Parsing

        /// Extract the first `# Heading` from a Markdown string, skipping YAML front matter.
        ///
        /// - Parameter markdown: Raw Markdown content.
        /// - Returns: The heading text without the `# ` prefix, or `nil` if not found.
        public static func extractTitle(from markdown: String) -> String? {
            var content = markdown
            if let firstDash = markdown.range(of: "---")?.lowerBound,
               let secondDash = markdown.range(
                   of: "---",
                   range: markdown.index(after: firstDash)..<markdown.endIndex
               )?.upperBound {
                content = String(markdown[secondDash...])
            }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") {
                    return String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
                }
            }
            return nil
        }

        /// Extract the `Status:` field from a Swift Evolution proposal Markdown file.
        ///
        /// Expected format: `* Status: **Implemented (Swift 5.5)**`
        ///
        /// - Parameter markdown: Raw Markdown content of a proposal file.
        /// - Returns: The status string (e.g., `"Implemented (Swift 5.5)"`), or `nil`.
        public static func extractProposalStatus(from markdown: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: Shared.Constants.Pattern.seStatus),
                  let match = regex.firstMatch(
                      in: markdown,
                      range: NSRange(markdown.startIndex..., in: markdown)
                  ),
                  match.numberOfRanges > 1,
                  let statusRange = Range(match.range(at: 1), in: markdown)
            else { return nil }
            return String(markdown[statusRange])
        }

        /// Return `true` when a Swift Evolution proposal should be indexed.
        ///
        /// Accepted statuses include `"Implemented"`, `"Accepted"`, and
        /// `"Accepted with revisions"` (case-insensitive).
        ///
        /// - Parameter status: The raw status string from ``extractProposalStatus(from:)``.
        /// - Returns: `true` if the proposal should be indexed.
        public static func isAcceptedProposal(_ status: String?) -> Bool {
            guard let status = status?.lowercased() else { return false }
            return status.contains("implemented") || status.contains("accepted")
        }

        /// Extract the `SE-NNNN` or `ST-NNNN` identifier from a proposal filename.
        ///
        /// - Parameter filename: Base filename without extension (e.g., `"SE-0001-generics"`).
        /// - Returns: The proposal ID (e.g., `"SE-0001"`), or `nil` if the pattern is absent.
        public static func extractProposalID(from filename: String) -> String? {
            guard let regex = try? NSRegularExpression(
                pattern: Shared.Constants.Pattern.evolutionReference, options: []
            ),
                let match = regex.firstMatch(
                    in: filename, range: NSRange(filename.startIndex..., in: filename)
                ),
                let range = Range(match.range(at: 1), in: filename)
            else { return nil }
            return String(filename[range])
        }

        /// Map a Swift Evolution `"Implemented (Swift X.Y)"` status string to the
        /// corresponding minimum iOS and macOS availability versions.
        ///
        /// Version mapping source: https://swiftversion.net
        ///
        /// - Parameter status: The raw status string (may contain a Swift version tag).
        /// - Returns: `(iOS, macOS)` minimum version strings; both `nil` when the version
        ///   cannot be determined.
        public static func mapSwiftVersionToAvailability(
            _ status: String?
        ) -> (iOS: String?, macOS: String?) {
            guard let status else { return (nil, nil) }
            let pattern = #"Swift\s+(\d+(?:\.\d+)?)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(
                      in: status, range: NSRange(status.startIndex..., in: status)
                  ),
                  match.numberOfRanges > 1,
                  let versionRange = Range(match.range(at: 1), in: status)
            else { return (nil, nil) }

            let swiftVersion = String(status[versionRange])
            let parts = swiftVersion.split(separator: ".")
            let major = parts.first.flatMap { Int($0) } ?? 0
            let minor = parts.dropFirst().first.flatMap { Int($0) } ?? 0

            switch (major, minor) {
            case (6, _): return ("18.0", "15.0")
            case (5, 10): return ("17.4", "14.4")
            case (5, 9): return ("17.0", "14.0")
            case (5, 8): return ("16.4", "13.3")
            case (5, 7): return ("16.0", "13.0")
            case (5, 6): return ("15.4", "12.3")
            case (5, 5): return ("15.0", "12.0")
            case (5, 4): return ("14.5", "11.3")
            case (5, 3): return ("14.0", "11.0")
            case (5, 2): return ("13.4", "10.15.4")
            case (5, 1): return ("13.0", "10.15")
            case (5, 0): return ("12.2", "10.14.4")
            case (4, 2): return ("12.0", "10.14")
            case (4, 1): return ("11.3", "10.13.4")
            case (4, 0): return ("11.0", "10.13")
            case (3, _): return ("10.0", "10.12")
            case (2, _): return ("9.0", "10.11")
            default: return ("8.0", "10.9")
            }
        }

        // MARK: - Front-Matter Parsers

        /// Parse YAML front matter from a Human Interface Guidelines Markdown file.
        ///
        /// Supports the key-value format `key: value` and `key: "quoted value"`.
        /// Returns an empty dictionary when no front matter block is present.
        ///
        /// - Parameter markdown: Raw Markdown content.
        /// - Returns: A `[String: String]` dictionary of parsed key-value pairs.
        public static func extractHIGMetadata(from markdown: String) -> [String: String] {
            parseFrontMatter(from: markdown)
        }

        /// Parse YAML front matter from an Apple Archive guide Markdown file.
        ///
        /// Supports the key-value format `key: value` and `key: "quoted value"`.
        /// Returns an empty dictionary when no front matter block is present.
        ///
        /// - Parameter markdown: Raw Markdown content.
        /// - Returns: A `[String: String]` dictionary of parsed key-value pairs.
        public static func extractArchiveMetadata(from markdown: String) -> [String: String] {
            parseFrontMatter(from: markdown)
        }

        // MARK: - Framework Synonyms

        /// Known framework name synonyms.
        ///
        /// Maps a canonical framework name to one or more alternate names that should be
        /// indexed alongside it so that searches for either name return the same results.
        private static let frameworkSynonyms: [String: [String]] = [
            "QuartzCore": ["CoreAnimation"],
            "CoreGraphics": ["Quartz2D"],
        ]

        /// Expand `framework` to include any registered synonyms.
        ///
        /// Returns a comma-separated string when synonyms are defined
        /// (e.g., `"QuartzCore, CoreAnimation"`), or the original value otherwise.
        ///
        /// - Parameter framework: The canonical framework name.
        /// - Returns: The framework, possibly extended with comma-separated synonyms.
        public static func expandFrameworkSynonyms(_ framework: String) -> String {
            guard let synonyms = frameworkSynonyms[framework], !synonyms.isEmpty else {
                return framework
            }
            return ([framework] + synonyms).joined(separator: ", ")
        }

        // MARK: - Structured Page Loading

        /// Decode a saved ``Shared/Models/StructuredDocumentationPage`` from a JSON file.
        ///
        /// The decoder is configured with `.iso8601` to match the encoding strategy used
        /// when pages are written by `cupertino fetch`.  Without this, `crawledAt` silently
        /// fails to decode and deduplication falls back to filesystem mtime, which can pick
        /// the wrong file when mtime and `crawledAt` diverge (e.g., after a corpus copy).
        ///
        /// - Parameter file: URL to a `.json` documentation file.
        /// - Returns: The decoded page, or `nil` when the file is not JSON or cannot be parsed.
        public static func loadStructuredPage(from file: URL) -> Shared.Models.StructuredDocumentationPage? {
            guard file.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: file) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(Shared.Models.StructuredDocumentationPage.self, from: data)
        }

        /// Derive the canonical Apple documentation URL for `file`.
        ///
        /// Prefers the `url` field embedded in a JSON ``Shared/Models/StructuredDocumentationPage``.
        /// Falls back to constructing a URL from `docsDirectory` + framework + filename when the
        /// file is Markdown or the JSON decode fails.
        ///
        /// - Parameters:
        ///   - file: The documentation file to inspect.
        ///   - docsDirectory: The root docs directory used for path-based fallback.
        /// - Returns: The canonical URL string, or `nil` when derivation fails.
        public static func canonicalDocumentationURL(for file: URL, docsDirectory: URL) -> String? {
            if let page = loadStructuredPage(from: file) {
                return Shared.Models.URLUtilities.normalize(page.url)?.absoluteString
            }
            guard let rawFramework = extractFrameworkFromPath(file, relativeTo: docsDirectory) else {
                return nil
            }
            let framework = canonicalPathComponent(rawFramework)
            let filename = canonicalPathComponent(file.deletingPathExtension().lastPathComponent)
            return "\(Shared.Constants.BaseURL.appleDeveloperDocs)\(framework)/\(filename)"
        }

        /// Return the crawl date for `file`.
        ///
        /// Reads `crawledAt` from the embedded JSON page when available; falls back to the
        /// filesystem modification date.
        ///
        /// - Parameter file: The documentation file to inspect.
        /// - Returns: The crawl date, or `nil` when neither source is available.
        public static func documentationCrawledAt(for file: URL) -> Date? {
            if let page = loadStructuredPage(from: file) { return page.crawledAt }
            return try? file.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
        }

        /// Deduplicate a list of documentation files by canonical URL, retaining the
        /// most recently crawled version of each page.
        ///
        /// When multiple files share the same canonical URL (e.g., case-axis duplicates
        /// from URL-canonicalization changes), only the file with the newest `crawledAt`
        /// date is kept.  This is the fix for issue #200.
        ///
        /// - Parameters:
        ///   - files: The full list of candidate documentation files.
        ///   - docsDirectory: The root docs directory used for URL derivation.
        /// - Returns: A filtered list with at most one file per canonical URL.
        public static func deduplicateDocFilesByCanonicalURL(
            _ files: [URL],
            docsDirectory: URL
        ) -> [URL] {
            var newestByURL: [String: (file: URL, crawledAt: Date)] = [:]
            for file in files {
                guard let canonicalURL = canonicalDocumentationURL(
                    for: file, docsDirectory: docsDirectory
                ) else { continue }
                let crawledAt = documentationCrawledAt(for: file) ?? .distantPast
                if let existing = newestByURL[canonicalURL], existing.crawledAt >= crawledAt {
                    continue
                }
                newestByURL[canonicalURL] = (file, crawledAt)
            }
            let keptFiles = Set(newestByURL.values.map(\.file))
            return files.filter { keptFiles.contains($0) }
        }

        // MARK: - Error-Page Defences (#284)

        /// Return `true` when `title` looks like an HTTP error template page title.
        ///
        /// Two checks are applied (mirroring the issue #284 spec):
        /// 1. The title starts with a canonical HTTP error code (`403`, `404`, `429`,
        ///    `500`, `502`, `503`, `504`) followed by whitespace or end-of-string.
        /// 2. The title equals one of the standalone Apple CDN error phrases
        ///    (e.g., `"Bad Gateway"`, `"Not Found"`).
        ///
        /// This is the **indexer-side** defence.  The crawler-side gate (PR #289) catches
        /// these at fetch time; this provides belt-and-suspenders protection for stale
        /// on-disk files from pre-#289 crawl runs.
        ///
        /// - Parameter title: The page title to inspect.
        /// - Returns: `true` if the title matches an HTTP error template pattern.
        public static func titleLooksLikeHTTPErrorTemplate(_ title: String) -> Bool {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            if trimmed.range(
                of: #"^(403|404|429|500|502|503|504)(\s|$)"#,
                options: .regularExpression
            ) != nil { return true }
            let standalone: Set = [
                "Forbidden", "Bad Gateway", "Not Found",
                "Service Unavailable", "Gateway Timeout",
                "Too Many Requests", "Internal Server Error",
            ]
            return standalone.contains(trimmed)
        }

        /// Return `true` when `page` looks like Apple's "JavaScript disabled" fallback.
        ///
        /// The fallback page has a real-looking title (Apple includes it in HTML metadata
        /// even when JS is off) but the body contains `"Please turn on JavaScript in your
        /// browser"` or the `"#app-main)# An unknown error occurred"` pattern that the
        /// WebView crawler emits when it cannot render the page.
        ///
        /// Found in 1,327 files in the v1.0.2 corpus; missed by all prior title-only checks.
        ///
        /// - Parameter page: The decoded ``Shared/Models/StructuredDocumentationPage``.
        /// - Returns: `true` if the page should be skipped.
        public static func pageLooksLikeJavaScriptFallback(
            _ page: Shared.Models.StructuredDocumentationPage
        ) -> Bool {
            if let overview = page.overview, overview.contains("Please turn on JavaScript") {
                return true
            }
            if let rawmd = page.rawMarkdown {
                if rawmd.contains("Please turn on JavaScript") { return true }
                if rawmd.contains("#app-main)# An unknown error occurred") { return true }
            }
            return false
        }

        /// Sister to `pageLooksLikeJavaScriptFallback` that operates on
        /// the raw content string instead of a `StructuredDocumentationPage`.
        /// Used by the non-Apple-docs indexer strategies (Swift Evolution,
        /// HIG, Swift.org, Apple Archive) that don't decode to the
        /// structured page shape but still need defence-in-depth against
        /// Apple's WebView crawl mishaps reaching their on-disk corpus
        /// (#429 — same poison-filter coverage everywhere, not just
        /// `indexAppleDocsFromDirectory`).
        ///
        /// Matches the same two signatures the structured-page check
        /// uses:
        ///   - `"Please turn on JavaScript"` (Apple's JS-disabled
        ///     fallback prose)
        ///   - `"#app-main)# An unknown error occurred"` (WebView render
        ///     failure marker the crawler emits when it can't draw the
        ///     page)
        ///
        /// - Parameter content: The raw page body the indexer is about
        ///   to write into the FTS index.
        /// - Returns: `true` if the content matches a JS-fallback signature.
        public static func contentLooksLikeJavaScriptFallback(_ content: String) -> Bool {
            if content.contains("Please turn on JavaScript") { return true }
            if content.contains("#app-main)# An unknown error occurred") { return true }
            return false
        }

        // MARK: - #588 door equivalence (tier A / B / C)

        /// Per-run record of a URI the indexer has already accepted.
        ///
        /// The strategy keeps a `[String: SeenURIRecord]` map as it walks
        /// the corpus. Each subsequent same-URI encounter is classified
        /// against the prior record via ``classifyDoorEncounter(prior:incoming:)``
        /// so the indexer never silently double-inserts and never silently
        /// drops a row whose content differs from what it collided with
        /// (`docs/PRINCIPLES.md` principle 3).
        public struct SeenURIRecord: Sendable, Equatable {
            /// Title after ``canonicalTitleForEquivalence(_:)`` normalization.
            public let canonicalTitle: String
            /// SHA-256 over the doc's content (as recorded by the crawler).
            public let contentHash: String

            public init(canonicalTitle: String, contentHash: String) {
                self.canonicalTitle = canonicalTitle
                self.contentHash = contentHash
            }
        }

        /// Result of comparing a new same-URI encounter against the prior
        /// record. Used by the strategy's door check to decide whether to
        /// INSERT, skip silently, or surface as a collision.
        ///
        /// - `firstArrival`: the URI hasn't been seen this run; the caller
        ///   records the URI and proceeds to INSERT.
        /// - `benignByteIdentical` (tier A): identical content hash;
        ///   provably the same bytes; silent skip.
        /// - `benignTitleMatchWithDrift` (tier B): same canonical title,
        ///   different content hash; same logical Apple page rendered
        ///   slightly differently between crawls (Apple's case-insensitive
        ///   routing guarantees same URI = same page); first-arrived
        ///   stays in the index, drift logged.
        /// - `malignantTitleMismatch` (tier C): different canonical title;
        ///   the URI canonicalization conflated two distinct Apple pages;
        ///   surface as a collision; **`DoD = 0 tier-C`** per `docs/PRINCIPLES.md`.
        public enum DoorClassification: Sendable, Equatable {
            case firstArrival
            case benignByteIdentical
            case benignTitleMatchWithDrift
            case malignantTitleMismatch
        }

        /// Normalize a page title for door-time equivalence comparison.
        ///
        /// Steps applied (deterministic Swift only, no AI):
        ///
        /// 1. HTML-entity decode (`&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`)
        ///    so Apple's renderer encoding doesn't make two byte-equal
        ///    titles compare unequal.
        /// 2. Strip the site-wide trailing `" | Apple Developer Documentation"`
        ///    suffix that some crawler paths capture.
        /// 3. Lowercase.
        /// 4. Collapse internal whitespace runs to single spaces.
        /// 5. Trim leading / trailing whitespace.
        ///
        /// Two titles compare equal under door equivalence iff their
        /// canonical forms are exactly equal.
        public static func canonicalTitleForEquivalence(_ title: String) -> String {
            var working = title
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
            let suffix = " | Apple Developer Documentation"
            if working.hasSuffix(suffix) {
                working = String(working.dropLast(suffix.count))
            }
            working = working.lowercased()
            working = working
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return working
        }

        /// Classify a same-URI encounter at the door.
        ///
        /// Pure function: same inputs always produce the same output, no
        /// I/O, no shared state. Exposed for unit tests.
        ///
        /// - Parameters:
        ///   - prior: The record stored for this URI on first arrival.
        ///   - incoming: The record we just constructed for the new encounter.
        /// - Returns: The classification per `docs/PRINCIPLES.md` principle 3.
        public static func classifyDoorEncounter(
            prior: SeenURIRecord,
            incoming: SeenURIRecord
        ) -> DoorClassification {
            if !prior.contentHash.isEmpty,
               !incoming.contentHash.isEmpty,
               prior.contentHash == incoming.contentHash {
                return .benignByteIdentical
            }
            if prior.canonicalTitle == incoming.canonicalTitle {
                return .benignTitleMatchWithDrift
            }
            return .malignantTitleMismatch
        }

        /// Return `true` when `title` is a placeholder shed by Apple's web app
        /// in lieu of the real document title.
        ///
        /// Three patterns are caught:
        ///
        /// 1. Empty / whitespace-only title.
        /// 2. Bare `"Apple Developer Documentation"` (case-insensitive) —
        ///    the site-wide HTML `<title>` element when the page-specific
        ///    title hasn't loaded yet. No real Apple symbol is named that.
        /// 3. Bare `"Error"` (case-insensitive, whitespace-tolerant), but
        ///    **only when the URL's last path component is not itself
        ///    named `error`**. This is the disambiguation `cupertino save
        ///    --dry-run` against the canonical corpus revealed: Apple
        ///    legitimately ships enum cases / properties named `error`
        ///    (e.g. `StoreKit/ProductIconPhase/error`,
        ///    `SKPaymentTransaction/error`, `SKDownload/error`) with the
        ///    page title `"Error"`. Those are real symbols, not poison.
        ///    The poison case is title `"Error"` at a URL whose leaf is
        ///    something unrelated (e.g.
        ///    `PDFKit/PDFViewDelegate/pdfViewParentViewController()`)
        ///    because Apple's JS app failed mid-render and emitted the
        ///    string `"Error"` as the title.
        ///
        /// When `url` is `nil` the caller has no context, so the gate
        /// **passes** `"Error"` through (does not reject) — the door
        /// equivalence check downstream will still flag it as tier C
        /// if it conflicts with another page at the same URI, but we
        /// won't drop a potentially legitimate symbol blind.
        ///
        /// The audit at issue #588 found these patterns hiding behind
        /// the existing #284 filters: `titleLooksLikeHTTPErrorTemplate`
        /// matches HTTP status names, not the bare "Error" string, and
        /// `pageLooksLikeJavaScriptFallback` checks the body but not the
        /// title.
        ///
        /// - Parameters:
        ///   - title: The page title to inspect.
        ///   - url: The page's source URL. Pass the actual URL whenever
        ///     possible so a real `error` enum case isn't mis-classified
        ///     as a placeholder. Defaults to `nil` for callers (and tests)
        ///     that don't have it.
        /// - Returns: `true` if the title is a placeholder; indexer should skip.
        public static func titleLooksLikePlaceholderError(_ title: String, url: URL? = nil) -> Bool {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.isEmpty { return true }
            if trimmed == "apple developer documentation" { return true }
            if trimmed == "error" {
                guard let url else {
                    // No URL context — be conservative, don't reject
                    // (downstream tier-C check still surfaces conflicts).
                    return false
                }
                // Apple's slug for an enum case named `error` is literally
                // "error" (or "error()" for parameterless method-like
                // shapes). Strip trailing parens before comparing.
                let leaf = url.lastPathComponent
                    .lowercased()
                    .replacingOccurrences(of: "()", with: "")
                return leaf != "error"
            }
            return false
        }

        /// Return `true` when `title` and `content` indicate a 404 error page.
        ///
        /// Three checks are applied:
        /// 1. Title is exactly `"not found"` (case-insensitive) or contains `"404"`.
        /// 2. Content contains an unambiguous 404 phrase.
        /// 3. The weaker phrase `"page not found"` only triggers on short pages (< 500 chars)
        ///    to avoid false-positives on Swift Book content that discusses error handling.
        ///
        /// - Parameters:
        ///   - title: The page title.
        ///   - content: The page body.
        /// - Returns: `true` if the page is a 404 error page.
        public static func is404Page(title: String, content: String) -> Bool {
            let lowerTitle = title.lowercased()
            if lowerTitle == "not found" || lowerTitle.contains("404") { return true }
            let lowerContent = content.lowercased()
            if lowerContent.contains("the requested url was not found") ||
                lowerContent.contains("404 not found") { return true }
            if content.count < 500, lowerContent.contains("page not found") { return true }
            return false
        }

        // MARK: - Private Helpers

        /// Parse a YAML front-matter block from Markdown content.
        ///
        /// Handles `key: value` and `key: "quoted value"` formats.
        private static func parseFrontMatter(from markdown: String) -> [String: String] {
            var metadata: [String: String] = [:]
            guard markdown.hasPrefix("---") else { return metadata }
            guard let endRange = markdown.range(
                of: "\n---",
                range: markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex
            ) else { return metadata }

            let frontMatter = String(
                markdown[markdown.index(markdown.startIndex, offsetBy: 4)..<endRange.lowerBound]
            )
            for line in frontMatter.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                metadata[key] = value
            }
            return metadata
        }
    }
}
