import Foundation
@_exported import RemoteSyncModels
import SharedConstants

// `@_exported import RemoteSyncModels` keeps callers reaching
// `RemoteSync.Progress` / `RemoteSync.IndexState` / etc. through
// `import RemoteSync` source-compatible after the seam extraction.

extension RemoteSync {
    // MARK: - Indexing Context

    /// Groups callbacks and context for indexing operations.
    /// Reduces function parameter count while maintaining type safety.
    ///
    /// Carries the three GoF Strategy / Observer protocol values supplied
    /// at `run` time:
    ///   - `documentIndexing` (Strategy): how to persist each document.
    ///   - `progress`         (Observer): high-frequency phase / file ticks.
    ///   - `document`         (Observer): per-document outcome, optional.
    struct IndexingContext {
        let documentIndexing: any RemoteSync.DocumentIndexing
        let progress: any RemoteSync.IndexerProgressObserving
        let document: (any RemoteSync.IndexerDocumentObserving)?
    }

    // MARK: - Remote Indexer

    /// Main orchestrator for streaming documentation from GitHub to search index.
    /// Handles all phases: docs, evolution, archive, swiftOrg, packages.
    public actor Indexer {
        /// GitHub fetcher for HTTP operations
        private let fetcher: GitHubFetcher

        /// State file URL for resume support
        private let stateFileURL: URL

        /// Current indexing state
        private var state: IndexState

        /// Start time for elapsed calculation
        private let startTime: Date

        /// App version for state tracking
        private let appVersion: String

        // MARK: - Initialization

        public init(
            fetcher: GitHubFetcher = GitHubFetcher(),
            stateFileURL: URL,
            appVersion: String
        ) {
            self.fetcher = fetcher
            self.stateFileURL = stateFileURL
            self.appVersion = appVersion
            startTime = Date()
            state = IndexState(version: appVersion)
        }

        // MARK: - Resume Support

        /// Check if there's a resumable state
        public func hasResumableState() -> Bool {
            IndexState.exists(at: stateFileURL)
        }

        /// Load existing state for resume
        public func loadState() throws {
            state = try IndexState.load(from: stateFileURL)
        }

        /// Get current state for resume prompt
        public func getState() -> IndexState {
            state
        }

        /// Clear state to start fresh
        public func clearState() throws {
            try IndexState.delete(at: stateFileURL)
            state = IndexState(version: appVersion)
        }

        // MARK: - Indexing

        /// Run the full indexing process.
        ///
        /// - Parameters:
        ///   - documentIndexing: GoF Strategy seam for persisting each
        ///     document into a search backend. Replaces the previous
        ///     `indexDocument: DocumentIndexer` closure typealias.
        ///   - progress: GoF Observer for high-frequency progress ticks.
        ///     Replaces the previous `onProgress` closure.
        ///   - document: Optional GoF Observer for per-document outcome.
        ///     Replaces the previous `onDocument` closure.
        public func run(
            documentIndexing: any RemoteSync.DocumentIndexing,
            progress: any RemoteSync.IndexerProgressObserving,
            document: (any RemoteSync.IndexerDocumentObserving)? = nil
        ) async throws {
            // Determine which phases to run
            let allPhases = IndexState.Phase.allCases
            let startPhaseIndex = allPhases.firstIndex(of: state.phase) ?? 0

            for phaseIndex in startPhaseIndex..<allPhases.count {
                let phase = allPhases[phaseIndex]

                // Skip completed phases
                if state.phasesCompleted.contains(phase) {
                    continue
                }

                try await runPhase(
                    phase,
                    documentIndexing: documentIndexing,
                    progress: progress,
                    document: document
                )

                // Mark phase complete
                state = state.completingPhase()
                try state.save(to: stateFileURL)
            }

            // Clean up state file on successful completion
            try IndexState.delete(at: stateFileURL)
        }

        // MARK: - Phase Execution

        private func runPhase(
            _ phase: IndexState.Phase,
            documentIndexing: any RemoteSync.DocumentIndexing,
            progress: any RemoteSync.IndexerProgressObserving,
            document: (any RemoteSync.IndexerDocumentObserving)?
        ) async throws {
            let path = phasePath(phase)
            let source = phaseSource(phase)

            // Get list of items (frameworks or files depending on phase)
            let items: [String]
            switch phase {
            case .docs:
                items = try await fetcher.fetchDirectoryList(path: path)
            case .evolution, .archive, .swiftOrg, .packages:
                // These phases may have different structures
                items = try await fetcher.fetchDirectoryList(path: path)
            }

            // Update state with phase info
            state = state.startingPhase(phase, frameworksTotal: items.count)
            try state.save(to: stateFileURL)

            // Determine starting index (for resume)
            let startIndex = state.frameworksCompleted.count

            for itemIndex in startIndex..<items.count {
                let item = items[itemIndex]

                // Skip already completed items
                if state.frameworksCompleted.contains(item) {
                    continue
                }

                let context = IndexingContext(
                    documentIndexing: documentIndexing,
                    progress: progress,
                    document: document
                )
                try await indexItem(
                    item,
                    at: "\(path)/\(item)",
                    phase: phase,
                    source: source,
                    context: context
                )

                // Mark item complete
                state = state.completingFramework()
                try state.save(to: stateFileURL)
            }
        }

        private func indexItem(
            _ item: String,
            at path: String,
            phase: IndexState.Phase,
            source: String,
            context: IndexingContext
        ) async throws {
            // Get file list
            let files = try await fetcher.fetchFileList(path: path)
            let jsonFiles = files.filter { $0.name.hasSuffix(".json") || $0.name.hasSuffix(".md") }

            // Update state
            state = state.startingFramework(item, filesTotal: jsonFiles.count)
            try state.save(to: stateFileURL)

            // Report progress
            reportProgress(to: context.progress)

            // Determine starting file index (for resume)
            let startFileIndex = state.currentFileIndex

            for fileIndex in startFileIndex..<jsonFiles.count {
                let file = jsonFiles[fileIndex]

                // Update file progress
                state = state.updatingFileIndex(fileIndex)

                // Report progress every file
                reportProgress(to: context.progress)

                // Fetch and index file
                do {
                    let content = try await fetcher.fetchString(path: file.path)
                    let title = extractTitle(from: content, filename: file.name)
                    let uri = buildURI(phase: phase, item: item, filename: file.name)

                    // Determine framework (nil for non-docs phases)
                    let framework: String? = phase == .docs ? item : nil

                    try await context.documentIndexing.indexDocument(
                        uri: uri,
                        source: source,
                        framework: framework,
                        title: title,
                        content: content,
                        jsonData: content
                    )

                    context.document?.observe(result: RemoteSync.IndexerResult(
                        uri: uri,
                        title: title,
                        success: true
                    ))
                } catch {
                    let uri = buildURI(phase: phase, item: item, filename: file.name)
                    context.document?.observe(result: RemoteSync.IndexerResult(
                        uri: uri,
                        title: file.name,
                        success: false,
                        error: error.localizedDescription
                    ))
                }
            }

            // Final progress for this item
            state = state.updatingFileIndex(jsonFiles.count)
            reportProgress(to: context.progress)
        }

        // MARK: - Helpers

        private func phasePath(_ phase: IndexState.Phase) -> String {
            typealias Dir = Shared.Constants.Directory
            switch phase {
            case .docs: return Dir.docs
            case .evolution: return Dir.swiftEvolution
            case .archive: return Dir.archive
            case .swiftOrg: return Dir.swiftOrg
            case .packages: return Dir.packages
            }
        }

        private func phaseSource(_ phase: IndexState.Phase) -> String {
            typealias SP = Shared.Constants.SourcePrefix
            switch phase {
            case .docs: return SP.appleDocs
            case .evolution: return SP.swiftEvolution
            case .archive: return SP.appleArchive
            case .swiftOrg: return SP.swiftOrg
            case .packages: return SP.packages
            }
        }

        private func buildURI(phase: IndexState.Phase, item: String, filename: String) -> String {
            let baseName = filename
                .replacingOccurrences(of: ".json", with: "")
                .replacingOccurrences(of: ".md", with: "")

            switch phase {
            case .docs:
                return "apple-docs://\(item)/\(baseName)"
            case .evolution:
                return "swift-evolution://\(baseName)"
            case .archive:
                return "apple-archive://\(item)/\(baseName)"
            case .swiftOrg:
                return "swift-org://\(baseName)"
            case .packages:
                return "packages://\(item)/\(baseName)"
            }
        }

        private func extractTitle(from content: String, filename: String) -> String {
            // Try to extract title from JSON
            if let json = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any],
               let title = json["title"] as? String {
                return title
            }

            // Try markdown heading
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") {
                    return String(trimmed.dropFirst(2))
                }
            }

            // Fall back to filename
            return filename
                .replacingOccurrences(of: ".json", with: "")
                .replacingOccurrences(of: ".md", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }

        private func reportProgress(to observer: any RemoteSync.IndexerProgressObserving) {
            let progress = RemoteSync.Progress(
                phase: state.phase,
                framework: state.currentFramework,
                frameworkIndex: state.frameworksCompleted.count + (state.currentFramework != nil ? 1 : 0),
                frameworksTotal: state.frameworksTotal,
                fileIndex: state.currentFileIndex,
                filesTotal: state.filesTotal,
                elapsed: Date().timeIntervalSince(startTime),
                overallProgress: state.overallProgress
            )
            observer.observe(progress: progress)
        }
    }
}
