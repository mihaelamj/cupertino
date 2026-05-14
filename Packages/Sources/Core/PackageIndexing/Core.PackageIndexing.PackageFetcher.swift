import CoreProtocols
import Foundation
import Logging
import SharedConstants
import SharedCore
import SharedUtils

// MARK: - Package Fetcher

// swiftlint:disable type_body_length
// Justification: This actor manages the complete Swift package fetching and enrichment workflow.
// It coordinates multiple async operations: downloading package lists, enriching with GitHub data,
// caching results, checkpoint/resume logic, and rate limiting. The logic is cohesive and sequential.
// File length: 523 lines | Type body length: 326 lines
// Disabling: file_length (400 line limit), type_body_length (250 line limit)

/// Fetches Swift packages from SwiftPackageIndex and enriches with GitHub metadata
extension Core.PackageIndexing {
    public actor PackageFetcher {
        private let packageListURL = try! URL(knownGood: Shared.Constants.BaseURL.swiftPackageList)
        private let outputDirectory: URL
        private let limit: Int?
        private let resumeFromCheckpoint: Bool
        private var starCache: [String: Int] = [:] // Cache star counts to avoid double-fetching

        public init(outputDirectory: URL, limit: Int? = nil, resume: Bool = false) {
            self.outputDirectory = outputDirectory
            self.limit = limit
            resumeFromCheckpoint = resume
        }

        // MARK: - Public API

        /// Fetch packages and enrich with GitHub metadata
        public func fetch(
            onProgress: (@Sendable (Progress) -> Void)? = nil
        ) async throws -> Statistics {
            var stats = Statistics(startTime: Date())

            try setupOutputDirectory()
            let packageURLs = try await fetchAndSortPackageList()
            let (packages, _) = try await processPackages(
                packageURLs,
                stats: &stats,
                onProgress: onProgress
            )

            let sortedPackages = packages
                .filter { $0.error == nil || $0.stars > 0 }
                .sorted { $0.stars > $1.stars }

            try saveResults(sortedPackages, processedCount: packages.count, errors: stats.errors)

            stats.endTime = Date()
            stats.totalPackages = sortedPackages.count

            logCompletionSummary(sortedPackages, stats: stats)

            return stats
        }

        // MARK: - Private Methods - Setup

        private func setupOutputDirectory() throws {
            logInfo("📦 Fetching Swift packages from SwiftPackageIndex...")
            logInfo("   Package list: \(packageListURL.absoluteString)")
            logInfo("   Output: \(outputDirectory.path)")
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        private func fetchAndSortPackageList() async throws -> [String] {
            logInfo("\n📥 Downloading package list...")
            var packageURLs = try await downloadPackageList()
            logInfo("   Found \(packageURLs.count) packages")

            // Try to load priority packages
            let priorityURLs = loadPriorityPackages()
            if !priorityURLs.isEmpty {
                logInfo("\n⚡ Loaded \(priorityURLs.count) priority packages (will be processed first)")
            }

            logInfo("\n⭐ Pre-fetching star counts to sort by popularity...")
            packageURLs = try await sortPackagesByStars(packageURLs, priorityURLs: priorityURLs)
            logInfo("   ✓ Packages sorted by priority and star count")

            return packageURLs
        }

        private func processPackages(
            _ packageURLs: [String],
            stats: inout Statistics,
            onProgress: (@Sendable (Progress) -> Void)?
        ) async throws -> ([PackageInfo], Bool) {
            var packages = try loadCheckpointIfNeeded()
            let startIndex = packages.count
            let totalToProcess = limit.map { min($0, packageURLs.count) } ?? packageURLs.count

            logInfo("\n🔍 Fetching metadata for \(totalToProcess) packages...\n")

            var rateLimited = false

            for index in startIndex..<totalToProcess {
                let packageURL = packageURLs[index]

                guard let (owner, repo) = extractOwnerRepo(from: packageURL) else {
                    logError("Invalid package URL: \(packageURL)")
                    stats.errors += 1
                    continue
                }

                logProgress(index: index, total: totalToProcess, owner: owner, repo: repo)

                do {
                    let packageInfo = try await fetchGitHubMetadata(owner: owner, repo: repo)
                    packages.append(packageInfo)
                    stats.successfulFetches += 1
                } catch Error.rateLimited {
                    rateLimited = try handleRateLimit(packages: packages, index: index, total: totalToProcess)
                    break
                } catch {
                    try handleFetchError(error, owner: owner, repo: repo, packages: &packages, stats: &stats)
                }

                onProgress?(Progress(
                    current: index + 1,
                    total: totalToProcess,
                    packageName: "\(owner)/\(repo)",
                    stats: stats
                ))

                try await applyRateLimit(index: index)
            }

            if !rateLimited {
                try? saveCheckpoint(packages: packages, processedCount: totalToProcess)
            }

            return (packages, rateLimited)
        }

        private func loadCheckpointIfNeeded() throws -> [PackageInfo] {
            guard resumeFromCheckpoint, let checkpoint = try? loadCheckpoint() else {
                return []
            }
            logInfo("📂 Resuming from checkpoint: \(checkpoint.processedCount) packages processed")
            return checkpoint.packages
        }

        private func logProgress(index: Int, total: Int, owner: String, repo: String) {
            if (index + 1) % 100 == 0 {
                logInfo("\n[\(index + 1)/\(total)] Fetching \(owner)/\(repo)...")
                logInfo("   💾 Saving checkpoint...")
            } else if (index + 1) % 10 == 0 {
                logInfo("[\(index + 1)/\(total)] \(owner)/\(repo)")
            }
        }

        private func handleRateLimit(packages: [PackageInfo], index: Int, total: Int) throws -> Bool {
            logError("\n⚠️  Rate limited at package \(index + 1)/\(total)")
            logInfo("   💾 Checkpoint saved")
            logInfo("   ⏸️  Wait 60 minutes or use GitHub token for higher limits")
            try? saveCheckpoint(packages: packages, processedCount: index)
            return true
        }

        private func handleFetchError(
            _ error: Swift.Error,
            owner: String,
            repo: String,
            packages: inout [PackageInfo],
            stats: inout Statistics
        ) throws {
            let errorType = (error as? Error == .notFound) ? "not_found" : "fetch_failed"
            if errorType == "fetch_failed" {
                logError("Failed to fetch \(owner)/\(repo): \(error)")
            }

            packages.append(PackageInfo(
                owner: owner,
                repo: repo,
                stars: 0,
                description: nil,
                url: Shared.Constants.URLTemplate.githubRepo(owner: owner, repo: repo),
                archived: false,
                fork: false,
                updatedAt: nil,
                language: nil,
                license: nil,
                error: errorType
            ))
            stats.errors += 1
        }

        private func applyRateLimit(index: Int) async throws {
            if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                try await Task.sleep(for: Shared.Constants.Delay.packageFetchHighPriority)
            } else {
                try await Task.sleep(for: Shared.Constants.Delay.packageFetchNormal)
            }
        }

        private func saveResults(_ packages: [PackageInfo], processedCount: Int, errors: Int) throws {
            let output = FetchOutput(
                totalPackages: packages.count,
                totalProcessed: processedCount,
                errors: errors,
                generatedAt: Date(),
                packages: packages
            )

            let outputFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.packagesWithStars)
            try saveJSON(output, to: outputFile)
        }

