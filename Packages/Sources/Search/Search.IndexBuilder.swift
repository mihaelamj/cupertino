import Core
import CoreJSONParser
import CoreProtocols
import Foundation
import Logging
import SharedConstants
import SharedCore
import SharedModels
import SearchModels

// MARK: - Search Index Builder

// swiftlint:disable type_body_length file_length
// Justification: IndexBuilder orchestrates the complete search index building process.
// It handles: documentation parsing, FTS5 indexing, availability data, statistics, and progress tracking.
// The actor manages state across multiple indexing stages that must be coordinated atomically.

/// Builds search index from crawled documentation
extension Search {
    public actor IndexBuilder {
        private let searchIndex: Search.Index
        private let metadata: Shared.Models.CrawlMetadata?
        private let docsDirectory: URL
        private let evolutionDirectory: URL?
        private let swiftOrgDirectory: URL?
        private let archiveDirectory: URL?
        private let higDirectory: URL?
        private let indexSampleCode: Bool

        public init(
            searchIndex: Search.Index,
            metadata: Shared.Models.CrawlMetadata?,
            docsDirectory: URL,
            evolutionDirectory: URL? = nil,
            swiftOrgDirectory: URL? = nil,
            archiveDirectory: URL? = nil,
            higDirectory: URL? = nil,
            indexSampleCode: Bool = true
        ) {
            self.searchIndex = searchIndex
            self.metadata = metadata
            self.docsDirectory = docsDirectory
            self.evolutionDirectory = evolutionDirectory
            self.swiftOrgDirectory = swiftOrgDirectory
            self.archiveDirectory = archiveDirectory
            self.higDirectory = higDirectory
            self.indexSampleCode = indexSampleCode
        }

        // MARK: - Build Index

        /// Build search index from all crawled documents
        public func buildIndex(
            clearExisting: Bool = true,
            onProgress: (@Sendable (Int, Int) -> Void)? = nil
        ) async throws {
            logInfo("🔨 Building search index...")

            // Clear existing index if requested
            if clearExisting {
                try await searchIndex.clearIndex()
                logInfo("   Cleared existing index")
            }

            // Index Apple Documentation
            try await indexAppleDocs(onProgress: onProgress)

            // Index Swift Evolution proposals if available
            if evolutionDirectory != nil {
                try await indexEvolutionProposals(onProgress: onProgress)
            }

            // Index Swift.org documentation if available
            if swiftOrgDirectory != nil {
                try await indexSwiftOrgDocs(onProgress: onProgress)
            }

            // Index Apple Archive documentation if available
            if archiveDirectory != nil {
                try await indexArchiveDocs(onProgress: onProgress)
            }

            // Index Human Interface Guidelines if available
            if higDirectory != nil {
                try await indexHIGDocs(onProgress: onProgress)
            }

            // Index Sample Code catalog if requested
            if indexSampleCode {
                try await indexSampleCodeCatalog(onProgress: onProgress)
            }

            // Index Swift Packages catalog
            try await indexPackagesCatalog(onProgress: onProgress)

            // Register framework synonyms for common alternate names
            try await registerFrameworkSynonyms()

            let count = try await searchIndex.documentCount()
            logInfo("✅ Search index built: \(count) documents")
        }

        /// Register synonyms so common alternate names resolve to the correct framework
        private func registerFrameworkSynonyms() async throws {
            let synonyms: [(identifier: String, synonyms: String)] = [
                ("corenfc", "nfc"),
                ("journalingsuggestions", "journaling"),
                ("corebluetooth", "bluetooth"),
                ("corelocation", "location"),
                ("coredata", "data"),
                ("coremotion", "motion"),
                ("coregraphics", "graphics"),
                ("coreimage", "imageprocessing"),
                ("coremedia", "media"),
                ("coreaudio", "audio"),
                ("coreml", "ml,machinelearning"),
                ("corespotlight", "spotlight"),
                ("coretext", "text"),
                ("corevideo", "video"),
                ("corehaptics", "haptics"),
                ("corewlan", "wifi,wlan"),
                ("coretelephony", "telephony"),
                ("metalperformanceshadersgraph", "mpsgraph"),
                ("avfoundation", "av"),
                ("scenekit", "scene"),
                ("spritekit", "sprite"),
                ("groupactivities", "shareplay"),
            ]

            for entry in synonyms {
                try await searchIndex.updateFrameworkSynonyms(
                    identifier: entry.identifier,
                    synonyms: entry.synonyms
                )
            }
        }

        // MARK: - Private Methods

        private func indexAppleDocs(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            // Always scan directory - metadata is for fetching, not indexing
            try await indexAppleDocsFromDirectory(onProgress: onProgress)
        }

        /// `internal` rather than `private` so SearchTests can exercise the
        /// metadata-driven indexing path (including the malformed-URL skip
        /// branch added in PR #288) without needing to bootstrap the whole
        /// `buildIndex()` orchestration.
        func indexAppleDocsFromMetadata(
            metadata: Shared.Models.CrawlMetadata,
            onProgress: (@Sendable (Int, Int) -> Void)?
        ) async throws {
            let total = metadata.pages.count
            guard total > 0 else {
                logInfo("⚠️  No Apple documentation found in metadata")
                return
            }

            logInfo("📚 Indexing \(total) Apple documentation pages from metadata...")

            var processed = 0
            var indexed = 0
            var skipped = 0

            for (url, pageMetadata) in metadata.pages {
                // Read markdown file
                let filePath = URL(fileURLWithPath: pageMetadata.filePath)

                guard FileManager.default.fileExists(atPath: filePath.path) else {
                    skipped += 1
                    processed += 1
                    continue
                }

                guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
                    skipped += 1
                    processed += 1
                    continue
                }

                // `url` comes from indexed page metadata; if a row's key
                // doesn't parse as a URL we skip the doc instead of crashing
                // the whole index build.
                guard let parsedURL = URL(string: url) else {
                    skipped += 1
                    processed += 1
                    continue
                }

                // Extract title from front matter or first heading
                let title = extractTitle(from: content) ?? Shared.Models.URLUtilities.filename(from: parsedURL)

                // Build URI
                let uri = "apple-docs://\(pageMetadata.framework)/\(Shared.Models.URLUtilities.filename(from: parsedURL))"

                // Index document (Apple docs from /docs folder)
                do {
                    try await searchIndex.indexDocument(Search.Index.IndexDocumentParams(
                        uri: uri,
                        source: Shared.Constants.SourcePrefix.appleDocs,
                        framework: pageMetadata.framework,
                        title: title,
                        content: content,
                        filePath: pageMetadata.filePath,
                        contentHash: pageMetadata.contentHash,
                        lastCrawled: pageMetadata.lastCrawled,
                    ))
                    indexed += 1
                } catch {
                    logError("Failed to index \(uri): \(error)")
                    skipped += 1
                }

                processed += 1

                if processed % 100 == 0 {
                    onProgress?(processed, total)
                    logInfo("   Progress: \(processed)/\(total) (\(indexed) indexed, \(skipped) skipped)")
                }
            }

            logInfo("   Apple Docs: \(indexed) indexed, \(skipped) skipped")
        }

