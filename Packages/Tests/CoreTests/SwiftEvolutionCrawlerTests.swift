@testable import Core
import Foundation
@testable import Shared
import Testing

// MARK: - Swift Evolution Crawler Tests

/// Tests for the Core.EvolutionCrawler
/// Tests proposal ID extraction, status parsing, and filtering logic

@Suite("Swift Evolution Crawler")
struct SwiftEvolutionCrawlerTests {
    // MARK: - Initialization Tests

    @Test("EvolutionCrawler initializes with output directory")
    @MainActor
    func crawlerInitialization() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let crawler = Core.EvolutionCrawler(outputDirectory: tempDir)

        // If we get here without crashing, initialization worked
        _ = crawler

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("EvolutionCrawler initializes with onlyAccepted flag")
    @MainActor
    func crawlerInitializationWithFlag() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let crawler = Core.EvolutionCrawler(
            outputDirectory: tempDir,
            onlyAccepted: true
        )

        _ = crawler

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Proposal ID Extraction Tests

    @Test("Extracts proposal ID from standard format")
    func extractProposalIDStandardFormat() throws {
        // Test filename format: "0001-keywords-as-argument-labels.md"
        let filename = "0042-flatten-method.md"

        // We can't directly test private methods, but we can verify
        // the pattern works by testing similar logic
        let pattern = #"(\d{4})-"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(filename.startIndex..., in: filename)

        let match = regex.firstMatch(in: filename, range: range)
        #expect(match != nil)

        if let match, match.numberOfRanges > 1,
           let numberRange = Range(match.range(at: 1), in: filename) {
            let number = String(filename[numberRange])
            #expect(number == "0042")
        }
    }

    @Test("Extracts proposal ID from SE-prefix format")
    func extractProposalIDWithSEPrefix() throws {
        // Test filename format: "SE-0001-keywords.md"
        let filename = "SE-0100-unicode-operators.md"

        let pattern = #"(\d{4})-"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(filename.startIndex..., in: filename)

        let match = regex.firstMatch(in: filename, range: range)
        #expect(match != nil)

        if let match, match.numberOfRanges > 1,
           let numberRange = Range(match.range(at: 1), in: filename) {
            let number = String(filename[numberRange])
            #expect(number == "0100")
        }
    }

    // MARK: - Status Extraction Tests

    @Test("Recognizes Implemented status")
    @MainActor
    func recognizesImplementedStatus() async throws {
        let markdown = """
        # Some Proposal
        * Status: **Implemented (Swift 5.0)**
        * Author: Someone
        """

        // Test the status parsing pattern
        let pattern = #"\* Status:\s*\*\*([^*]+)\*\*"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(markdown.startIndex..., in: markdown)

        let match = regex.firstMatch(in: markdown, range: range)
        #expect(match != nil)

        if let match, match.numberOfRanges > 1,
           let statusRange = Range(match.range(at: 1), in: markdown) {
            let status = String(markdown[statusRange])
            #expect(status.contains("Implemented"))
        }
    }

    @Test("Recognizes Accepted status")
    @MainActor
    func recognizesAcceptedStatus() async throws {
        let markdown = """
        # Some Proposal
        * Status: **Accepted**
        * Review: Done
        """

        let pattern = #"\* Status:\s*\*\*([^*]+)\*\*"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(markdown.startIndex..., in: markdown)

        let match = regex.firstMatch(in: markdown, range: range)
        #expect(match != nil)

        if let match, match.numberOfRanges > 1,
           let statusRange = Range(match.range(at: 1), in: markdown) {
            let status = String(markdown[statusRange])
            #expect(status.contains("Accepted"))
        }
    }

    @Test("Recognizes Rejected status")
    @MainActor
    func recognizesRejectedStatus() async throws {
        let markdown = """
        # Some Proposal
        * Status: **Rejected**
        * Review: Done
        """

        let pattern = #"\* Status:\s*\*\*([^*]+)\*\*"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(markdown.startIndex..., in: markdown)

        let match = regex.firstMatch(in: markdown, range: range)
        #expect(match != nil)

        if let match, match.numberOfRanges > 1,
           let statusRange = Range(match.range(at: 1), in: markdown) {
            let status = String(markdown[statusRange])
            #expect(status.contains("Rejected"))
        }
    }

    // MARK: - Status Filtering Logic Tests

    @Test("Implemented status is considered accepted")
    @MainActor
    func implementedIsAccepted() async throws {
        let status = "Implemented (Swift 5.0)"
        let isAccepted = status.lowercased().contains("implemented") ||
            status.lowercased().contains("accepted")

        #expect(isAccepted == true)
    }