        private func logCompletionSummary(_ packages: [PackageInfo], stats: Statistics) {
            logInfo("\n✅ Fetch completed!")
            logInfo("   Total packages: \(packages.count)")
            logInfo("   Successful: \(stats.successfulFetches)")
            logInfo("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                logInfo("   Duration: \(Int(duration))s")
            }
            let outputFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.packagesWithStars)
            logInfo("\n📁 Output: \(outputFile.path)")

            logInfo("\nTop \(Shared.Constants.Limit.topPackagesDisplay) packages by stars:")
            for (index, pkg) in packages.prefix(Shared.Constants.Limit.topPackagesDisplay).enumerated() {
                let archived = pkg.archived ? " [ARCHIVED]" : ""
                let fork = pkg.fork ? " [FORK]" : ""
                logInfo(String(
                    format: "  %2d. %-50s ⭐ %6d%@%@",
                    index + 1,
                    "\(pkg.owner)/\(pkg.repo)",
                    pkg.stars,
                    archived,
                    fork
                ))
            }
        }

        // MARK: - Private Methods - Priority Packages

        private func loadPriorityPackages() -> [String] {
            let priorityFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.priorityPackages)

            guard FileManager.default.fileExists(atPath: priorityFile.path),
                  let data = try? Data(contentsOf: priorityFile),
                  let priorityList = try? JSONDecoder().decode(PriorityPackageGenerator.PriorityPackageList.self, from: data) else {
                return []
            }

            // Collect URLs in priority order: Tier 1 → Tier 2 → Tier 3 → Tier 4
            var urls: [String] = []
            urls.append(contentsOf: priorityList.priorityLevels.tier1AppleOfficial.packages.map(\.url))
            urls.append(contentsOf: priorityList.priorityLevels.tier2Swiftlang.packages.map(\.url))
            urls.append(contentsOf: priorityList.priorityLevels.tier3SwiftServer.packages.map(\.url))
            urls.append(contentsOf: priorityList.priorityLevels.tier4Ecosystem.packages.map(\.url))

            return urls
        }

        // MARK: - Private Methods - Sorting

        private func sortPackagesByStars(_ packageURLs: [String], priorityURLs: [String]) async throws -> [String] {
            // Separate priority packages from regular packages
            let prioritySet = Set(priorityURLs)
            let regularURLs = packageURLs.filter { !prioritySet.contains($0) }

            // Quick fetch: only get star counts (much lighter than full metadata)
            var packageStars: [(url: String, stars: Int)] = []

            for (index, url) in regularURLs.enumerated() {
                guard let (owner, repo) = extractOwnerRepo(from: url) else {
                    packageStars.append((url, 0))
                    continue
                }

                // Progress every 100
                if (index + 1) % 100 == 0 {
                    logInfo("   [\(index + 1)/\(regularURLs.count)] Fetched star counts...")
                }

                // Fetch only stars (lightweight)
                do {
                    let stars = try await fetchStarCount(owner: owner, repo: repo)
                    packageStars.append((url, stars))

                    // Cache the star count for later reuse
                    starCache["\(owner)/\(repo)"] = stars
                } catch {
                    packageStars.append((url, 0))
                    starCache["\(owner)/\(repo)"] = 0
                }

                // Rate limiting
                if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    try await Task.sleep(for: Shared.Constants.Delay.packageStarsHighPriority)
                } else {
                    try await Task.sleep(for: Shared.Constants.Delay.packageStarsNormal)
                }
            }

            // Sort regular packages by stars descending
            let sortedRegular = packageStars.sorted { $0.stars > $1.stars }.map(\.url)

            // Return priority packages first, then sorted regular packages
            return priorityURLs + sortedRegular
        }

        private func fetchStarCount(owner: String, repo: String) async throws -> Int {
            let url = try URL(knownGood: "\(Shared.Constants.BaseURL.githubAPIRepos)/\(owner)/\(repo)")

            var request = URLRequest(url: url)
            request.setValue(Shared.Constants.HTTPHeader.githubAccept, forHTTPHeaderField: "Accept")
            request.setValue(Shared.Constants.App.userAgent, forHTTPHeaderField: "User-Agent")

            if let token = ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.githubToken] {
                request.setValue("Bearer \(token)", forHTTPHeaderField: Shared.Constants.HTTPHeader.authorization)
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return 0
            }

            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let stars = json["stargazers_count"] as? Int {
                    return stars
                }
            }

            return 0
        }

        private func downloadPackageList() async throws -> [String] {
            let (data, _) = try await URLSession.shared.data(from: packageListURL)
            return try JSONDecoder().decode([String].self, from: data)
        }

        private func extractOwnerRepo(from githubURL: String) -> (String, String)? {
            // Match: https://github.com/owner/repo.git or https://github.com/owner/repo
            guard let regex = try? NSRegularExpression(pattern: Shared.Constants.Pattern.githubURL),
                  let match = regex.firstMatch(in: githubURL, range: NSRange(githubURL.startIndex..., in: githubURL)),
                  let ownerRange = Range(match.range(at: 1), in: githubURL),
                  let repoRange = Range(match.range(at: 2), in: githubURL)
            else {
                return nil
            }

            return (String(githubURL[ownerRange]), String(githubURL[repoRange]))
        }

        private func fetchGitHubMetadata(owner: String, repo: String) async throws -> PackageInfo {
            let cacheKey = "\(owner)/\(repo)"
            let request = try createGitHubRequest(owner: owner, repo: repo)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.invalidResponse
            }

            try validateHTTPResponse(httpResponse)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let repoData = try decoder.decode(GitHubRepository.self, from: data)

            let stars = starCache[cacheKey] ?? repoData.stargazersCount
            return createPackageInfo(owner: owner, repo: repo, repoData: repoData, stars: stars)
        }

        private func createGitHubRequest(owner: String, repo: String) throws -> URLRequest {
            let url = try URL(knownGood: "\(Shared.Constants.BaseURL.githubAPIRepos)/\(owner)/\(repo)")
            var request = URLRequest(url: url)
            request.setValue(Shared.Constants.HTTPHeader.githubAccept, forHTTPHeaderField: "Accept")
            request.setValue(Shared.Constants.App.userAgent, forHTTPHeaderField: "User-Agent")

            if let token = ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.githubToken] {
                request.setValue("Bearer \(token)", forHTTPHeaderField: Shared.Constants.HTTPHeader.authorization)
            }

            return request
        }

        private func validateHTTPResponse(_ response: HTTPURLResponse) throws {
            switch response.statusCode {
            case 200:
                return
            case 404:
                throw Error.notFound
            case 403:
                if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                   let remainingInt = Int(remaining),
                   remainingInt == 0 {
                    throw Error.rateLimited
                }
                throw Error.forbidden
            default:
                throw Error.httpError(response.statusCode)
            }
        }

        private func createPackageInfo(
            owner: String,
            repo: String,
            repoData: GitHubRepository,
            stars: Int
        ) -> PackageInfo {
            PackageInfo(
                owner: owner,
                repo: repo,
                stars: stars,
                description: repoData.description,
                url: repoData.htmlUrl,
                archived: repoData.archived,
                fork: repoData.fork,
                updatedAt: repoData.updatedAt,
                language: repoData.language,
                license: repoData.license?.spdxId
            )
        }

        private func loadCheckpoint() throws -> Checkpoint {
            let checkpointFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.checkpoint)
            let data = try Data(contentsOf: checkpointFile)
            return try JSONDecoder().decode(Checkpoint.self, from: data)
        }

        private func saveCheckpoint(packages: [PackageInfo], processedCount: Int) throws {
            let checkpoint = Checkpoint(
                processedCount: processedCount,
                packages: packages,
                timestamp: Date()
            )
            let checkpointFile = outputDirectory.appendingPathComponent(Shared.Constants.FileName.checkpoint)
            try saveJSON(checkpoint, to: checkpointFile)
        }

        private func saveJSON(_ value: some Encodable, to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            try data.write(to: url)
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            Logging.Log.info(message, category: .packages)
        }

        private func logError(_ message: String) {
            Logging.Log.error(message, category: .packages)
        }
    }
}

