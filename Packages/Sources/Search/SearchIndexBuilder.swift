import Core
import Foundation
import Logging
import Shared

// MARK: - Search Index Builder

/// Builds search index from crawled documentation
extension Search {
    public actor IndexBuilder {
        private let searchIndex: Search.Index
        private let metadata: CrawlMetadata?
        private let docsDirectory: URL
        private let evolutionDirectory: URL?
        private let swiftOrgDirectory: URL?
        private let indexSampleCode: Bool

        public init(
            searchIndex: Search.Index,
            metadata: CrawlMetadata?,
            docsDirectory: URL,
            evolutionDirectory: URL? = nil,
            swiftOrgDirectory: URL? = nil,
            indexSampleCode: Bool = true
        ) {
            self.searchIndex = searchIndex
            self.metadata = metadata
            self.docsDirectory = docsDirectory
            self.evolutionDirectory = evolutionDirectory
            self.swiftOrgDirectory = swiftOrgDirectory
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

            // Index Sample Code catalog if requested
            if indexSampleCode {
                try await indexSampleCodeCatalog(onProgress: onProgress)
            }

            // Index Swift Packages catalog
            try await indexPackagesCatalog(onProgress: onProgress)

            let count = try await searchIndex.documentCount()
            logInfo("✅ Search index built: \(count) documents")
        }

        // MARK: - Private Methods

        private func indexAppleDocs(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            // Use metadata if available, otherwise scan directory
            if let metadata {
                try await indexAppleDocsFromMetadata(metadata: metadata, onProgress: onProgress)
            } else {
                try await indexAppleDocsFromDirectory(onProgress: onProgress)
            }
        }

        private func indexAppleDocsFromMetadata(
            metadata: CrawlMetadata,
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

                // Extract title from front matter or first heading
                let title = extractTitle(from: content) ?? URLUtilities.filename(from: URL(string: url)!)

                // Build URI
                let uri = "apple-docs://\(pageMetadata.framework)/\(URLUtilities.filename(from: URL(string: url)!))"

                // Index document
                do {
                    try await searchIndex.indexDocument(
                        uri: uri,
                        framework: pageMetadata.framework,
                        title: title,
                        content: content,
                        filePath: pageMetadata.filePath,
                        contentHash: pageMetadata.contentHash,
                        lastCrawled: pageMetadata.lastCrawled
                    )
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

            // Recursively find all .md files
            let markdownFiles = try findMarkdownFiles(in: docsDirectory)

            guard !markdownFiles.isEmpty else {
                logInfo("⚠️  No markdown files found in \(docsDirectory.path)")
                return
            }

            logInfo("📚 Indexing \(markdownFiles.count) documentation pages from directory...")

            var indexed = 0
            var skipped = 0

            for (index, file) in markdownFiles.enumerated() {
                // Extract framework from path: docs/{framework}/...
                guard let framework = extractFrameworkFromPath(file, relativeTo: docsDirectory) else {
                    skipped += 1
                    continue
                }

                // Read markdown content
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    skipped += 1
                    continue
                }

                // Extract title from markdown
                let title = extractTitle(from: content) ?? file.deletingPathExtension().lastPathComponent

                // Generate URI: apple-docs://{framework}/{filename}
                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "apple-docs://\(framework)/\(filename)"

                // Calculate content hash
                let contentHash = HashUtilities.sha256(of: content)

                // Use file modification date
                let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
                let modDate = attributes?[.modificationDate] as? Date ?? Date()

                // Index document
                do {
                    try await searchIndex.indexDocument(
                        uri: uri,
                        framework: framework,
                        title: title,
                        content: content,
                        filePath: file.path,
                        contentHash: contentHash,
                        lastCrawled: modDate
                    )
                    indexed += 1
                } catch {
                    logError("Failed to index \(uri): \(error)")
                    skipped += 1
                }

                if (index + 1) % 100 == 0 {
                    onProgress?(index + 1, markdownFiles.count)
                    logInfo("   Progress: \(index + 1)/\(markdownFiles.count) (\(indexed) indexed, \(skipped) skipped)")
                }
            }

            logInfo("   Directory scan: \(indexed) indexed, \(skipped) skipped")
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
            // Get path relative to base directory
            let basePath = baseDir.path
            let filePath = file.path

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

        private func getProposalFiles(from directory: URL) throws -> [URL] {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            return files.filter {
                $0.pathExtension == "md" &&
                    $0.lastPathComponent.range(of: #"^\d{4}-"#, options: .regularExpression) != nil
            }
        }

        private func indexProposal(file: URL, content: String) async throws {
            let filename = file.deletingPathExtension().lastPathComponent
            let proposalID = extractProposalID(from: filename) ?? filename
            let title = extractTitle(from: content) ?? proposalID
            let uri = "swift-evolution://\(proposalID)"

            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            let modDate = attributes?[.modificationDate] as? Date ?? Date()
            let contentHash = HashUtilities.sha256(of: content)

            try await searchIndex.indexDocument(
                uri: uri,
                framework: "swift-evolution",
                title: title,
                content: content,
                filePath: file.path,
                contentHash: contentHash,
                lastCrawled: modDate
            )
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

            let markdownFiles = try findMarkdownFiles(in: swiftOrgDirectory)

            guard !markdownFiles.isEmpty else {
                logInfo("⚠️  No Swift.org documentation found")
                return
            }

            logInfo("🔶 Indexing \(markdownFiles.count) Swift.org documentation pages...")

            var indexed = 0
            var skipped = 0

            for (index, file) in markdownFiles.enumerated() {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    skipped += 1
                    continue
                }

                // Extract category from path: swift-org/{category}/...
                let category = extractFrameworkFromPath(file, relativeTo: swiftOrgDirectory) ?? "swift-org"

                // Extract title from markdown
                let title = extractTitle(from: content) ?? file.deletingPathExtension().lastPathComponent

                // Generate URI: swift-org://{category}/{filename}
                let filename = file.deletingPathExtension().lastPathComponent
                let uri = "swift-org://\(category)/\(filename)"

                // Calculate content hash
                let contentHash = HashUtilities.sha256(of: content)

                // Use file modification date
                let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
                let modDate = attributes?[.modificationDate] as? Date ?? Date()

                do {
                    try await searchIndex.indexDocument(
                        uri: uri,
                        framework: "swift-org",
                        title: title,
                        content: content,
                        filePath: file.path,
                        contentHash: contentHash,
                        lastCrawled: modDate
                    )
                    indexed += 1
                } catch {
                    logError("Failed to index \(uri): \(error)")
                    skipped += 1
                }

                if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    logInfo("   Progress: \(index + 1)/\(markdownFiles.count)")
                }
            }

            logInfo("   Swift.org: \(indexed) indexed, \(skipped) skipped")
        }

        // MARK: - Helper Methods

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
            // Extract SE-NNNN from filenames like "SE-0001-optional-binding.md"
            if let regex = try? NSRegularExpression(pattern: Shared.Constants.Pattern.seReference, options: []),
               let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
               let range = Range(match.range(at: 1), in: filename) {
                return String(filename[range])
            }
            return nil
        }

        private func indexSampleCodeCatalog(onProgress: (@Sendable (Int, Int) -> Void)?) async throws {
            logInfo("📦 Indexing sample code catalog from bundled resources...")

            let entries = await SampleCodeCatalog.allEntries

            guard !entries.isEmpty else {
                logInfo("⚠️  No sample code entries found in catalog")
                return
            }

            logInfo("📚 Indexing \(entries.count) sample code entries...")

            var indexed = 0
            var skipped = 0

            for (index, entry) in entries.enumerated() {
                do {
                    try await searchIndex.indexSampleCode(
                        url: entry.url,
                        framework: entry.framework,
                        title: entry.title,
                        description: entry.description,
                        zipFilename: entry.zipFilename,
                        webURL: entry.webURL
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

            let packages = await SwiftPackagesCatalog.allPackages

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
            Logging.Logger.search.info(message)
            print(message)
        }

        private func logError(_ message: String) {
            let errorMessage = "❌ \(message)"
            Logging.Logger.search.error(message)
            fputs("\(errorMessage)\n", stderr)
        }
    }
}
