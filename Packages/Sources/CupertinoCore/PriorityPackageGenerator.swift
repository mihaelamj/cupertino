import CupertinoLogging
import CupertinoShared
import Foundation

// swiftlint:disable function_body_length
// Justification: The generate() function orchestrates the complete package analysis workflow:
// scanning documentation, extracting package mentions, categorizing by tier (Apple/SwiftLang/
// Server/Ecosystem), selecting critical packages, and building the output JSON structure.
// Function body length: 64 lines
// Disabling: function_body_length (50 line limit for complex data aggregation)

/// Generates priority package list from Swift.org documentation analysis
public actor PriorityPackageGenerator {
    private let swiftOrgDocsPath: URL
    private let outputPath: URL

    public init(swiftOrgDocsPath: URL, outputPath: URL) {
        self.swiftOrgDocsPath = swiftOrgDocsPath
        self.outputPath = outputPath
    }

    public func generate() async throws -> PriorityPackageList {
        ConsoleLogger.info("🔍 Scanning \(CupertinoConstants.DisplayName.swiftOrg) documentation for package mentions...")

        let packages = try await extractGitHubPackages()

        // Categorize packages
        let applePackages = packages.filter { $0.owner.lowercased() == CupertinoConstants.GitHubOrg.apple }
        let swiftlangPackages = packages.filter { $0.owner.lowercased() == CupertinoConstants.GitHubOrg.swiftlang }
        let serverPackages = packages.filter { $0.owner.lowercased() == CupertinoConstants.GitHubOrg.swiftServer }
        let ecosystemPackages = packages.filter {
            !CupertinoConstants.GitHubOrg.officialOrgs.contains($0.owner.lowercased())
        }

        ConsoleLogger.info("📦 Found \(packages.count) unique GitHub repositories:")
        ConsoleLogger.info("   • \(CupertinoConstants.GitHubOrg.appleDisplay) packages: \(applePackages.count)")
        ConsoleLogger.info("   • \(CupertinoConstants.GitHubOrg.swiftlangDisplay) packages: \(swiftlangPackages.count)")
        ConsoleLogger.info("   • \(CupertinoConstants.GitHubOrg.swiftServerDisplay) packages: \(serverPackages.count)")
        ConsoleLogger.info("   • Ecosystem packages: \(ecosystemPackages.count)")

        // Build priority list
        let priorityList = try await PriorityPackageList(
            version: CupertinoConstants.PriorityPackage.version,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            description: CupertinoConstants.PriorityPackage.listDescription,
            sources: CupertinoConstants.PriorityPackage.sources,
            updatePolicy: CupertinoConstants.PriorityPackage.updatePolicy,
            priorityLevels: PriorityLevels(
                tier1AppleOfficial: TierInfo(
                    description: CupertinoConstants.PriorityPackage.tier1Description,
                    packages: selectCriticalApplePackages(from: applePackages)
                ),
                tier2Swiftlang: TierInfo(
                    description: CupertinoConstants.PriorityPackage.tier2Description,
                    packages: swiftlangPackages.sorted { $0.repo < $1.repo }
                ),
                tier3SwiftServer: TierInfo(
                    description: CupertinoConstants.PriorityPackage.tier3Description,
                    packages: serverPackages.sorted { $0.repo < $1.repo }
                ),
                tier4Ecosystem: TierInfo(
                    description: CupertinoConstants.PriorityPackage.tier4Description,
                    packages: selectTopEcosystemPackages(from: ecosystemPackages)
                )
            ),
            stats: PackageStats(
                totalApplePackagesInSwiftorg: applePackages.count,
                totalSwiftlangPackagesInSwiftorg: swiftlangPackages.count,
                totalEcosystemPackagesInSwiftorg: ecosystemPackages.count,
                totalUniqueReposFound: packages.count,
                sourceFilesScanned: countMarkdownFiles()
            ),
            notes: CupertinoConstants.PriorityPackage.notes
        )

        // Save to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(priorityList)
        try data.write(to: outputPath)

        ConsoleLogger.info("💾 Saved priority package list to: \(outputPath.path)")

        return priorityList
    }

    private func extractGitHubPackages() async throws -> [PriorityPackageInfo] {
        var packages: [String: PriorityPackageInfo] = [:]

        // Get all markdown files using DispatchQueue to avoid async context issues
        let allURLs: [URL] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                guard let enumerator = fileManager.enumerator(
                    at: self.swiftOrgDocsPath,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.resume(throwing: PriorityPackageError.cannotReadDirectory(self.swiftOrgDocsPath.path))
                    return
                }

                var urls: [URL] = []
                for case let fileURL as URL in enumerator where fileURL.pathExtension == "md" {
                    urls.append(fileURL)
                }
                continuation.resume(returning: urls)
            }
        }

        // Process each file
        for fileURL in allURLs {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            let foundPackages = extractGitHubURLs(from: content)
            for pkg in foundPackages {
                packages["\(pkg.owner)/\(pkg.repo)"] = pkg
            }
        }

        return Array(packages.values).sorted { $0.owner < $1.owner || ($0.owner == $1.owner && $0.repo < $1.repo) }
    }

    private func extractGitHubURLs(from content: String) -> [PriorityPackageInfo] {
        guard let regex = try? NSRegularExpression(pattern: CupertinoConstants.Pattern.githubURLLenient) else {
            return []
        }

        let matches = regex.matches(
            in: content,
            range: NSRange(content.startIndex..., in: content)
        )

        var packages: [PriorityPackageInfo] = []
        for match in matches {
            guard match.numberOfRanges == 3,
                  let ownerRange = Range(match.range(at: 1), in: content),
                  let repoRange = Range(match.range(at: 2), in: content) else {
                continue
            }

            let owner = String(content[ownerRange])
            var repo = String(content[repoRange])

            // Clean up trailing punctuation
            repo = repo.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]"))

            // Skip placeholder URLs
            guard !owner.hasPrefix("<"), !repo.hasPrefix("<") else {
                continue
            }

            packages.append(PriorityPackageInfo(
                owner: owner,
                repo: repo,
                url: CupertinoConstants.URLTemplate.githubRepo(owner: owner, repo: repo)
            ))
        }

        return packages
    }

    private func selectCriticalApplePackages(from all: [PriorityPackageInfo]) -> [PriorityPackageInfo] {
        // Priority Apple packages (most commonly used)
        let criticalRepos = CupertinoConstants.CriticalApplePackages.repositories

        return all.filter { pkg in
            criticalRepos.contains(pkg.repo.lowercased())
        }.sorted { $0.repo < $1.repo }
    }

    private func selectTopEcosystemPackages(from all: [PriorityPackageInfo]) -> [PriorityPackageInfo] {
        // Well-known ecosystem packages
        let knownPackages = CupertinoConstants.KnownEcosystemPackages.repositories

        return all.filter { pkg in
            knownPackages.contains("\(pkg.owner)/\(pkg.repo)")
        }.sorted { $0.repo < $1.repo }
    }

    private func countMarkdownFiles() async throws -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default
                guard let enumerator = fileManager.enumerator(
                    at: self.swiftOrgDocsPath,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.resume(returning: 0)
                    return
                }

                var count = 0
                for case let fileURL as URL in enumerator where fileURL.pathExtension == "md" {
                    count += 1
                }
                continuation.resume(returning: count)
            }
        }
    }
}

