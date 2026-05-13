import Foundation
import Logging
import SharedConstants
import SharedModels

// MARK: - SwiftEvolutionStrategy

extension Search {
    /// Indexes accepted Swift Evolution proposals into the search index.
    ///
    /// Scans ``evolutionDirectory`` for files whose names start with the `SE-` or `ST-`
    /// prefix, filters to only accepted/implemented proposals, and maps each proposal's
    /// Swift version to minimum iOS and macOS availability versions.
    ///
    /// URI scheme: `swift-evolution://{proposalID}`
    ///
    /// ## Example
    /// ```swift
    /// let strategy = Search.SwiftEvolutionStrategy(evolutionDirectory: evolutionDir)
    /// let stats = try await strategy.indexItems(into: index, progress: nil)
    /// ```
    public struct SwiftEvolutionStrategy: SourceIndexingStrategy {
        /// The source identifier written into the FTS index.
        public let source = Shared.Constants.SourcePrefix.swiftEvolution

        /// Root directory containing the Swift Evolution proposal Markdown files.
        public let evolutionDirectory: URL

        /// Create a strategy for indexing Swift Evolution proposals.
        ///
        /// - Parameter evolutionDirectory: Directory containing the proposal `.md` files.
        public init(evolutionDirectory: URL) {
            self.evolutionDirectory = evolutionDirectory
        }

        /// Index all accepted Swift Evolution proposals found in ``evolutionDirectory``.
        ///
        /// Proposals with a status other than `"Implemented"` or `"Accepted"` are silently
        /// skipped.  Progress is logged every
        /// ``Shared/Constants/Interval/progressLogEvery`` items.
        ///
        /// - Parameters:
        ///   - index: The ``Search/Index`` to write into.
        ///   - progress: Optional progress callback, called at regular intervals.
        /// - Returns: ``Search/IndexStats`` with indexed and skipped counts.
        public func indexItems(
            into index: Search.Index,
            progress: Search.IndexingProgressCallback?
        ) async throws -> Search.IndexStats {
            guard FileManager.default.fileExists(atPath: evolutionDirectory.path) else {
                Logging.Log.info(
                    "⚠️  Swift Evolution directory not found: \(evolutionDirectory.path)",
                    category: .search
                )
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            let proposalFiles = try getProposalFiles(from: evolutionDirectory)
            guard !proposalFiles.isEmpty else {
                Logging.Log.info("⚠️  No Swift Evolution proposals found", category: .search)
                return IndexStats(source: source, indexed: 0, skipped: 0)
            }

            Logging.Log.info(
                "📋 Indexing \(proposalFiles.count) Swift Evolution proposals...",
                category: .search
            )

            var indexed = 0
            var skipped = 0

            for (idx, file) in proposalFiles.enumerated() {
                guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                    skipped += 1
                    continue
                }

                let status = Search.StrategyHelpers.extractProposalStatus(from: content)
                guard Search.StrategyHelpers.isAcceptedProposal(status) else {
                    skipped += 1
                    continue
                }

                do {
                    try await indexProposal(file: file, content: content, into: index)
                    indexed += 1
                } catch {
                    Logging.Log.error(
                        "❌ Failed to index \(file.lastPathComponent): \(error)",
                        category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    Logging.Log.info(
                        "   Progress: \(idx + 1)/\(proposalFiles.count)", category: .search
                    )
                }
            }

            Logging.Log.info(
                "   Swift Evolution: \(indexed) indexed, \(skipped) skipped", category: .search
            )
            return IndexStats(source: source, indexed: indexed, skipped: skipped)
        }

        // MARK: - Private Helpers

        /// Enumerate the proposal files in `directory`.
        ///
        /// Only files whose names start with `Shared.Constants.Search.sePrefix` (`"SE-"`) or
        /// `Shared.Constants.Search.stPrefix` (`"ST-"`) and have a `.md` extension are included.
        ///
        /// - Parameter directory: The Swift Evolution proposals directory.
        /// - Returns: A list of matching file URLs.
        private func getProposalFiles(from directory: URL) throws -> [URL] {
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

        /// Write a single proposal to the index.
        ///
        /// Extracts the proposal ID from the filename, derives a Swift-version-based
        /// availability range, and calls ``Search/Index/indexDocument(uri:source:framework:title:content:filePath:contentHash:lastCrawled:minIOS:minMacOS:minTvOS:minWatchOS:minVisionOS:availabilitySource:)``.
        ///
        /// - Parameters:
        ///   - file: The proposal `.md` file URL.
        ///   - content: The file's raw Markdown content.
        ///   - index: The ``Search/Index`` to write into.
        private func indexProposal(
            file: URL,
            content: String,
            into index: Search.Index
        ) async throws {
            let filename = file.deletingPathExtension().lastPathComponent
            let proposalID = Search.StrategyHelpers.extractProposalID(from: filename) ?? filename
            let title = Search.StrategyHelpers.extractTitle(from: content) ?? proposalID
            let uri = "swift-evolution://\(proposalID)"

            let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()
            let contentHash = Shared.Models.HashUtilities.sha256(of: content)

            let status = Search.StrategyHelpers.extractProposalStatus(from: content)
            let availability = Search.StrategyHelpers.mapSwiftVersionToAvailability(status)

            try await index.indexDocument(
                uri: uri,
                source: source,
                framework: nil,
                title: title,
                content: content,
                filePath: file.path,
                contentHash: contentHash,
                lastCrawled: modDate,
                minIOS: availability.iOS,
                minMacOS: availability.macOS,
                availabilitySource: availability.iOS != nil ? "swift-version" : nil
            )
        }
    }
}