        private func indexAppleDocsFromDirectory(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            guard FileManager.default.fileExists(atPath: docsDirectory.path) else {
                logInfo("⚠️  Docs directory not found: \(docsDirectory.path)")
                return
            }

            logInfo("📂 Scanning directory for documentation (no metadata.json)...")

            // Recursively find all .json and .md files (JSON preferred over MD).
            // The dedup helper collapses case-axis duplicates by canonical URL.
            let docFiles = try deduplicateDocFilesByCanonicalURL(Self.findDocFiles(in: docsDirectory))

            guard !docFiles.isEmpty else {
                logInfo("⚠️  No documentation files found in \(docsDirectory.path)")
                return
            }

            logInfo("📚 Indexing \(docFiles.count) documentation pages from directory...")

            var indexed = 0
            var skipped = 0

            for (index, file) in docFiles.enumerated() {
                // Extract framework from path: docs/{framework}/...
                guard let rawFramework = extractFrameworkFromPath(file, relativeTo: docsDirectory) else {
                    logError("Could not extract framework from path: \(file.path) (relative to \(docsDirectory.path))")
                    skipped += 1
                    continue
                }
                let framework = canonicalPathComponent(rawFramework)

                // Always work with StructuredDocumentationPage
                let structuredPage: Shared.Models.StructuredDocumentationPage
                let jsonString: String

                if file.pathExtension == "json" {
                    // JSON format: decode directly
                    do {
                        let jsonData = try Data(contentsOf: file)
                        jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        structuredPage = try decoder.decode(Shared.Models.StructuredDocumentationPage.self, from: jsonData)
                    } catch {
                        logError("Failed to decode \(file.lastPathComponent): \(error)")
                        skipped += 1
                        continue
                    }
                } else {
                    // Markdown format: convert to StructuredDocumentationPage
                    guard let mdContent = try? String(contentsOf: file, encoding: .utf8) else {
                        skipped += 1
                        continue
                    }

                    let pageURL = URL(string: "\(Shared.Constants.BaseURL.appleDeveloperDocs)\(framework)/\(file.deletingPathExtension().lastPathComponent)")
                    guard let converted = Core.JSONParser.MarkdownToStructuredPage.convert(mdContent, url: pageURL) else {
                        logError("Failed to convert \(file.lastPathComponent) to structured page")
                        skipped += 1
                        continue
                    }
                    structuredPage = converted

                    // Encode to JSON
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    guard let jsonData = try? encoder.encode(structuredPage),
                          let json = String(data: jsonData, encoding: .utf8) else {
                        logError("Failed to encode \(file.lastPathComponent) to JSON")
                        skipped += 1
                        continue
                    }
                    jsonString = json
                }

                // Defense-in-depth: refuse to index any page whose title looks
                // like an HTTP error template (502 Bad Gateway, 403 Forbidden,
                // etc.). The crawler-side filter (#284 / PR #289) catches
                // these at fetch time, but stray poison files can land on disk
                // via mid-flight rsync from a pre-#284 binary, restored
                // backups, or hand-edited corpora. Skipping at index time
                // keeps the bundle clean by construction regardless of how
                // the file got onto disk.
                if Self.titleLooksLikeHTTPErrorTemplate(structuredPage.title) {
                    logError(
                        "⛔ Skipping HTTP-error-template page (#284 indexer defense): " +
                            "title=\(structuredPage.title.prefix(60)) file=\(file.lastPathComponent)"
                    )
                    skipped += 1
                    continue
                }
                if Self.pageLooksLikeJavaScriptFallback(structuredPage) {
                    logError(
                        "⛔ Skipping JS-disabled-fallback page (#284 indexer defense): " +
                            "title=\(structuredPage.title.prefix(60)) file=\(file.lastPathComponent)"
                    )
                    skipped += 1
                    continue
                }

                // Generate URI: apple-docs://{framework}/{filename}
                let filename = Shared.Models.URLUtilities.normalize(structuredPage.url)?.lastPathComponent
                    ?? canonicalPathComponent(file.deletingPathExtension().lastPathComponent)
                let uri = "apple-docs://\(framework)/\(filename)"

                // Index using indexStructuredDocument (Apple docs from /docs folder)
                do {
                    try await searchIndex.indexStructuredDocument(
                        uri: uri,
                        source: Shared.Constants.SourcePrefix.appleDocs,
                        framework: framework,
                        page: structuredPage,
                        jsonData: jsonString
                    )

                    // Index code examples if present (#192 D: also extract AST
                    // symbols into doc_symbols / doc_imports and the
                    // denormalised docs_metadata.symbols blob).
                    if !structuredPage.codeExamples.isEmpty {
                        let examples = structuredPage.codeExamples.map {
                            (code: $0.code, language: $0.language ?? "swift")
                        }
                        try await searchIndex.indexCodeExamples(
                            docUri: uri,
                            codeExamples: examples
                        )
                        try await searchIndex.extractCodeExampleSymbols(
                            docUri: uri,
                            codeExamples: examples
                        )
                    }

                    indexed += 1
                } catch {
                    logError("Failed to index \(uri): \(error)")
                    skipped += 1
                }

                if (index + 1) % 100 == 0 {
                    onProgress?(index + 1, docFiles.count)
                    logInfo("   Progress: \(index + 1)/\(docFiles.count) (\(indexed) indexed, \(skipped) skipped)")
                }
            }

            logInfo("   Directory scan: \(indexed) indexed, \(skipped) skipped")
        }