// MARK: - Models

extension Core.PackageIndexing.PackageFetcher {
    public struct PackageInfo: Codable, Sendable {
        public let owner: String
        public let repo: String
        public let stars: Int
        public let description: String?
        public let url: String
        public let archived: Bool
        public let fork: Bool
        public let updatedAt: String?
        public let language: String?
        public let license: String?
        public let error: String?

        public init(
            owner: String,
            repo: String,
            stars: Int,
            description: String?,
            url: String,
            archived: Bool,
            fork: Bool,
            updatedAt: String?,
            language: String?,
            license: String?,
            error: String? = nil
        ) {
            self.owner = owner
            self.repo = repo
            self.stars = stars
            self.description = description
            self.url = url
            self.archived = archived
            self.fork = fork
            self.updatedAt = updatedAt
            self.language = language
            self.license = license
            self.error = error
        }
    }

    public struct FetchOutput: Codable, Sendable {
        public let totalPackages: Int
        public let totalProcessed: Int
        public let errors: Int
        public let generatedAt: Date
        public let packages: [PackageInfo]
    }

    public struct Checkpoint: Codable, Sendable {
        public let processedCount: Int
        public let packages: [PackageInfo]
        public let timestamp: Date
    }

    public struct Statistics: Sendable {
        public var totalPackages: Int = 0
        public var successfulFetches: Int = 0
        public var errors: Int = 0
        public var startTime: Date?
        public var endTime: Date?

        public var duration: TimeInterval? {
            guard let start = startTime, let end = endTime else { return nil }
            return end.timeIntervalSince(start)
        }
    }

    public struct Progress: Sendable {
        public let current: Int
        public let total: Int
        public let packageName: String
        public let stats: Statistics

        public var percentage: Double {
            Double(current) / Double(total) * 100
        }
    }

    enum Error: Swift.Error, Equatable {
        case rateLimited
        case notFound
        case forbidden
        case invalidResponse
        case httpError(Int)
    }
}

// MARK: - GitHub API Models

private struct GitHubRepository: Codable {
    let stargazersCount: Int
    let description: String?
    let htmlUrl: String
    let archived: Bool
    let fork: Bool
    let updatedAt: String
    let language: String?
    let license: GitHubLicense?
}

private struct GitHubLicense: Codable {
    let spdxId: String
}
