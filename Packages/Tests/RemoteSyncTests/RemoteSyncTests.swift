import Foundation
import Testing

@testable import RemoteSync

// MARK: - RemoteIndexState Tests

@Suite("RemoteIndexState Tests")
struct RemoteIndexStateTests {
    @Test("Initial state has correct defaults")
    func initialState() {
        let state = RemoteIndexState(version: "1.0.0")

        #expect(state.version == "1.0.0")
        #expect(state.phase == .docs)
        #expect(state.phasesCompleted.isEmpty)
        #expect(state.currentFramework == nil)
        #expect(state.frameworksCompleted.isEmpty)
        #expect(state.frameworksTotal == 0)
        #expect(state.currentFileIndex == 0)
        #expect(state.filesTotal == 0)
    }

    @Test("Starting phase updates state correctly")
    func testStartingPhase() {
        let state = RemoteIndexState(version: "1.0.0")
        let newState = state.startingPhase(.docs, frameworksTotal: 248)

        #expect(newState.phase == .docs)
        #expect(newState.frameworksTotal == 248)
        #expect(newState.frameworksCompleted.isEmpty)
        #expect(newState.currentFramework == nil)
    }

    @Test("Starting framework updates state correctly")
    func testStartingFramework() {
        let state = RemoteIndexState(version: "1.0.0")
            .startingPhase(.docs, frameworksTotal: 248)
            .startingFramework("swiftui", filesTotal: 1000)

        #expect(state.currentFramework == "swiftui")
        #expect(state.filesTotal == 1000)
        #expect(state.currentFileIndex == 0)
    }

    @Test("Updating file index preserves other state")
    func testUpdatingFileIndex() {
        let state = RemoteIndexState(version: "1.0.0")
            .startingPhase(.docs, frameworksTotal: 248)
            .startingFramework("swiftui", filesTotal: 1000)
            .updatingFileIndex(456)

        #expect(state.currentFileIndex == 456)
        #expect(state.currentFramework == "swiftui")
        #expect(state.filesTotal == 1000)
    }

    @Test("Completing framework adds to completed list")
    func testCompletingFramework() {
        let state = RemoteIndexState(version: "1.0.0")
            .startingPhase(.docs, frameworksTotal: 248)
            .startingFramework("swiftui", filesTotal: 1000)
            .updatingFileIndex(1000)
            .completingFramework()

        #expect(state.frameworksCompleted == ["swiftui"])
        #expect(state.currentFramework == nil)
        #expect(state.currentFileIndex == 0)
    }

    @Test("Completing phase adds to completed list")
    func testCompletingPhase() {
        let state = RemoteIndexState(version: "1.0.0")
            .startingPhase(.docs, frameworksTotal: 1)
            .startingFramework("foundation", filesTotal: 100)
            .completingFramework()
            .completingPhase()

        #expect(state.phasesCompleted == [.docs])
    }

    @Test("Overall progress calculation")
    func testOverallProgress() {
        // Empty state = 0%
        let emptyState = RemoteIndexState(version: "1.0.0")
        #expect(emptyState.overallProgress == 0.0)

        // One phase done out of 5 = 20%
        let onePhaseComplete = RemoteIndexState(
            version: "1.0.0",
            phase: .evolution,
            phasesCompleted: [.docs]
        )
        #expect(onePhaseComplete.overallProgress > 0.19)
        #expect(onePhaseComplete.overallProgress < 0.21)
    }

    @Test("State persistence round-trip")
    func statePersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let stateURL = tempDir.appendingPathComponent("test-state-\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: stateURL)
        }

        let original = RemoteIndexState(version: "1.0.0")
            .startingPhase(.docs, frameworksTotal: 248)
            .startingFramework("swiftui", filesTotal: 1000)
            .updatingFileIndex(456)

        try original.save(to: stateURL)

        #expect(RemoteIndexState.exists(at: stateURL))

        let loaded = try RemoteIndexState.load(from: stateURL)

        #expect(loaded.version == original.version)
        #expect(loaded.phase == original.phase)
        #expect(loaded.currentFramework == original.currentFramework)
        #expect(loaded.currentFileIndex == original.currentFileIndex)
        #expect(loaded.filesTotal == original.filesTotal)
    }

    @Test("State deletion")
    func stateDeletion() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let stateURL = tempDir.appendingPathComponent("test-delete-\(UUID().uuidString).json")

        let state = RemoteIndexState(version: "1.0.0")
        try state.save(to: stateURL)

        #expect(RemoteIndexState.exists(at: stateURL))

        try RemoteIndexState.delete(at: stateURL)

        #expect(!RemoteIndexState.exists(at: stateURL))
    }
}