        /// Pure filesystem scan. Static so tests can exercise the crawl-manifest
        /// filter (fix for #110) without spinning up the full actor.
        static func findDocFiles(in directory: URL) throws -> [URL] {
            var jsonFiles: Set<String> = [] // Track JSON filenames to skip duplicate MDs
            var docFiles: [URL] = []

            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return docFiles
            }

            // First pass: collect all files
            var allFiles: [URL] = []
            while let element = enumerator.nextObject() {
                guard let fileURL = element as? URL else { continue }
                let ext = fileURL.pathExtension.lowercased()
                guard ext == "json" || ext == "md" else { continue }

                // Skip crawl-manifest files (fix for #110): `metadata.json` sits inside
                // source roots (e.g. ~/.cupertino/swift-org/metadata.json) but is not a
                // documentation page, and lacks the `url` key required by
                // StructuredDocumentationPage. Treating it as a doc produces a
                // keyNotFound decode error and a skipped-file count that confuses users.
                if fileURL.lastPathComponent == "metadata.json" {
                    continue
                }

                // Use FileManager to check if it's a file (more reliable than resourceValues)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                   !isDirectory.boolValue {
                    allFiles.append(fileURL)
                }
            }

            // Second pass: prefer JSON over MD for same filename.
            // Process JSONs first so `jsonFiles` is fully populated before MDs are
            // considered; FileManager.enumerator ordering is not guaranteed, which
            // previously allowed MDs to slip through when they came first.
            for file in allFiles where file.pathExtension.lowercased() == "json" {
                let basename = file.deletingPathExtension().lastPathComponent
                let dir = file.deletingLastPathComponent().path
                jsonFiles.insert("\(dir)/\(basename)")
                docFiles.append(file)
            }
            for file in allFiles where file.pathExtension.lowercased() == "md" {
                let basename = file.deletingPathExtension().lastPathComponent
                let dir = file.deletingLastPathComponent().path
                if !jsonFiles.contains("\(dir)/\(basename)") {
                    docFiles.append(file)
                }
            }

            return docFiles
        }

        func deduplicateDocFilesByCanonicalURL(_ files: [URL]) throws -> [URL] {
            var newestByURL: [String: (file: URL, crawledAt: Date)] = [:]

            for file in files {
                guard let canonicalURL = canonicalDocumentationURL(for: file) else {
                    continue
                }

                let crawledAt = documentationCrawledAt(for: file) ?? .distantPast
                if let existing = newestByURL[canonicalURL], existing.crawledAt >= crawledAt {
                    continue
                }

                newestByURL[canonicalURL] = (file, crawledAt)
            }

            let keptFiles = Set(newestByURL.values.map(\.file))
            return files.filter { keptFiles.contains($0) }
        }

        /// Read and decode a saved StructuredDocumentationPage. Configures the
        /// decoder with `.iso8601` to match how `cupertino fetch` writes
        /// `crawledAt`; without this the decode silently fails on every real
        /// Apple-doc JSON file and the dedup primary path becomes dead code.
        /// See `indexStructuredDocument` for the canonical decoder config.
        func loadStructuredPage(from file: URL) -> Shared.Models.StructuredDocumentationPage? {
            guard file.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: file) else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(Shared.Models.StructuredDocumentationPage.self, from: data)
        }

        func canonicalDocumentationURL(for file: URL) -> String? {
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

        func documentationCrawledAt(for file: URL) -> Date? {
            if let page = loadStructuredPage(from: file) {
                return page.crawledAt
            }

            return try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        /// Lowercase-only canonicalization. Mirrors `URLUtilities.normalize`
        /// which deliberately does NOT collapse underscore→dash because
        /// at least one Apple framework (`installer_js`) legitimately uses
        /// underscore in its path and Apple does not redirect from the dash
        /// form (verified: `documentation/installer-js` returns 404).
        private func canonicalPathComponent(_ component: String) -> String {
            component.lowercased()
        }

        private func findMarkdownFiles(in directory: URL) throws -> [URL] {
            var markdownFiles: [URL] = []

            if let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    guard fileURL.pathExtension == "md" else { continue }

                    let attributes = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if attributes?.isRegularFile == true {
                        markdownFiles.append(fileURL)
                    }
                }
            }

            return markdownFiles
        }

        private func extractFrameworkFromPath(_ file: URL, relativeTo baseDir: URL) -> String? {
            // Standardize both paths to handle /private/var vs /var symlink issues
            let basePath = baseDir.standardizedFileURL.path
            let filePath = file.standardizedFileURL.path

            guard filePath.hasPrefix(basePath) else {
                return nil
            }

            // Remove base path and leading slash
            let relativePath = String(filePath.dropFirst(basePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // Extract first path component as framework
            let components = relativePath.split(separator: "/")
            guard let framework = components.first else {
                return nil
            }

            return String(framework)
        }

        private func indexEvolutionProposals(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            guard let evolutionDirectory else {
                return
            }

            guard FileManager.default.fileExists(atPath: evolutionDirectory.path) else {
                logInfo("⚠️  Swift Evolution directory not found: \(evolutionDirectory.path)")
                return
            }

            let proposalFiles = try getProposalFiles(from: evolutionDirectory)

            guard !proposalFiles.isEmpty else {
                logInfo("⚠️  No Swift Evolution proposals found")
                return
            }

            logInfo("📋 Indexing \(proposalFiles.count) Swift Evolution proposals...")

            var indexed = 0
            var skipped = 0

            for (index, file) in proposalFiles.enumerated() {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    skipped += 1
                    continue
                }

                // Only index accepted/implemented proposals
                let status = extractProposalStatus(from: content)
                guard isAcceptedProposal(status) else {
                    skipped += 1
                    continue
                }

                do {
                    try await indexProposal(file: file, content: content)
                    indexed += 1
                } catch {
                    logError("Failed to index \(file.lastPathComponent): \(error)")
                    skipped += 1
                }

                if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    logInfo("   Progress: \(index + 1)/\(proposalFiles.count)")
                }
            }

            logInfo("   Swift Evolution: \(indexed) indexed, \(skipped) skipped")
        }

        func getProposalFiles(from directory: URL) throws -> [URL] {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            return files.filter {
                $0.pathExtension == "md" &&
                    ($0.lastPathComponent.hasPrefix(Shared.Constants.Search.sePrefix) ||
                        $0.lastPathComponent.hasPrefix(Shared.Constants.Search.stPrefix))
            }
        }

        private func indexProposal(file: URL, content: String) async throws {
            let filename = file.deletingPathExtension().lastPathComponent
            let proposalID = extractProposalID(from: filename) ?? filename
            let title = extractTitle(from: content) ?? proposalID
            let uri = "swift-evolution://\(proposalID)"

            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            let modDate = attributes?[.modificationDate] as? Date ?? Date()
            let contentHash = Shared.Models.HashUtilities.sha256(of: content)

            // Extract Swift version from status and map to iOS/macOS
            let status = extractProposalStatus(from: content)
            let availability = mapSwiftVersionToAvailability(status)

            // Swift Evolution source - no framework, just source
            try await searchIndex.indexDocument(Search.Index.IndexDocumentParams(
                uri: uri,
                source: Shared.Constants.SourcePrefix.swiftEvolution,
                framework: nil,
                title: title,
                content: content,
                filePath: file.path,
                contentHash: contentHash,
                lastCrawled: modDate,
                minIOS: availability.iOS,
                minMacOS: availability.macOS,
                availabilitySource: availability.iOS != nil ? "swift-version" : nil,
            ))
        }

        /// Map Swift version to iOS/macOS availability
        /// Based on: https://swiftversion.net
        private func mapSwiftVersionToAvailability(_ status: String?) -> (iOS: String?, macOS: String?) {
            guard let status else { return (nil, nil) }

            // Extract Swift version from status like "Implemented (Swift 5.5)"
            let pattern = #"Swift\s+(\d+(?:\.\d+)?)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: status, range: NSRange(status.startIndex..., in: status)),
                  match.numberOfRanges > 1,
                  let versionRange = Range(match.range(at: 1), in: status)
            else {
                return (nil, nil)
            }

            let swiftVersion = String(status[versionRange])
            let major = swiftVersion.split(separator: ".").first.flatMap { Int($0) } ?? 0
            let minor = swiftVersion.split(separator: ".").dropFirst().first.flatMap { Int($0) } ?? 0

            // Swift version to iOS/macOS mapping
            switch (major, minor) {
            case (6, _):
                return ("18.0", "15.0")
            case (5, 10):
                return ("17.4", "14.4")
            case (5, 9):
                return ("17.0", "14.0")
            case (5, 8):
                return ("16.4", "13.3")
            case (5, 7):
                return ("16.0", "13.0")
            case (5, 6):
                return ("15.4", "12.3")
            case (5, 5):
                return ("15.0", "12.0")
            case (5, 4):
                return ("14.5", "11.3")
            case (5, 3):
                return ("14.0", "11.0")
            case (5, 2):
                return ("13.4", "10.15.4")
            case (5, 1):
                return ("13.0", "10.15")
            case (5, 0):
                return ("12.2", "10.14.4")
            case (4, 2):
                return ("12.0", "10.14")
            case (4, 1):
                return ("11.3", "10.13.4")
            case (4, 0):
                return ("11.0", "10.13")
            case (3, _):
                return ("10.0", "10.12")
            case (2, _):
                return ("9.0", "10.11")
            default:
                // Swift 1.x or unknown
                return ("8.0", "10.9")
            }
        }

        /// Extract status from Swift Evolution proposal markdown
        func extractProposalStatus(from markdown: String) -> String? {
            // Format: "* Status: **Implemented (Swift 2.2)**" or "* Status: **Accepted**"
            guard let regex = try? NSRegularExpression(pattern: Shared.Constants.Pattern.seStatus),
                  let match = regex.firstMatch(
                      in: markdown,
                      range: NSRange(markdown.startIndex..., in: markdown)
                  ),
                  match.numberOfRanges > 1,
                  let statusRange = Range(match.range(at: 1), in: markdown)
            else {
                return nil
            }
            return String(markdown[statusRange])
        }

        /// Check if proposal status indicates it was accepted/implemented
        func isAcceptedProposal(_ status: String?) -> Bool {
            guard let status = status?.lowercased() else {
                return false
            }
            // Accept proposals that are "Implemented", "Accepted", or "Accepted with revisions"
            return status.contains("implemented") || status.contains("accepted")
        }

        /// Check if a page is a 404 error page. Pure; exposed `static` for direct unit testing.
        ///
        /// Heuristic (fix for #110):
        /// - Strong title signals (exact "not found" or contains "404") → 404.
        /// - Unambiguous content phrases ("the requested url was not found", "404 not found") → 404.
        /// - The weaker phrase "page not found" only flips the verdict on short pages
        ///   (< 500 chars), because real documentation can discuss that phrase in prose
        ///   about error handling. Swift Book's "The Basics" pages were being misflagged.
        static func is404Page(title: String, content: String) -> Bool {
            let lowerTitle = title.lowercased()
            if lowerTitle == "not found" || lowerTitle.contains("404") {
                return true
            }

            let lowerContent = content.lowercased()
            if lowerContent.contains("the requested url was not found") ||
                lowerContent.contains("404 not found") {
                return true
            }

            if content.count < 500, lowerContent.contains("page not found") {
                return true
            }

            return false
        }

        // MARK: - Swift.org Documentation

        private func indexSwiftOrgDocs(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            guard let swiftOrgDirectory else {
                return
            }

            guard FileManager.default.fileExists(atPath: swiftOrgDirectory.path) else {
                logInfo("⚠️  Swift.org directory not found: \(swiftOrgDirectory.path)")
                return
            }

            // Use findDocFiles to handle both .json and .md files (same as Apple docs)
            let docFiles = try Self.findDocFiles(in: swiftOrgDirectory)

            guard !docFiles.isEmpty else {
                logInfo("⚠️  No Swift.org documentation found")
                return
            }

            logInfo("🔶 Indexing \(docFiles.count) Swift.org documentation pages...")

            var indexed = 0
            var skipped = 0

            for (index, file) in docFiles.enumerated() {
                // Extract source from path: swift-org/{source}/... (swift-book or swift-org)
                let source = extractFrameworkFromPath(file, relativeTo: swiftOrgDirectory)
                    ?? Shared.Constants.SourcePrefix.swiftOrg

                // Handle JSON and MD files (same pattern as Apple docs)
                let structuredPage: Shared.Models.StructuredDocumentationPage
                let jsonString: String

                if file.pathExtension == "json" {
                    // JSON format: decode directly
                    do {
                        let jsonData = try Data(contentsOf: file)
                        jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        structuredPage = try decoder.decode(Shared.Models.StructuredDocumentationPage.self, from: jsonData)
                    } catch {
                        logError("Failed to decode \(file.lastPathComponent): \(error)")
                        skipped += 1
                        continue
                    }
                } else {
                    // Markdown format: convert to StructuredDocumentationPage
                    guard let mdContent = try? String(contentsOf: file, encoding: .utf8) else {
                        skipped += 1
                        continue
                    }

                    let pageURL = URL(string: "https://www.swift.org/documentation/\(file.deletingPathExtension().lastPathComponent)")
                    guard let converted = Core.JSONParser.MarkdownToStructuredPage.convert(mdContent, url: pageURL) else {
                        logError("Failed to convert \(file.lastPathComponent) to structured page")
                        skipped += 1
                        continue
                    }
                    structuredPage = converted

                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    guard let jsonData = try? encoder.encode(structuredPage),
                          let json = String(data: jsonData, encoding: .utf8) else {
                        logError("Failed to encode \(file.lastPathComponent) to JSON")
                        skipped += 1
                        continue
                    }
                    jsonString = json
                }

                // Skip 404/error pages
                let title = structuredPage.title
                let content = structuredPage.rawMarkdown ?? structuredPage.overview ?? ""
                if Self.is404Page(title: title, content: content) {
                    skipped += 1
                    continue
                }

                // Generate URI: {source}://{filename}
                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "\(source)://\(filename)"

                do {
                    // Use source as framework for swift-org (swift-book or swift-org)
                    // swift-book is universal language documentation (all platforms with Swift support)
                    let isSwiftBook = source == "swift-book"
                    try await searchIndex.indexStructuredDocument(
                        uri: uri,
                        source: source,
                        framework: source,
                        page: structuredPage,
                        jsonData: jsonString,
                        overrideMinIOS: isSwiftBook ? "8.0" : nil,
                        overrideMinMacOS: isSwiftBook ? "10.9" : nil,
                        overrideMinTvOS: isSwiftBook ? "9.0" : nil,
                        overrideMinWatchOS: isSwiftBook ? "2.0" : nil,
                        overrideMinVisionOS: isSwiftBook ? "1.0" : nil,
                        overrideAvailabilitySource: isSwiftBook ? "universal" : nil
                    )

                    // Index code examples if present (#192 D: also extract AST
                    // symbols into doc_symbols / doc_imports and the
                    // denormalised docs_metadata.symbols blob).
                    if !structuredPage.codeExamples.isEmpty {
                        let examples = structuredPage.codeExamples.map {
                            (code: $0.code, language: $0.language ?? "swift")
                        }
                        try await searchIndex.indexCodeExamples(
                            docUri: uri,
                            codeExamples: examples
                        )
                        try await searchIndex.extractCodeExampleSymbols(
                            docUri: uri,
                            codeExamples: examples
                        )
                    }

                    indexed += 1
                } catch {
                    logError("Failed to index \(uri): \(error)")
                    skipped += 1
                }

                if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    logInfo("   Progress: \(index + 1)/\(docFiles.count)")
                }
            }

            logInfo("   Swift.org: \(indexed) indexed, \(skipped) skipped")
        }

        // MARK: - Apple Archive Documentation

        private func indexArchiveDocs(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            guard let archiveDirectory else {
                return
            }

            guard FileManager.default.fileExists(atPath: archiveDirectory.path) else {
                logInfo("⚠️  Archive directory not found: \(archiveDirectory.path)")
                return
            }

            let markdownFiles = try findMarkdownFiles(in: archiveDirectory)

            guard !markdownFiles.isEmpty else {
                logInfo("⚠️  No Apple Archive documentation found")
                return
            }

            logInfo("📜 Indexing \(markdownFiles.count) Apple Archive documentation pages...")

            var indexed = 0
            var skipped = 0

            // Cache framework availability lookups
            var frameworkAvailabilityCache: [String: FrameworkAvailability] = [:]

            for (index, file) in markdownFiles.enumerated() {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    skipped += 1
                    continue
                }

                // Extract guide ID (book UID) from path: archive/{guideUID}/...
                let guideID = extractFrameworkFromPath(file, relativeTo: archiveDirectory) ?? "unknown"

                // Extract metadata from front matter
                let metadata = extractArchiveMetadata(from: content)
                let title = metadata["title"] ?? extractTitle(from: content) ?? file.deletingPathExtension().lastPathComponent
                let bookTitle = metadata["book"] ?? guideID
                // Use framework field if available, otherwise fall back to book title
                let baseFramework = metadata["framework"] ?? bookTitle
                // Expand framework synonyms (e.g., QuartzCore -> QuartzCore, CoreAnimation)
                let framework = expandFrameworkSynonyms(baseFramework)

                // Generate URI: apple-archive://{guideID}/{filename}
                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "apple-archive://\(guideID)/\(filename)"

                // Calculate content hash
                let contentHash = Shared.Models.HashUtilities.sha256(of: content)

                // Use file modification date
                let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
                let modDate = attributes?[.modificationDate] as? Date ?? Date()

                // Look up availability from framework (cached)
                let availability: FrameworkAvailability
                if let cached = frameworkAvailabilityCache[framework] {
                    availability = cached
                } else {
                    availability = await searchIndex.getFrameworkAvailability(framework: framework)
                    frameworkAvailabilityCache[framework] = availability
                }

                do {
                    // Apple Archive source with framework (or book title as fallback)
                    try await searchIndex.indexDocument(Search.Index.IndexDocumentParams(
                        uri: uri,
                        source: "apple-archive",
                        framework: framework,
                        title: title,
                        content: content,
                        filePath: file.path,
                        contentHash: contentHash,
                        lastCrawled: modDate,
                        minIOS: availability.minIOS,
                        minMacOS: availability.minMacOS,
                        minTvOS: availability.minTvOS,
                        minWatchOS: availability.minWatchOS,
                        minVisionOS: availability.minVisionOS,
                        availabilitySource: availability.minIOS != nil ? "framework" : nil,
                    ))
                    indexed += 1
                } catch {
                    logError("Failed to index \(uri): \(error)")
                    skipped += 1
                }

                if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    logInfo("   Progress: \(index + 1)/\(markdownFiles.count)")
                }
            }

            logInfo("   Apple Archive: \(indexed) indexed, \(skipped) skipped")
        }

        // MARK: - Human Interface Guidelines

        private func indexHIGDocs(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            guard let higDirectory else {
                return
            }

            guard FileManager.default.fileExists(atPath: higDirectory.path) else {
                logInfo("⚠️  HIG directory not found: \(higDirectory.path)")
                return
            }

            let markdownFiles = try findMarkdownFiles(in: higDirectory)

            guard !markdownFiles.isEmpty else {
                logInfo("⚠️  No HIG documentation found")
                return
            }

            logInfo("🎨 Indexing \(markdownFiles.count) Human Interface Guidelines pages...")

            var indexed = 0
            var skipped = 0

            for (index, file) in markdownFiles.enumerated() {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    skipped += 1
                    continue
                }

                // Extract category from path: hig/{category}/...
                let category = extractFrameworkFromPath(file, relativeTo: higDirectory) ?? "general"

                // Extract metadata from front matter
                let metadata = extractHIGMetadata(from: content)
                let title = metadata["title"] ?? extractTitle(from: content) ?? file.deletingPathExtension().lastPathComponent

                // Generate URI: hig://{category}/{filename}
                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "hig://\(category)/\(filename)"

                // Calculate content hash
                let contentHash = Shared.Models.HashUtilities.sha256(of: content)

                // Use file modification date
                let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
                let modDate = attributes?[.modificationDate] as? Date ?? Date()

                do {
                    // HIG source with category as framework
                    // HIG is universal - applies to all Apple platforms
                    try await searchIndex.indexDocument(Search.Index.IndexDocumentParams(
                        uri: uri,
                        source: Shared.Constants.SourcePrefix.hig,
                        framework: category,
                        title: title,
                        content: content,
                        filePath: file.path,
                        contentHash: contentHash,
                        lastCrawled: modDate,
                        minIOS: "2.0",
                        minMacOS: "10.0",
                        minTvOS: "9.0",
                        minWatchOS: "2.0",
                        minVisionOS: "1.0",
                        availabilitySource: "universal",
                    ))
                    indexed += 1
                } catch {
                    logError("Failed to index \(uri): \(error)")
                    skipped += 1
                }

                if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    logInfo("   Progress: \(index + 1)/\(markdownFiles.count)")
                }
            }

            logInfo("   HIG: \(indexed) indexed, \(skipped) skipped")
        }

        private func extractHIGMetadata(from markdown: String) -> [String: String] {
            var metadata: [String: String] = [:]

            // Look for YAML front matter
            guard markdown.hasPrefix("---") else { return metadata }

            if let endRange = markdown.range(of: "\n---", range: markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex) {
                let frontMatter = String(markdown[markdown.index(markdown.startIndex, offsetBy: 4)..<endRange.lowerBound])

                for line in frontMatter.split(separator: "\n") {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        var value = parts[1].trimmingCharacters(in: .whitespaces)
                        // Remove quotes
                        if value.hasPrefix("\""), value.hasSuffix("\"") {
                            value = String(value.dropFirst().dropLast())
                        }
                        metadata[key] = value
                    }
                }
            }

            return metadata
        }

        private func extractArchiveMetadata(from markdown: String) -> [String: String] {
            var metadata: [String: String] = [:]

            // Look for YAML front matter
            guard markdown.hasPrefix("---") else { return metadata }

            if let endRange = markdown.range(of: "\n---", range: markdown.index(markdown.startIndex, offsetBy: 3)..<markdown.endIndex) {
                let frontMatter = String(markdown[markdown.index(markdown.startIndex, offsetBy: 4)..<endRange.lowerBound])

                for line in frontMatter.split(separator: "\n") {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        var value = parts[1].trimmingCharacters(in: .whitespaces)
                        // Remove quotes
                        if value.hasPrefix("\""), value.hasSuffix("\"") {
                            value = String(value.dropFirst().dropLast())
                        }
                        metadata[key] = value
                    }
                }
            }

            return metadata
        }

        // MARK: - Helper Methods

        /// Framework synonyms - maps a framework to additional names it should be indexed under
        private static let frameworkSynonyms: [String: [String]] = [
            "QuartzCore": ["CoreAnimation"],
            "CoreGraphics": ["Quartz2D"],
        ]

        /// Expand framework to include synonyms (returns comma-separated list)
        private func expandFrameworkSynonyms(_ framework: String) -> String {
            if let synonyms = Self.frameworkSynonyms[framework], !synonyms.isEmpty {
                return ([framework] + synonyms).joined(separator: ", ")
            }
            return framework
        }

        private func extractTitle(from markdown: String) -> String? {
            // Remove front matter first
            var content = markdown
            if let firstDash = markdown.range(of: "---")?.lowerBound {
                if let secondDash = markdown.range(
                    of: "---",
                    range: markdown.index(after: firstDash)..<markdown.endIndex
                )?.upperBound {
                    content = String(markdown[secondDash...])
                }
            }

            // Look for first # heading
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") {
                    return String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
                }
            }

            return nil
        }

        private func extractProposalID(from filename: String) -> String? {
            // Extract SE-NNNN or ST-NNNN from filenames like "SE-0001-optional-binding.md" or "ST-0001-foo.md"
            if let regex = try? NSRegularExpression(pattern: Shared.Constants.Pattern.evolutionReference, options: []),
               let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
               let range = Range(match.range(at: 1), in: filename) {
                return String(filename[range])
            }
            return nil
        }

        private func indexSampleCodeCatalog(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            // Sample-code catalog now lives ONLY on disk
            // (<sample-code-dir>/catalog.json, written by
            // `cupertino fetch --type code`). The previous embedded fallback
            // was deleted in #215 — auto-discovery is the source of truth.
            let entries = await Sample.Core.Catalog.allEntries
            let source = await Sample.Core.Catalog.loadedSource ?? .missing
            switch source {
            case .onDisk:
                logInfo("📦 Indexing sample code catalog from on-disk catalog.json (#214)...")
            case .missing:
                let path = Shared.Constants.defaultSampleCodeDirectory
                    .appendingPathComponent(Sample.Core.Catalog.onDiskCatalogFilename)
                    .path
                logInfo("⚠️  No sample-code catalog at \(path) — skipping sample-code indexing.")
                logInfo("    Run `cupertino fetch --type code` to populate the catalog, then re-run save.")
                return
            }

            guard !entries.isEmpty else {
                logInfo("⚠️  Sample-code catalog parsed but contained zero entries; skipping.")
                return
            }

            logInfo("📚 Indexing \(entries.count) sample code entries...")

            // Cache framework availability lookups
            var frameworkAvailabilityCache: [String: FrameworkAvailability] = [:]

            var indexed = 0
            var skipped = 0

            for (index, entry) in entries.enumerated() {
                do {
                    // Look up availability from framework (cached)
                    let availability: FrameworkAvailability
                    if let cached = frameworkAvailabilityCache[entry.framework] {
                        availability = cached
                    } else {
                        availability = await searchIndex.getFrameworkAvailability(framework: entry.framework)
                        frameworkAvailabilityCache[entry.framework] = availability
                    }

                    try await searchIndex.indexSampleCode(
                        url: entry.url,
                        framework: entry.framework,
                        title: entry.title,
                        description: entry.description,
                        zipFilename: entry.zipFilename,
                        webURL: entry.webURL,
                        minIOS: availability.minIOS,
                        minMacOS: availability.minMacOS,
                        minTvOS: availability.minTvOS,
                        minWatchOS: availability.minWatchOS,
                        minVisionOS: availability.minVisionOS
                    )
                    indexed += 1
                } catch {
                    logError("Failed to index sample code \(entry.title): \(error)")
                    skipped += 1
                }

                if (index + 1) % 100 == 0 {
                    onProgress?(index + 1, entries.count)
                    logInfo("   Progress: \(index + 1)/\(entries.count)")
                }
            }

            logInfo("   Sample Code: \(indexed) indexed, \(skipped) skipped")
        }

        private func indexPackagesCatalog(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            logInfo("📦 Indexing Swift packages catalog from bundled resources...")

            let packages = await Core.Protocols.SwiftPackagesCatalog.allPackages

            guard !packages.isEmpty else {
                logInfo("⚠️  No packages found in catalog")
                return
            }

            logInfo("📚 Indexing \(packages.count) Swift packages...")

            var indexed = 0
            var skipped = 0

            for (index, package) in packages.enumerated() {
                do {
                    try await searchIndex.indexPackage(
                        owner: package.owner,
                        name: package.repo,
                        repositoryURL: package.url,
                        description: package.description,
                        stars: package.stars,
                        isAppleOfficial: package.owner.lowercased() == "apple",
                        lastUpdated: package.updatedAt
                    )
                    indexed += 1
                } catch {
                    logError("Failed to index package \(package.repo): \(error)")
                    skipped += 1
                }

                if (index + 1) % 500 == 0 {
                    onProgress?(index + 1, packages.count)
                    logInfo("   Progress: \(index + 1)/\(packages.count)")
                }
            }

            logInfo("   Packages: \(indexed) indexed, \(skipped) skipped")
        }

        private func logInfo(_ message: String) {
            Logging.Log.info(message, category: .search)
        }

        private func logError(_ message: String) {
            let errorMessage = "❌ \(message)"
            Logging.Log.error(errorMessage, category: .search)
        }

        // MARK: - #284 indexer-side defense

        /// Returns true if `title` matches an HTTP error template's title
        /// pattern. Used to skip poisoned-on-disk JSON files at index time as
        /// a belt-and-suspenders complement to PR #289's crawler-side gate.
        ///
        /// Two checks, mirroring the issue spec:
        /// 1. Title starts with one of the canonical HTTP error status codes
        ///    followed by whitespace or end-of-string ("502 Bad Gateway",
        ///    "404 Not Found", etc.). Catches the literal CDN-rendered
        ///    error pages.
        /// 2. Title equals (after trim) one of the standalone error phrases
        ///    Apple's CDN sometimes returns. Catches templates that drop
        ///    the numeric prefix.
        ///
        /// `internal` so SearchTests can pin the truth table.
        static func titleLooksLikeHTTPErrorTemplate(_ title: String) -> Bool {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }

            // Status-prefix form: "403 Forbidden", "502 Bad Gateway", etc.
            if trimmed.range(of: #"^(403|404|429|500|502|503|504)(\s|$)"#, options: .regularExpression) != nil {
                return true
            }

            // Standalone phrase form (rare but seen in some Apple CDN error templates)
            let standalone: Set = [
                "Forbidden",
                "Bad Gateway",
                "Not Found",
                "Service Unavailable",
                "Gateway Timeout",
                "Too Many Requests",
                "Internal Server Error",
            ]
            return standalone.contains(trimmed)
        }

        /// Returns true if the page looks like Apple's "JavaScript disabled"
        /// fallback that the WebView crawler captured when JS didn't render
        /// in time. The on-disk file has a real-looking title (Apple ships
        /// it in HTML metadata even when JS is off) but the body content is
        /// `[ Skip Navigation ](#app-main)# An unknown error occurred.` with
        /// an `overview` of `Please turn on JavaScript in your browser…`.
        ///
        /// Found in 1,327 files of the v1.0.2 corpus when this audit ran;
        /// missed by every prior title-only check.
        ///
        /// `internal` so SearchTests can pin the truth table.
        static func pageLooksLikeJavaScriptFallback(_ page: Shared.Models.StructuredDocumentationPage) -> Bool {
            // Strongest signal: overview is the literal Apple JS-warning text.
            if let overview = page.overview, overview.contains("Please turn on JavaScript") {
                return true
            }
            // Body signal: rawMarkdown carries the broken Skip-Navigation +
            // "An unknown error occurred" pattern that the crawler emitted
            // when it couldn't extract real content.
            if let rawmd = page.rawMarkdown {
                if rawmd.contains("Please turn on JavaScript") { return true }
                if rawmd.contains("#app-main)# An unknown error occurred") { return true }
            }
            return false
        }
    }
}
