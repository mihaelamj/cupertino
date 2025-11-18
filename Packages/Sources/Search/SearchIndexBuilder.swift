import Foundation
import Logging
import Shared

// MARK: - Search Index Builder

/// Builds search index from crawled documentation
extension Search {
    public actor IndexBuilder {
        private let searchIndex: Search.Index
        private let metadata: CrawlMetadata
        private let docsDirectory: URL
        private let evolutionDirectory: URL?

        public init(
            searchIndex: Search.Index,
            metadata: CrawlMetadata,
            docsDirectory: URL,
            evolutionDirectory: URL? = nil
        ) {
            self.searchIndex = searchIndex
            self.metadata = metadata
            self.docsDirectory = docsDirectory
            self.evolutionDirectory = evolutionDirectory
        }

        // MARK: - Build Index

        /// Build search index from all crawled documents
        public func buildIndex(
            clearExisting: Bool = true,
            onProgress: ((Int, Int) -> Void)? = nil
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

            let count = try await searchIndex.documentCount()
            logInfo("✅ Search index built: \(count) documents")
        }

        // MARK: - Private Methods

        private func indexAppleDocs(onProgress: ((Int, Int) -> Void)?) async throws {
            let total = metadata.pages.count
            guard total > 0 else {
                logInfo("⚠️  No Apple documentation found in metadata")
                return
            }

            logInfo("📚 Indexing \(total) Apple documentation pages...")

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

        private func indexEvolutionProposals(onProgress: ((Int, Int) -> Void)?) async throws {
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
                $0.pathExtension == "md" && $0.lastPathComponent.range(of: #"^\d{4}-"#, options: .regularExpression) != nil
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
