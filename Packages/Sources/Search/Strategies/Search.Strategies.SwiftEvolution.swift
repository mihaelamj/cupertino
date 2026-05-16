import Foundation
import LoggingModels
import SearchModels
import SharedConstants

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

        /// GoF Strategy seam for log emission (1994 p. 315).
        private let logger: any LoggingModels.Logging.Recording

        /// Create a strategy for indexing Swift Evolution proposals.
        ///
        /// - Parameter evolutionDirectory: Directory containing the proposal `.md` files.
        public init(
            evolutionDirectory: URL,
            logger: any LoggingModels.Logging.Recording
        ) {
            self.evolutionDirectory = evolutionDirectory
            self.logger = logger
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
            progress: (any Search.IndexingProgressReporting)?
        ) async throws -> Search.IndexStats {
            guard FileManager.default.fileExists(atPath: evolutionDirectory.path) else {
                // #671 — clean-skip when no local corpus is available.
                return IndexStats(
                    source: source,
                    indexed: 0,
                    skipped: 0,
                    wasSkipped: true,
                    skipReason: "no local corpus"
                )
            }

            let proposalFiles = try getProposalFiles(from: evolutionDirectory)
            guard !proposalFiles.isEmpty else {
                // #671 — clean-skip when the dir exists but has no proposals.
                return IndexStats(
                    source: source,
                    indexed: 0,
                    skipped: 0,
                    wasSkipped: true,
                    skipReason: "no proposals found"
                )
            }

            logger.info(
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
                    logger.error(
                        "❌ Failed to index \(file.lastPathComponent): \(error)",
                        category: .search
                    )
                    skipped += 1
                }

                if (idx + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    logger.info(
                        "   Progress: \(idx + 1)/\(proposalFiles.count)", category: .search
                    )
                }
            }

            logger.info(
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

        /// Write a single proposal to the index.
        ///
        /// Extracts the proposal ID from the filename, derives a Swift-version-based
        /// availability range, and calls
        /// ``Search/Index/indexDocument(uri:source:framework:title:content:filePath:contentHash:lastCrawled:minIOS:minMacOS:minTvOS:minWatchOS:minVisionOS:availabilitySource:)``.
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

            // #429: indexer-side poison defence, generalised from
            // apple-docs to all source strategies. Pre-fix only
            // `indexAppleDocsFromDirectory` ran these checks; the
            // swift-evolution / HIG / swift.org / archive paths could
            // ship Apple-CDN HTTP error templates or JS-disabled
            // fallback content straight into the index (the v1.0.2
            // bundle carried a surviving `swift-org://docc_documentation`
            // "Forbidden" row through exactly this gap).
            if Search.StrategyHelpers.titleLooksLikeHTTPErrorTemplate(title) {
                logger.error(
                    "⛔ Skipping HTTP-error-template proposal (#429 defence): title=\(title.prefix(60)) file=\(file.lastPathComponent)",
                    category: .search
                )
                return
            }
            if Search.StrategyHelpers.contentLooksLikeJavaScriptFallback(content) {
                logger.error(
                    "⛔ Skipping JS-fallback proposal (#429 defence): title=\(title.prefix(60)) file=\(file.lastPathComponent)",
                    category: .search
                )
                return
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()
            let contentHash = Shared.Models.HashUtilities.sha256(of: content)

            let status = Search.StrategyHelpers.extractProposalStatus(from: content)
            let availability = Search.StrategyHelpers.mapSwiftVersionToAvailability(status)

            try await index.indexDocument(Search.Index.IndexDocumentParams(
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
            ))
        }
    }
}