// MARK: - RemoteSyncProgress Tests

@Suite("RemoteSyncProgress Tests")
struct RemoteSyncProgressTests {
    @Test("Progress ETA calculation")
    func progressETA() {
        // 50% done in 60 seconds = ~60 seconds remaining
        let progress = RemoteSyncProgress(
            phase: .docs,
            framework: "swiftui",
            frameworkIndex: 124,
            frameworksTotal: 248,
            fileIndex: 500,
            filesTotal: 1000,
            elapsed: 60.0,
            overallProgress: 0.5
        )

        let eta = progress.estimatedTimeRemaining
        #expect(eta != nil)
        #expect(eta! > 55.0)
        #expect(eta! < 65.0)
    }

    @Test("Progress ETA nil for early progress")
    func progressETAEarly() {
        let progress = RemoteSyncProgress(
            phase: .docs,
            framework: nil,
            frameworkIndex: 0,
            frameworksTotal: 248,
            fileIndex: 0,
            filesTotal: 0,
            elapsed: 1.0,
            overallProgress: 0.001
        )

        #expect(progress.estimatedTimeRemaining == nil)
    }
}

// MARK: - AnimatedProgress Tests

@Suite("AnimatedProgress Tests")
struct AnimatedProgressTests {
    @Test("Progress bar rendering")
    func progressBarRendering() {
        let display = AnimatedProgress(barWidth: 10, useEmoji: false)
        let progress = RemoteSyncProgress(
            phase: .docs,
            framework: "swiftui",
            frameworkIndex: 5,
            frameworksTotal: 10,
            fileIndex: 250,
            filesTotal: 500,
            elapsed: 120.0,
            overallProgress: 0.5
        )

        let rendered = display.render(progress)

        #expect(rendered.contains("Docs"))
        #expect(rendered.contains("swiftui"))
        #expect(rendered.contains("5/10"))
        #expect(rendered.contains("250/500"))
    }

    @Test("Compact rendering")
    func compactRendering() {
        let display = AnimatedProgress(barWidth: 10, useEmoji: false)
        let progress = RemoteSyncProgress(
            phase: .docs,
            framework: "foundation",
            frameworkIndex: 3,
            frameworksTotal: 10,
            fileIndex: 50,
            filesTotal: 100,
            elapsed: 30.0,
            overallProgress: 0.3
        )

        let compact = display.renderCompact(progress)

        #expect(compact.contains("3/10"))
        #expect(compact.contains("foundation"))
        #expect(compact.contains("50/100"))
    }
}

// MARK: - GitHubFetcher Tests

@Suite("GitHubFetcher Tests")
struct GitHubFetcherTests {
    // Note: Using apple/swift-evolution as test repo (NOT cupertino-docs)
    // This is a public repo that won't change structure unexpectedly

    @Test("Fetcher initialization with custom repo")
    func fetcherInitialization() async {
        let fetcher = GitHubFetcher(
            repository: "apple/swift-evolution",
            branch: "main"
        )

        // Just verify it initializes - actual network tests below
        let repo = await fetcher.repository
        let branch = await fetcher.branch

        #expect(repo == "apple/swift-evolution")
        #expect(branch == "main")
    }

    @Test("GitHubFileInfo equality")
    func gitHubFileInfoEquality() {
        let info1 = GitHubFileInfo(name: "test.json", path: "/docs/test.json", size: 1024)
        let info2 = GitHubFileInfo(name: "test.json", path: "/docs/test.json", size: 1024)
        let info3 = GitHubFileInfo(name: "other.json", path: "/docs/other.json", size: 2048)

        #expect(info1 == info2)
        #expect(info1 != info3)
    }

    @Test("Error descriptions")
    func errorDescriptions() {
        let url = URL(string: "https://example.com/test")!

        let notFound = GitHubFetcherError.notFound(url: url)
        #expect(notFound.description.contains("Not found"))

        let rateLimited = GitHubFetcherError.rateLimited
        #expect(rateLimited.description.contains("rate limit"))

        let httpError = GitHubFetcherError.httpError(statusCode: 500, url: url)
        #expect(httpError.description.contains("500"))

        let invalidEncoding = GitHubFetcherError.invalidEncoding(path: "/test.json")
        #expect(invalidEncoding.description.contains("encoding"))
    }
}