// MARK: - Data Models

public struct PriorityPackageList: Codable, Sendable {
    let version: String
    let generatedAt: String
    let description: String
    let sources: [String]
    let updatePolicy: String
    let priorityLevels: PriorityLevels
    let stats: PackageStats
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case description
        case sources
        case updatePolicy = "update_policy"
        case priorityLevels = "priority_levels"
        case stats
        case notes
    }
}

public struct PriorityLevels: Codable, Sendable {
    let tier1AppleOfficial: TierInfo
    let tier2Swiftlang: TierInfo
    let tier3SwiftServer: TierInfo
    let tier4Ecosystem: TierInfo

    enum CodingKeys: String, CodingKey {
        case tier1AppleOfficial = "tier1_apple_official"
        case tier2Swiftlang = "tier2_swiftlang"
        case tier3SwiftServer = "tier3_swift_server"
        case tier4Ecosystem = "tier4_ecosystem"
    }
}

public struct TierInfo: Codable, Sendable {
    let description: String
    let packages: [PriorityPackageInfo]
}

public struct PriorityPackageInfo: Codable, Hashable, Sendable {
    let owner: String
    let repo: String
    let url: String
}

public struct PackageStats: Codable, Sendable {
    let totalApplePackagesInSwiftorg: Int
    let totalSwiftlangPackagesInSwiftorg: Int
    let totalEcosystemPackagesInSwiftorg: Int
    let totalUniqueReposFound: Int
    let sourceFilesScanned: Int

    enum CodingKeys: String, CodingKey {
        case totalApplePackagesInSwiftorg = "total_apple_packages_in_swiftorg"
        case totalSwiftlangPackagesInSwiftorg = "total_swiftlang_packages_in_swiftorg"
        case totalEcosystemPackagesInSwiftorg = "total_ecosystem_packages_in_swiftorg"
        case totalUniqueReposFound = "total_unique_repos_found"
        case sourceFilesScanned = "source_files_scanned"
    }
}

public enum PriorityPackageError: Error, CustomStringConvertible {
    case cannotReadDirectory(String)

    public var description: String {
        switch self {
        case .cannotReadDirectory(let path):
            return "Cannot read directory: \(path)"
        }
    }
}
