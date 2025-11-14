import Foundation
import DocsuckerShared
import DocsuckerLogging

// MARK: - Swift Evolution Crawler

/// Crawls Swift Evolution proposals from GitHub
@MainActor
public final class SwiftEvolutionCrawler {
    private let outputDirectory: URL
    private let githubAPI = "https://api.github.com"
    private let githubRaw = "https://raw.githubusercontent.com"
    private let repo = "swiftlang/swift-evolution"
    private let branch = "main"

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    // MARK: - Public API

    /// Crawl Swift Evolution proposals
    public func crawl(onProgress: ((EvolutionProgress) -> Void)? = nil) async throws -> EvolutionStatistics {
        var stats = EvolutionStatistics(startTime: Date())

        logInfo("🚀 Starting Swift Evolution crawler")
        logInfo("   Repository: \(repo)")
        logInfo("   Output: \(outputDirectory.path)")

        // Create output directory
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        // Fetch proposals list
        logInfo("\n📋 Fetching proposals list...")
        let proposals = try await fetchProposalsList()
        logInfo("   Found \(proposals.count) proposals")

        // Download each proposal
        for (index, proposal) in proposals.enumerated() {
            do {
                try await downloadProposal(proposal, stats: &stats)

                // Progress callback
                if let onProgress {
                    let progress = EvolutionProgress(
                        current: index + 1,
                        total: proposals.count,
                        proposalID: proposal.id,
                        stats: stats
                    )
                    onProgress(progress)
                }

                // Rate limiting - be respectful to GitHub
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                stats.errors += 1
                logError("Failed to download \(proposal.id): \(error)")
            }
        }

        stats.endTime = Date()

        logInfo("\n✅ Crawl completed!")
        logStatistics(stats)

        return stats
    }

    // MARK: - Private Methods

    private func fetchProposalsList() async throws -> [ProposalMetadata] {
        // Fetch proposals directory listing from GitHub API
        let url = URL(string: "\(githubAPI)/repos/\(repo)/contents/proposals?ref=\(branch)")!

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw EvolutionCrawlerError.invalidResponse
        }

        // Parse JSON response
        let files = try JSONDecoder().decode([GitHubFile].self, from: data)

        // Filter for .md files and extract proposal metadata
        let proposals = files
            .filter { $0.name.hasSuffix(".md") && $0.name.hasPrefix("SE-") }
            .compactMap { file -> ProposalMetadata? in
                guard let id = extractProposalID(from: file.name) else {
                    return nil
                }
                return ProposalMetadata(
                    id: id,
                    filename: file.name,
                    downloadURL: file.download_url
                )
            }
            .sorted { $0.id < $1.id }

        return proposals
    }

    private func downloadProposal(_ proposal: ProposalMetadata, stats: inout EvolutionStatistics) async throws {
        logInfo("📄 [\(stats.totalProposals + 1)] \(proposal.id)")

        // Download markdown content
        guard let url = URL(string: proposal.downloadURL) else {
            throw EvolutionCrawlerError.invalidURL(proposal.downloadURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw EvolutionCrawlerError.invalidEncoding
        }

        // Compute hash for change detection
        _ = HashUtilities.sha256(of: markdown)

        // Save to file
        let outputPath = outputDirectory.appendingPathComponent(proposal.filename)
        let isNew = !FileManager.default.fileExists(atPath: outputPath.path)

        try markdown.write(to: outputPath, atomically: true, encoding: .utf8)

        if isNew {
            stats.newProposals += 1
            logInfo("   ✅ Saved new proposal")
        } else {
            stats.updatedProposals += 1
            logInfo("   ♻️  Updated proposal")
        }

        stats.totalProposals += 1
    }

    private func extractProposalID(from filename: String) -> String? {
        // Extract SE-NNNN from filename like "SE-0001-keywords-as-argument-labels.md"
        let pattern = #"^(SE-\d{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: filename,
                  range: NSRange(filename.startIndex..., in: filename)
              ),
              let range = Range(match.range, in: filename)
        else {
            return nil
        }
        return String(filename[range])
    }

    // MARK: - Logging

    private func logInfo(_ message: String) {
        DocsuckerLogger.evolution.info(message)
        print(message)
    }

    private func logError(_ message: String) {
        let errorMessage = "❌ \(message)"
        DocsuckerLogger.evolution.error(message)
        fputs("\(errorMessage)\n", stderr)
    }

    private func logStatistics(_ stats: EvolutionStatistics) {
        let messages = [
            "📊 Statistics:",
            "   Total proposals: \(stats.totalProposals)",
            "   New: \(stats.newProposals)",
            "   Updated: \(stats.updatedProposals)",
            "   Errors: \(stats.errors)",
            stats.duration.map { "   Duration: \(Int($0))s" } ?? "",
            "",
            "📁 Output: \(outputDirectory.path)",
        ]

        for message in messages where !message.isEmpty {
            DocsuckerLogger.evolution.info(message)
            print(message)
        }
    }
}

// MARK: - Models

struct GitHubFile: Codable {
    let name: String
    let download_url: String
}

struct ProposalMetadata {
    let id: String
    let filename: String
    let downloadURL: String
}

public struct EvolutionStatistics: Sendable {
    public var totalProposals: Int = 0
    public var newProposals: Int = 0
    public var updatedProposals: Int = 0
    public var errors: Int = 0
    public var startTime: Date?
    public var endTime: Date?

    public init(
        totalProposals: Int = 0,
        newProposals: Int = 0,
        updatedProposals: Int = 0,
        errors: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.totalProposals = totalProposals
        self.newProposals = newProposals
        self.updatedProposals = updatedProposals
        self.errors = errors
        self.startTime = startTime
        self.endTime = endTime
    }

    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else {
            return nil
        }
        return end.timeIntervalSince(start)
    }
}

public struct EvolutionProgress: Sendable {
    public let current: Int
    public let total: Int
    public let proposalID: String
    public let stats: EvolutionStatistics

    public var percentage: Double {
        Double(current) / Double(total) * 100
    }
}

// MARK: - Errors

enum EvolutionCrawlerError: Error {
    case invalidResponse
    case invalidURL(String)
    case invalidEncoding
}