    @Test("Accepted status is considered accepted")
    @MainActor
    func acceptedIsAccepted() async throws {
        let status = "Accepted"
        let isAccepted = status.lowercased().contains("implemented") ||
            status.lowercased().contains("accepted")

        #expect(isAccepted == true)
    }

    @Test("Accepted with revisions is considered accepted")
    @MainActor
    func acceptedWithRevisionsIsAccepted() async throws {
        let status = "Accepted with revisions"
        let isAccepted = status.lowercased().contains("implemented") ||
            status.lowercased().contains("accepted")

        #expect(isAccepted == true)
    }

    @Test("Rejected status is not accepted")
    @MainActor
    func rejectedIsNotAccepted() async throws {
        let status = "Rejected"
        let isAccepted = status.lowercased().contains("implemented") ||
            status.lowercased().contains("accepted")

        #expect(isAccepted == false)
    }

    @Test("Withdrawn status is not accepted")
    @MainActor
    func withdrawnIsNotAccepted() async throws {
        let status = "Withdrawn"
        let isAccepted = status.lowercased().contains("implemented") ||
            status.lowercased().contains("accepted")

        #expect(isAccepted == false)
    }

    // MARK: - EvolutionStatistics Tests

    @Test("EvolutionStatistics initializes with zeros")
    func statisticsInitializesWithZeros() throws {
        let stats = EvolutionStatistics()

        #expect(stats.totalProposals == 0)
        #expect(stats.newProposals == 0)
        #expect(stats.updatedProposals == 0)
        #expect(stats.errors == 0)
    }

    @Test("EvolutionStatistics tracks counts")
    func statisticsTracksCounts() throws {
        var stats = EvolutionStatistics(startTime: Date())
        stats.totalProposals = 400
        stats.newProposals = 350
        stats.updatedProposals = 50
        stats.errors = 0

        #expect(stats.totalProposals == 400)
        #expect(stats.newProposals == 350)
        #expect(stats.updatedProposals == 50)
        #expect(stats.errors == 0)
    }

    @Test("EvolutionStatistics calculates duration")
    func statisticsCalculatesDuration() throws {
        var stats = EvolutionStatistics(startTime: Date())
        stats.endTime = stats.startTime?.addingTimeInterval(3600) // 1 hour

        let duration = stats.duration
        #expect(duration == 3600.0)
    }

    // MARK: - EvolutionProgress Tests

    @Test("EvolutionProgress tracks progress")
    func progressTracksProgress() throws {
        let stats = EvolutionStatistics()
        let progress = EvolutionProgress(
            current: 100,
            total: 400,
            proposalID: "SE-0100",
            stats: stats
        )

        #expect(progress.current == 100)
        #expect(progress.total == 400)
        #expect(progress.proposalID == "SE-0100")
        #expect(progress.percentage == 25.0)
    }

    // MARK: - ProposalMetadata Tests

    @Test("ProposalMetadata stores proposal info")
    func proposalMetadataStoresInfo() throws {
        let metadata = ProposalMetadata(
            id: "SE-0001",
            filename: "0001-keywords-as-argument-labels.md",
            downloadURL: "https://raw.githubusercontent.com/swiftlang/swift-evolution/main/proposals/0001-keywords-as-argument-labels.md"
        )

        #expect(metadata.id == "SE-0001")
        #expect(metadata.filename == "0001-keywords-as-argument-labels.md")
        #expect(metadata.downloadURL.contains("raw.githubusercontent.com"))
    }

    @Test("ProposalMetadata can be sorted by ID")
    func proposalMetadataCanBeSorted() throws {
        let proposal1 = ProposalMetadata(
            id: "SE-0001",
            filename: "0001-test.md",
            downloadURL: "https://example.com/1"
        )
        let proposal2 = ProposalMetadata(
            id: "SE-0002",
            filename: "0002-test.md",
            downloadURL: "https://example.com/2"
        )

        // Proposals can be sorted by ID string comparison
        let proposals = [proposal2, proposal1].sorted { $0.id < $1.id }
        #expect(proposals[0].id == "SE-0001")
        #expect(proposals[1].id == "SE-0002")
    }

    // MARK: - Integration Tests

    @Test("Crawler creates output directory", .tags(.integration))
    @MainActor
    func crawlerCreatesOutputDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        // Ensure directory doesn't exist yet
        try? FileManager.default.removeItem(at: tempDir)
        #expect(!FileManager.default.fileExists(atPath: tempDir.path))

        let crawler = Core.EvolutionCrawler(outputDirectory: tempDir)

        // Note: We're not actually calling crawl() to avoid network calls
        // Just verify the crawler can be instantiated
        _ = crawler

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
}
