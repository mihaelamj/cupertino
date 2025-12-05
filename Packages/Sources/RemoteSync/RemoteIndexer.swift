import Foundation

// MARK: - Indexing Context

/// Groups callbacks and context for indexing operations.
/// Reduces function parameter count while maintaining type safety.
struct IndexingContext: @unchecked Sendable {
    let indexDocument: RemoteIndexer.DocumentIndexer
    let onProgress: @Sendable (RemoteSyncProgress) -> Void
    let onDocument: (@Sendable (RemoteIndexer.IndexResult) -> Void)?
}

// MARK: - Remote Indexer

/// Main orchestrator for streaming documentation from GitHub to search index.
/// Handles all phases: docs, evolution, archive, swiftOrg, packages.
public actor RemoteIndexer {
    /// GitHub fetcher for HTTP operations
    private let fetcher: GitHubFetcher

    /// State file URL for resume support
    private let stateFileURL: URL

    /// Current indexing state
    private var state: RemoteIndexState

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
        state = RemoteIndexState(version: appVersion)
    }

    // MARK: - Resume Support

    /// Check if there's a resumable state
    public func hasResumableState() -> Bool {
        RemoteIndexState.exists(at: stateFileURL)
    }

    /// Load existing state for resume
    public func loadState() throws {
        state = try RemoteIndexState.load(from: stateFileURL)
    }

    /// Get current state for resume prompt
    public func getState() -> RemoteIndexState {
        state
    }

    /// Clear state to start fresh
    public func clearState() throws {
        try RemoteIndexState.delete(at: stateFileURL)
        state = RemoteIndexState(version: appVersion)
    }

    // MARK: - Indexing

    /// Index result for a single document
    public struct IndexResult: Sendable {
        public let uri: String
        public let title: String
        public let success: Bool
        public let error: String?

        public init(uri: String, title: String, success: Bool, error: String? = nil) {
            self.uri = uri
            self.title = title
            self.success = success
            self.error = error
        }
    }

    /// Callback type for document indexing
    public typealias DocumentIndexer = @Sendable (
        _ uri: String,
        _ source: String,
        _ framework: String?,
        _ title: String,
        _ content: String,
        _ jsonData: String?
    ) async throws -> Void

    /// Run the full indexing process
    /// - Parameters:
    ///   - indexDocument: Callback to index each document
    ///   - onProgress: Progress callback (called frequently)
    ///   - onDocument: Called for each document processed
    public func run(
        indexDocument: @escaping DocumentIndexer,
        onProgress: @escaping @Sendable (RemoteSyncProgress) -> Void,
        onDocument: (@Sendable (IndexResult) -> Void)? = nil
    ) async throws {
        // Determine which phases to run
        let allPhases = RemoteIndexState.Phase.allCases
        let startPhaseIndex = allPhases.firstIndex(of: state.phase) ?? 0

        for phaseIndex in startPhaseIndex..<allPhases.count {
            let phase = allPhases[phaseIndex]

            // Skip completed phases
            if state.phasesCompleted.contains(phase) {
                continue
            }

            try await runPhase(
                phase,
                indexDocument: indexDocument,
                onProgress: onProgress,
                onDocument: onDocument
            )

            // Mark phase complete
            state = state.completingPhase()
            try state.save(to: stateFileURL)
        }

        // Clean up state file on successful completion
        try RemoteIndexState.delete(at: stateFileURL)
    }

    // MARK: - Phase Execution

    private func runPhase(
        _ phase: RemoteIndexState.Phase,
        indexDocument: @escaping DocumentIndexer,
        onProgress: @escaping @Sendable (RemoteSyncProgress) -> Void,
        onDocument: (@Sendable (IndexResult) -> Void)?
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
                indexDocument: indexDocument,
                onProgress: onProgress,
                onDocument: onDocument
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
        phase: RemoteIndexState.Phase,
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
        reportProgress(context.onProgress)

        // Determine starting file index (for resume)
        let startFileIndex = state.currentFileIndex

        for fileIndex in startFileIndex..<jsonFiles.count {
            let file = jsonFiles[fileIndex]

            // Update file progress
            state = state.updatingFileIndex(fileIndex)

            // Report progress every file
            reportProgress(context.onProgress)

            // Fetch and index file
            do {
                let content = try await fetcher.fetchString(path: file.path)
                let title = extractTitle(from: content, filename: file.name)
                let uri = buildURI(phase: phase, item: item, filename: file.name)

                // Determine framework (nil for non-docs phases)
                let framework: String? = phase == .docs ? item : nil

                try await context.indexDocument(uri, source, framework, title, content, content)

                context.onDocument?(IndexResult(uri: uri, title: title, success: true))
            } catch {
                let uri = buildURI(phase: phase, item: item, filename: file.name)
                context.onDocument?(IndexResult(
                    uri: uri,
                    title: file.name,
                    success: false,
                    error: error.localizedDescription
                ))
            }
        }

        // Final progress for this item
        state = state.updatingFileIndex(jsonFiles.count)
        reportProgress(context.onProgress)
    }

    // MARK: - Helpers

    private func phasePath(_ phase: RemoteIndexState.Phase) -> String {
        switch phase {
        case .docs: return "docs"
        case .evolution: return "swift-evolution"
        case .archive: return "archive"
        case .swiftOrg: return "swift-org"
        case .packages: return "packages"
        }
    }

    private func phaseSource(_ phase: RemoteIndexState.Phase) -> String {
        switch phase {
        case .docs: return "apple-docs"
        case .evolution: return "swift-evolution"
        case .archive: return "apple-archive"
        case .swiftOrg: return "swift-org"
        case .packages: return "packages"
        }
    }

    private func buildURI(phase: RemoteIndexState.Phase, item: String, filename: String) -> String {
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

    private func reportProgress(_ onProgress: @Sendable (RemoteSyncProgress) -> Void) {
        let progress = RemoteSyncProgress(
            phase: state.phase,
            framework: state.currentFramework,
            frameworkIndex: state.frameworksCompleted.count + (state.currentFramework != nil ? 1 : 0),
            frameworksTotal: state.frameworksTotal,
            fileIndex: state.currentFileIndex,
            filesTotal: state.filesTotal,
            elapsed: Date().timeIntervalSince(startTime),
            overallProgress: state.overallProgress
        )
        onProgress(progress)
    }
}

// MARK: - Errors

public enum RemoteIndexerError: Error, Sendable, CustomStringConvertible {
    case stateVersionMismatch(expected: String, found: String)
    case phaseNotFound(String)
    case indexingFailed(uri: String, underlying: String)

    public var description: String {
        switch self {
        case let .stateVersionMismatch(expected, found):
            return "State version mismatch: expected \(expected), found \(found)"
        case let .phaseNotFound(phase):
            return "Phase not found: \(phase)"
        case let .indexingFailed(uri, underlying):
            return "Failed to index \(uri): \(underlying)"
        }
    }
}