// MARK: - RemoteIndexer Tests

@Suite("RemoteIndexer Tests")
struct RemoteIndexerTests {
    @Test("Indexer initialization")
    func indexerInitialization() async {
        let tempDir = FileManager.default.temporaryDirectory
        let stateURL = tempDir.appendingPathComponent("test-indexer-\(UUID().uuidString).json")

        let indexer = RemoteIndexer(
            fetcher: GitHubFetcher(repository: "apple/swift-evolution"),
            stateFileURL: stateURL,
            appVersion: "1.0.0"
        )

        let hasResumable = await indexer.hasResumableState()
        #expect(!hasResumable)

        let state = await indexer.getState()
        #expect(state.version == "1.0.0")
        #expect(state.phase == .docs)
    }

    @Test("Indexer state management")
    func indexerStateManagement() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let stateURL = tempDir.appendingPathComponent("test-state-mgmt-\(UUID().uuidString).json")

        defer {
            try? FileManager.default.removeItem(at: stateURL)
        }

        // Create and save state externally
        let existingState = RemoteIndexState(version: "1.0.0")
            .startingPhase(.docs, frameworksTotal: 100)
            .startingFramework("test", filesTotal: 50)
            .updatingFileIndex(25)
        try existingState.save(to: stateURL)

        // Create indexer and check it detects resumable state
        let indexer = RemoteIndexer(
            fetcher: GitHubFetcher(repository: "apple/swift-evolution"),
            stateFileURL: stateURL,
            appVersion: "1.0.0"
        )

        let hasResumable = await indexer.hasResumableState()
        #expect(hasResumable)

        // Load state
        try await indexer.loadState()
        let loaded = await indexer.getState()
        #expect(loaded.currentFramework == "test")
        #expect(loaded.currentFileIndex == 25)

        // Clear state
        try await indexer.clearState()
        let cleared = await indexer.hasResumableState()
        #expect(!cleared)
    }

    @Test("IndexResult creation")
    func indexResult() {
        let success = RemoteIndexer.IndexResult(
            uri: "apple-docs://swiftui/View",
            title: "View",
            success: true
        )
        #expect(success.success)
        #expect(success.error == nil)

        let failure = RemoteIndexer.IndexResult(
            uri: "apple-docs://swiftui/View",
            title: "View",
            success: false,
            error: "Network error"
        )
        #expect(!failure.success)
        #expect(failure.error == "Network error")
    }
}

// MARK: - RemoteIndexerError Tests

@Suite("RemoteIndexerError Tests")
struct RemoteIndexerErrorTests {
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let versionMismatch = RemoteIndexerError.stateVersionMismatch(expected: "1.0.0", found: "0.9.0")
        #expect(versionMismatch.description.contains("1.0.0"))
        #expect(versionMismatch.description.contains("0.9.0"))

        let phaseNotFound = RemoteIndexerError.phaseNotFound("unknown")
        #expect(phaseNotFound.description.contains("unknown"))

        let indexingFailed = RemoteIndexerError.indexingFailed(uri: "test://uri", underlying: "timeout")
        #expect(indexingFailed.description.contains("test://uri"))
        #expect(indexingFailed.description.contains("timeout"))
    }
}

// MARK: - Integration Tests (require network)

@Suite("Integration Tests", .disabled("Requires network access"))
struct IntegrationTests {
    @Test("Fetch directory listing from GitHub")
    func fetchDirectoryListing() async throws {
        // Using swift-evolution repo (NOT cupertino-docs)
        let fetcher = GitHubFetcher(
            repository: "apple/swift-evolution",
            branch: "main"
        )

        let proposals = try await fetcher.fetchDirectoryList(path: "proposals")

        // swift-evolution has hundreds of proposals
        #expect(proposals.count > 100)
    }

    @Test("Fetch file content from GitHub")
    func fetchFileContent() async throws {
        let fetcher = GitHubFetcher(
            repository: "apple/swift-evolution",
            branch: "main"
        )

        let readme = try await fetcher.fetchString(path: "README.md")

        #expect(readme.contains("Swift"))
        #expect(readme.count > 100)
    }
}
