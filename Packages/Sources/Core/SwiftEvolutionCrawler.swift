import Foundation
import Logging
import Shared

// MARK: - Swift Evolution Crawler

/// Crawls Swift Evolution proposals from GitHub
extension Core {
    @MainActor
    public final class EvolutionCrawler {
        private let outputDirectory: URL
        private let onlyAccepted: Bool
        private let githubAPI = Shared.Constants.BaseURL.githubAPI
        private let githubRaw = Shared.Constants.BaseURL.githubRaw
        private let repo = Shared.Constants.SwiftEvolution.repository
        private let branch = Shared.Constants.SwiftEvolution.branch

        public init(outputDirectory: URL, onlyAccepted: Bool = false) {
            self.outputDirectory = outputDirectory
            self.onlyAccepted = onlyAccepted
        }

        // MARK: - Public API

        /// Crawl Swift Evolution proposals
        public func crawl(
            limit: Int? = nil, // Internal use only - for testing
            onProgress: (@Sendable (EvolutionProgress) -> Void)? = nil
        ) async throws -> EvolutionStatistics {
            var stats = EvolutionStatistics(startTime: Date())

            logInfo("🚀 Starting Swift Evolution crawler")
            logInfo("   Repository: \(repo)")
            logInfo("   Output: \(outputDirectory.path)")
            if let limit {
                logInfo("   Limit: \(limit) proposals")
            }

            // Create output directory
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            // Fetch proposals list
            logInfo("\n📋 Fetching proposals list...")
            let proposals = try await fetchProposalsList()
            logInfo("   Found \(proposals.count) proposals")

            // Apply limit if specified
            let proposalsToDownload = if let limit {
                Array(proposals.prefix(limit))
            } else {
                proposals
            }

            if limit != nil, proposalsToDownload.count < proposals.count {
                logInfo("   Limiting to first \(proposalsToDownload.count) proposals")
            }

            // Download each proposal
            for (index, proposal) in proposalsToDownload.enumerated() {
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
                    try await Task.sleep(for: Shared.Constants.Delay.swiftEvolution)
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
            // Fetch SE proposals from proposals/ directory
            let seProposals = try await fetchProposalsFromDirectory(
                path: Shared.Constants.SwiftEvolution.proposalsSubdirectory,
                prefix: Shared.Constants.SwiftEvolution.seIDPrefix
            )

            // Fetch ST proposals from proposals/testing/ directory
            let stProposals = try await fetchProposalsFromDirectory(
                path: Shared.Constants.SwiftEvolution.testingSubdirectory,
                prefix: Shared.Constants.SwiftEvolution.stIDPrefix
            )

            return (seProposals + stProposals).sorted { $0.id < $1.id }
        }

        private func fetchProposalsFromDirectory(
            path: String,
            prefix: String
        ) async throws -> [ProposalMetadata] {
            let url = URL(string: "\(githubAPI)/repos/\(repo)/contents/\(path)?ref=\(branch)")!

            var request = URLRequest(url: url)
            request.setValue(
                Shared.Constants.HTTPHeader.githubAccept,
                forHTTPHeaderField: Shared.Constants.HTTPHeader.accept
            )

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw EvolutionCrawlerError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                // Only treat 404 as "directory not found" for the testing subdirectory
                if httpResponse.statusCode == 404, path == Shared.Constants.SwiftEvolution.testingSubdirectory {
                    logInfo("   Testing proposals directory (\(path)) not found, skipping")
                    return []
                }
                throw EvolutionCrawlerError.invalidResponse
            }

            let files = try JSONDecoder().decode([GitHubFile].self, from: data)

            return files.compactMap { file -> ProposalMetadata? in
                guard let downloadURL = file.downloadURL else { return nil }
                guard file.name.hasSuffix(Shared.Constants.FileName.markdownExtension) else { return nil }
                guard let id = extractProposalID(from: file.name, prefix: prefix) else { return nil }
                return ProposalMetadata(id: id, filename: file.name, downloadURL: downloadURL)
            }
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

            // Check status if filtering for accepted only
            if onlyAccepted {
                let status = extractStatus(from: markdown)
                if !isAcceptedStatus(status) {
                    logInfo("   ⏭️  Skipped (status: \(status ?? "unknown"))")
                    stats.totalProposals += 1
                    return
                }
            }

            // Compute hash for change detection
            _ = HashUtilities.sha256(of: markdown)

            // Save to file with proposal ID prefix (e.g., "SE-0001.md" or "ST-0001.md")
            let filename = "\(proposal.id)\(Shared.Constants.FileName.markdownExtension)"
            let outputPath = outputDirectory.appendingPathComponent(filename)
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

        func extractProposalID(from filename: String, prefix: String = "SE") -> String? {
            // Extract proposal number from filename
            // Handles: "0001-keywords-as-argument-labels.md" -> "SE-0001" (or "ST-0001" for testing)
            // Also handles: "SE-0001-keywords-as-argument-labels.md" -> "SE-0001"
            guard let regex = try? NSRegularExpression(pattern: Shared.Constants.Pattern.seProposalNumber),
                  let match = regex.firstMatch(
                      in: filename,
                      range: NSRange(filename.startIndex..., in: filename)
                  ),
                  match.numberOfRanges > 1,
                  let numberRange = Range(match.range(at: 1), in: filename)
            else {
                return nil
            }
            let number = String(filename[numberRange])
            return "\(prefix)-\(number)"
        }

        func extractStatus(from markdown: String) -> String? {
            // Extract status from markdown content
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

        func isAcceptedStatus(_ status: String?) -> Bool {
            guard let status = status?.lowercased() else {
                return false
            }
            // Accept proposals that are "Implemented", "Accepted", or "Accepted with revisions"
            return status.contains("implemented") ||
                status.contains("accepted")
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            Log.info(message, category: .evolution)
        }

        private func logError(_ message: String) {
            let errorMessage = "❌ \(message)"
            Log.error(errorMessage, category: .evolution)
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
                Log.info(message, category: .evolution)
            }
        }
    }
}

// MARK: - Models

struct GitHubFile: Codable {
    let name: String
    let downloadURL: String? // Optional - directories have null download_url

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "download_url"
    }
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
