import Foundation
import Logging
import Shared

// MARK: - GitHub Sample Code Fetcher

/// Fetches Apple sample code from the public GitHub repository
/// This is faster and more reliable than scraping Apple's website
public final class GitHubSampleCodeFetcher {
    private let outputDirectory: URL
    private let repoOwner = "mihaelamj"
    private let repoName = "cupertino-sample-code"
    private let branch = "main"

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    // MARK: - Public API

    /// Clone or pull the sample code repository
    public func fetch(onProgress: ((FetchProgress) -> Void)? = nil) async throws -> FetchStatistics {
        var stats = FetchStatistics(startTime: Date())

        let repoURL = "https://github.com/\(repoOwner)/\(repoName).git"
        let repoPath = outputDirectory.appendingPathComponent(repoName)

        logInfo("🚀 Fetching Apple sample code from GitHub")
        logInfo("   Repository: \(repoURL)")
        logInfo("   Output: \(repoPath.path)")

        // Create output directory
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        // Check if repo already exists
        let gitDir = repoPath.appendingPathComponent(".git")
        if FileManager.default.fileExists(atPath: gitDir.path) {
            // Pull latest changes
            logInfo("\n📥 Repository exists, pulling latest changes...")
            try await pullRepository(at: repoPath)
            stats.action = .pulled
        } else {
            // Clone the repository
            logInfo("\n📦 Cloning repository (this may take a while, ~10GB with LFS)...")
            try await cloneRepository(to: repoPath, from: repoURL)
            stats.action = .cloned
        }

        // Count projects
        stats.projectCount = try countProjects(in: repoPath)

        stats.endTime = Date()

        logInfo("\n✅ Fetch completed!")
        logStatistics(stats, repoPath: repoPath)

        return stats
    }

    /// List all available sample code projects
    public func listProjects() async throws -> [SampleProject] {
        let repoPath = outputDirectory.appendingPathComponent(repoName)

        guard FileManager.default.fileExists(atPath: repoPath.path) else {
            throw GitHubFetcherError.repositoryNotCloned
        }

        var projects: [SampleProject] = []
        let contents = try FileManager.default.contentsOfDirectory(
            at: repoPath,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for item in contents {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !item.lastPathComponent.hasPrefix(".") else {
                continue
            }

            // Check if it's a valid project (has xcodeproj or Package.swift)
            let hasXcodeproj = try FileManager.default.contentsOfDirectory(atPath: item.path)
                .contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
            let hasPackageSwift = FileManager.default.fileExists(
                atPath: item.appendingPathComponent("Package.swift").path
            )

            if hasXcodeproj || hasPackageSwift {
                let project = SampleProject(
                    id: item.lastPathComponent,
                    name: formatProjectName(item.lastPathComponent),
                    path: item
                )
                projects.append(project)
            }
        }

        return projects.sorted { $0.name < $1.name }
    }

    /// Get path to a specific project
    public func projectPath(for projectId: String) -> URL {
        outputDirectory
            .appendingPathComponent(repoName)
            .appendingPathComponent(projectId)
    }

    // MARK: - Private Methods

    private func cloneRepository(to destination: URL, from url: String) async throws {
        // Remove existing directory if it exists but isn't a git repo
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", "--depth", "1", url, destination.path]
        process.currentDirectoryURL = outputDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GitHubFetcherError.cloneFailed(output)
        }
    }

    private func pullRepository(at path: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["pull", "--ff-only"]
        process.currentDirectoryURL = path

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GitHubFetcherError.pullFailed(output)
        }
    }

    private func countProjects(in repoPath: URL) throws -> Int {
        let contents = try FileManager.default.contentsOfDirectory(
            at: repoPath,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        return contents.filter { item in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
                && !item.lastPathComponent.hasPrefix(".")
        }.count
    }

    private func formatProjectName(_ slug: String) -> String {
        // Convert slug like "swiftui-fruta-sample" to "SwiftUI Fruta Sample"
        slug
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in
                let lowercased = word.lowercased()
                // Preserve common acronyms
                let acronyms = [
                    "swiftui",
                    "uikit",
                    "arkit",
                    "avfoundation",
                    "coreml",
                    "realitykit",
                    "healthkit",
                    "mapkit",
                    "coredata",
                    "swiftdata",
                    "visionos",
                    "ios",
                    "macos",
                    "tvos",
                    "watchos",
                ]
                if acronyms.contains(lowercased) {
                    return lowercased.capitalized
                }
                return word.capitalized
            }
            .joined(separator: " ")
    }

    // MARK: - Logging

    private func logInfo(_ message: String) {
        Log.info(message, category: .samples)
    }

    private func logStatistics(_ stats: FetchStatistics, repoPath: URL) {
        let messages = [
            "📊 Statistics:",
            "   Action: \(stats.action.description)",
            "   Projects: \(stats.projectCount)",
            stats.duration.map { "   Duration: \(Int($0))s" } ?? "",
            "",
            "📁 Output: \(repoPath.path)",
        ]

        for message in messages where !message.isEmpty {
            Log.info(message, category: .samples)
        }
    }
}

// MARK: - Models

public struct SampleProject: Sendable {
    public let id: String
    public let name: String
    public let path: URL

    public init(id: String, name: String, path: URL) {
        self.id = id
        self.name = name
        self.path = path
    }
}

public struct FetchStatistics: Sendable {
    public var action: FetchAction = .cloned
    public var projectCount: Int = 0
    public var startTime: Date?
    public var endTime: Date?

    public init(
        action: FetchAction = .cloned,
        projectCount: Int = 0,
        startTime: Date? = nil,
        endTime: Date? = nil
    ) {
        self.action = action
        self.projectCount = projectCount
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

public enum FetchAction: Sendable {
    case cloned
    case pulled

    public var description: String {
        switch self {
        case .cloned: return "Cloned repository"
        case .pulled: return "Pulled latest changes"
        }
    }
}

public struct FetchProgress: Sendable {
    public let message: String
    public let percentage: Double?

    public init(message: String, percentage: Double? = nil) {
        self.message = message
        self.percentage = percentage
    }
}

// MARK: - Errors

public enum GitHubFetcherError: Error, LocalizedError {
    case repositoryNotCloned
    case cloneFailed(String)
    case pullFailed(String)
    case gitNotInstalled

    public var errorDescription: String? {
        switch self {
        case .repositoryNotCloned:
            return "Sample code repository not cloned. Run 'cupertino fetch-samples' first."
        case .cloneFailed(let output):
            return "Failed to clone repository: \(output)"
        case .pullFailed(let output):
            return "Failed to pull repository: \(output)"
        case .gitNotInstalled:
            return "Git is not installed. Please install git and try again."
        }
    }
}
