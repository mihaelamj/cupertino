import ArgumentParser
import Foundation
import Logging
import Shared

// MARK: - Release Command

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Package and upload databases to GitHub Releases"
    )

    @Option(name: .long, help: "Base directory containing databases")
    var baseDir: String?

    @Option(name: .long, help: "GitHub repository (owner/repo)")
    var repo: String = "mihaelamj/cupertino-docs"

    @Flag(name: .long, help: "Create release without uploading (dry run)")
    var dryRun: Bool = false

    // MARK: - Constants

    private static let searchDBFilename = "search.db"
    private static let samplesDBFilename = "samples.db"

    private static var version: String {
        Shared.Constants.App.version
    }

    private static var releaseTag: String {
        "v\(version)"
    }

    private static var zipFilename: String {
        "cupertino-databases-\(releaseTag).zip"
    }

    // MARK: - Run

    mutating func run() async throws {
        Logging.ConsoleLogger.info("📦 Cupertino Release \(Self.releaseTag)\n")

        let baseURL = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory

        let searchDBURL = baseURL.appendingPathComponent(Self.searchDBFilename)
        let samplesDBURL = baseURL.appendingPathComponent(Self.samplesDBFilename)

        // Verify databases exist
        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            throw ReleaseError.missingDatabase(Self.searchDBFilename, baseURL.path)
        }
        guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
            throw ReleaseError.missingDatabase(Self.samplesDBFilename, baseURL.path)
        }

        // Get database sizes
        let searchSize = try fileSize(at: searchDBURL)
        let samplesSize = try fileSize(at: samplesDBURL)
        Logging.ConsoleLogger.info("📊 Database sizes:")
        Logging.ConsoleLogger.info("   search.db:  \(formatBytes(searchSize))")
        Logging.ConsoleLogger.info("   samples.db: \(formatBytes(samplesSize))")

        // Create zip
        let zipURL = baseURL.appendingPathComponent(Self.zipFilename)
        Logging.ConsoleLogger.info("\n📁 Creating \(Self.zipFilename)...")

        try createZip(
            containing: [searchDBURL, samplesDBURL],
            at: zipURL
        )

        let zipSize = try fileSize(at: zipURL)
        Logging.ConsoleLogger.info("   ✓ Created (\(formatBytes(zipSize)))")

        // Calculate SHA256
        Logging.ConsoleLogger.info("\n🔐 Calculating SHA256...")
        let sha256 = try calculateSHA256(of: zipURL)
        Logging.ConsoleLogger.info("   \(sha256)")

        if dryRun {
            Logging.ConsoleLogger.info("\n🏃 Dry run - skipping upload")
            Logging.ConsoleLogger.info("   Zip file: \(zipURL.path)")
            return
        }

        // Check for GitHub token
        guard let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] else {
            throw ReleaseError.missingToken
        }

        // Check if release exists
        Logging.ConsoleLogger.info("\n🔍 Checking for existing release...")
        let releaseExists = try await checkReleaseExists(repo: repo, tag: Self.releaseTag, token: token)

        if releaseExists {
            Logging.ConsoleLogger.info("   Release \(Self.releaseTag) exists, updating...")
            try await deleteRelease(repo: repo, tag: Self.releaseTag, token: token)
        }

        // Create release
        Logging.ConsoleLogger.info("\n🚀 Creating release \(Self.releaseTag)...")
        let uploadURL = try await createRelease(
            repo: repo,
            tag: Self.releaseTag,
            token: token,
            sha256: sha256
        )
        Logging.ConsoleLogger.info("   ✓ Release created")

        // Upload asset
        Logging.ConsoleLogger.info("\n⬆️  Uploading \(Self.zipFilename)...")
        try await uploadAsset(
            uploadURL: uploadURL,
            file: zipURL,
            filename: Self.zipFilename,
            token: token
        )
        Logging.ConsoleLogger.info("   ✓ Upload complete")

        // Cleanup
        try? FileManager.default.removeItem(at: zipURL)

        Logging.ConsoleLogger.info("\n✅ Release \(Self.releaseTag) published!")
        Logging.ConsoleLogger.info("   https://github.com/\(repo)/releases/tag/\(Self.releaseTag)")
    }

    // MARK: - Zip

    private func createZip(containing files: [URL], at destination: URL) throws {
        // Remove existing zip
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = files[0].deletingLastPathComponent()
        process.arguments = ["-j", destination.path] + files.map(\.lastPathComponent)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ReleaseError.zipFailed
        }
    }

    // MARK: - SHA256

    private func calculateSHA256(of url: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8),
              let hash = output.split(separator: " ").first else {
            throw ReleaseError.sha256Failed
        }

        return String(hash)
    }

    // MARK: - GitHub API

    private func checkReleaseExists(repo: String, tag: String, token: String) async throws -> Bool {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }

    private func deleteRelease(repo: String, tag: String, token: String) async throws {
        // Get release ID
        let getURL = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
        var getRequest = URLRequest(url: getURL)
        getRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        getRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: getRequest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releaseId = json["id"] as? Int else {
            throw ReleaseError.apiError("Failed to get release ID")
        }

        // Delete release
        let deleteURL = URL(string: "https://api.github.com/repos/\(repo)/releases/\(releaseId)")!
        var deleteRequest = URLRequest(url: deleteURL)
        deleteRequest.httpMethod = "DELETE"
        deleteRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: deleteRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw ReleaseError.apiError("Failed to delete release")
        }

        // Delete tag
        let tagURL = URL(string: "https://api.github.com/repos/\(repo)/git/refs/tags/\(tag)")!
        var tagRequest = URLRequest(url: tagURL)
        tagRequest.httpMethod = "DELETE"
        tagRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        _ = try? await URLSession.shared.data(for: tagRequest)
    }

    private func createRelease(
        repo: String,
        tag: String,
        token: String,
        sha256: String
    ) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "tag_name": tag,
            "name": "Pre-built Databases \(tag) (search.db and samples.db)",
            "body": """
            Pre-built search databases for instant Cupertino setup.

            ## Quick Install

            ```bash
            cupertino setup
            ```

            ## SHA256

            ```
            \(sha256)  \(Self.zipFilename)
            ```
            """,
            "prerelease": false,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw ReleaseError.apiError(message)
            }
            throw ReleaseError.apiError("Failed to create release")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadURL = json["upload_url"] as? String else {
            throw ReleaseError.apiError("Missing upload_url in response")
        }

        // Remove template part from upload URL
        return uploadURL.replacingOccurrences(of: "{?name,label}", with: "")
    }

    private func uploadAsset(
        uploadURL: String,
        file: URL,
        filename: String,
        token: String
    ) async throws {
        guard let url = URL(string: "\(uploadURL)?name=\(filename)") else {
            throw ReleaseError.apiError("Invalid upload URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: file)
        request.httpBody = fileData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw ReleaseError.apiError(message)
            }
            throw ReleaseError.apiError("Failed to upload asset")
        }
    }

    // MARK: - Helpers

    private func fileSize(at url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? Int64 ?? 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1000000
        if megabytes >= 1000 {
            return String(format: "%.1f GB", megabytes / 1000)
        }
        return String(format: "%.1f MB", megabytes)
    }
}

// MARK: - Errors

enum ReleaseError: Error, CustomStringConvertible {
    case missingDatabase(String, String)
    case zipFailed
    case sha256Failed
    case missingToken
    case apiError(String)

    var description: String {
        switch self {
        case .missingDatabase(let filename, let dir):
            return "Database not found: \(filename) in \(dir)"
        case .zipFailed:
            return "Failed to create zip file"
        case .sha256Failed:
            return "Failed to calculate SHA256"
        case .missingToken:
            return """
            GITHUB_TOKEN environment variable not set.

            Create a token at: https://github.com/settings/tokens
            Then: export GITHUB_TOKEN=your_token
            """
        case .apiError(let message):
            return "GitHub API error: \(message)"
        }
    }
}

// MARK: - URL Extension

private extension URL {
    var expandingTildeInPath: URL {
        if path.hasPrefix("~") {
            let expandedPath = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expandedPath)
        }
        return self
    }
}
