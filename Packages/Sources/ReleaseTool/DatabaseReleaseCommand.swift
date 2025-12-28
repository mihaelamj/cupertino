import ArgumentParser
import Foundation
import Shared

// MARK: - Database Release Command

struct DatabaseReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "databases",
        abstract: "Package and upload databases to GitHub Releases (cupertino-docs)"
    )

    @Option(name: .long, help: "Base directory containing databases")
    var baseDir: String?

    @Option(name: .long, help: "GitHub repository (owner/repo)")
    var repo: String = "mihaelamj/cupertino-docs"

    @Flag(name: .long, help: "Create release without uploading (dry run)")
    var dryRun: Bool = false

    @Option(name: .long, help: "Path to repository root")
    var repoRoot: String?

    // MARK: - Constants

    private static let searchDBFilename = Shared.Constants.FileName.searchDatabase
    private static let samplesDBFilename = Shared.Constants.FileName.samplesDatabase

    // MARK: - Run

    mutating func run() async throws {
        let root = try findRepoRoot()
        let version = try readCurrentVersion(from: root)

        Console.info("📦 Database Release \(version.tag)\n")

        let baseURL = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? defaultBaseDirectory

        let searchDBURL = baseURL.appendingPathComponent(Self.searchDBFilename)
        let samplesDBURL = baseURL.appendingPathComponent(Self.samplesDBFilename)

        // Verify databases exist
        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            throw DatabaseReleaseError.missingDatabase(Self.searchDBFilename, baseURL.path)
        }
        guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
            throw DatabaseReleaseError.missingDatabase(Self.samplesDBFilename, baseURL.path)
        }

        // Get database sizes
        let searchSize = try fileSize(at: searchDBURL)
        let samplesSize = try fileSize(at: samplesDBURL)
        Console.info("📊 Database sizes:")
        Console.substep("search.db:  \(Shared.Formatting.formatBytes(searchSize))")
        Console.substep("samples.db: \(Shared.Formatting.formatBytes(samplesSize))")

        // Create zip
        let zipFilename = "cupertino-databases-\(version.tag).zip"
        let zipURL = baseURL.appendingPathComponent(zipFilename)
        Console.info("\n📁 Creating \(zipFilename)...")

        try createZip(containing: [searchDBURL, samplesDBURL], at: zipURL)

        let zipSize = try fileSize(at: zipURL)
        Console.substep("✓ Created (\(Shared.Formatting.formatBytes(zipSize)))")

        // Calculate SHA256
        Console.info("\n🔐 Calculating SHA256...")
        let sha256 = try calculateSHA256(of: zipURL)
        Console.substep(sha256)

        if dryRun {
            Console.info("\n🏃 Dry run - skipping upload")
            Console.substep("Zip file: \(zipURL.path)")
            return
        }

        // Check for GitHub token (try CUPERTINO_DOCS_TOKEN first, fall back to GITHUB_TOKEN)
        let token: String
        if let docsToken = ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.cupertinoDocsToken] {
            token = docsToken
        } else if let ghToken = ProcessInfo.processInfo.environment[Shared.Constants.EnvVar.githubToken] {
            token = ghToken
        } else {
            throw DatabaseReleaseError.missingToken
        }

        // Check if release exists
        Console.info("\n🔍 Checking for existing release...")
        let releaseExists = try await checkReleaseExists(repo: repo, tag: version.tag, token: token)

        if releaseExists {
            Console.substep("Release \(version.tag) exists, updating...")
            try await deleteRelease(repo: repo, tag: version.tag, token: token)
        }

        // Create release
        Console.info("\n🚀 Creating release \(version.tag)...")
        let uploadURL = try await createRelease(
            repo: repo,
            tag: version.tag,
            token: token,
            sha256: sha256,
            zipFilename: zipFilename
        )
        Console.substep("✓ Release created")

        // Upload asset
        Console.info("\n⬆️  Uploading \(zipFilename)...")
        try await uploadAsset(
            uploadURL: uploadURL,
            file: zipURL,
            filename: zipFilename,
            token: token
        )
        Console.substep("✓ Upload complete")

        // Cleanup
        try? FileManager.default.removeItem(at: zipURL)

        Console.success("Release \(version.tag) published!")
        Console.info("   https://github.com/\(repo)/releases/tag/\(version.tag)")
    }

    // MARK: - Helpers

    private var defaultBaseDirectory: URL {
        Shared.Constants.defaultBaseDirectory
    }

    private func findRepoRoot() throws -> URL {
        if let root = repoRoot {
            return URL(fileURLWithPath: root)
        }
        let output = try Shell.run("git rev-parse --show-toplevel")
        return URL(fileURLWithPath: output)
    }

    private func readCurrentVersion(from root: URL) throws -> Version {
        let constantsPath = root.appendingPathComponent("Packages/Sources/Shared/Constants.swift")
        let content = try String(contentsOf: constantsPath, encoding: .utf8)
        let pattern = #"public\s+static\s+let\s+version\s*=\s*"(\d+\.\d+\.\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let versionRange = Range(match.range(at: 1), in: content),
              let version = Version(String(content[versionRange])) else {
            throw DatabaseReleaseError.versionNotFound
        }
        return version
    }

    // MARK: - Zip

    private func createZip(containing files: [URL], at destination: URL) throws {
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

        // Show spinner while zip is running
        let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        let clearLine = "\r\u{1B}[K"
        var spinnerIndex = 0

        while process.isRunning {
            let s = spinner[spinnerIndex % spinner.count]
            let output = "\(clearLine)   \(s) Compressing databases..."
            FileHandle.standardOutput.write(Data(output.utf8))
            fflush(stdout)
            spinnerIndex += 1
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Clear the spinner line
        printProgress("\(clearLine)")

        guard process.terminationStatus == 0 else {
            throw DatabaseReleaseError.zipFailed
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
            throw DatabaseReleaseError.sha256Failed
        }

        return String(hash)
    }

    // MARK: - File Helpers

    private func fileSize(at url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? Int64 ?? 0
    }

    // MARK: - GitHub API

    /// Creates a URLRequest with proper GitHub API authentication
    private func githubRequest(url: URL, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Fine-grained tokens start with github_pat_, classic tokens start with ghp_
        let authValue = token.hasPrefix("ghp_") ? "token \(token)" : "Bearer \(token)"
        request.setValue(authValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    private func checkReleaseExists(repo: String, tag: String, token: String) async throws -> Bool {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
        let request = githubRequest(url: url, token: token)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }

    private func deleteRelease(repo: String, tag: String, token: String) async throws {
        // Get release ID
        let getURL = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
        let getRequest = githubRequest(url: getURL, token: token)

        let (data, _) = try await URLSession.shared.data(for: getRequest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releaseId = json["id"] as? Int else {
            throw DatabaseReleaseError.apiError("Failed to get release ID")
        }

        // Delete release
        let deleteURL = URL(string: "https://api.github.com/repos/\(repo)/releases/\(releaseId)")!
        let deleteRequest = githubRequest(url: deleteURL, token: token, method: "DELETE")

        let (_, response) = try await URLSession.shared.data(for: deleteRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw DatabaseReleaseError.apiError("Failed to delete release")
        }

        // Delete tag
        let tagURL = URL(string: "https://api.github.com/repos/\(repo)/git/refs/tags/\(tag)")!
        let tagRequest = githubRequest(url: tagURL, token: token, method: "DELETE")

        _ = try? await URLSession.shared.data(for: tagRequest)
    }

    private func createRelease(
        repo: String,
        tag: String,
        token: String,
        sha256: String,
        zipFilename: String
    ) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases")!
        var request = githubRequest(url: url, token: token, method: "POST")
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
            \(sha256)  \(zipFilename)
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
                throw DatabaseReleaseError.apiError(message)
            }
            throw DatabaseReleaseError.apiError("Failed to create release")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadURL = json["upload_url"] as? String else {
            throw DatabaseReleaseError.apiError("Missing upload_url in response")
        }

        return uploadURL.replacingOccurrences(of: "{?name,label}", with: "")
    }

    private func uploadAsset(
        uploadURL: String,
        file: URL,
        filename: String,
        token: String
    ) async throws {
        guard let url = URL(string: "\(uploadURL)?name=\(filename)") else {
            throw DatabaseReleaseError.apiError("Invalid upload URL")
        }

        var request = githubRequest(url: url, token: token, method: "POST")
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")

        // Use delegate for upload progress tracking
        let fileSize = try fileSize(at: file)
        let delegate = UploadDelegate(filename: filename, totalSize: fileSize)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (data, response) = try await session.upload(for: request, fromFile: file)

        // Move to new line after progress
        printProgress("\n")

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw DatabaseReleaseError.apiError(message)
            }
            throw DatabaseReleaseError.apiError("Failed to upload asset")
        }
    }

    private func printProgress(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
        fflush(stdout)
    }
}

// MARK: - Upload Delegate

private final class UploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let filename: String
    let totalSize: Int64
    private let barWidth = 30
    private let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var spinnerIndex = 0

    init(filename: String, totalSize: Int64) {
        self.filename = filename
        self.totalSize = totalSize
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let currentSpinner = spinner[spinnerIndex % spinner.count]
        spinnerIndex += 1

        // ANSI escape: \r = carriage return, \u{1B}[K = clear to end of line
        let clearLine = "\r\u{1B}[K"

        let expectedSize = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : totalSize

        guard expectedSize > 0 else {
            let uploaded = Shared.Formatting.formatBytes(totalBytesSent)
            let output = "\(clearLine)   \(currentSpinner) Uploading... \(uploaded)"
            FileHandle.standardOutput.write(Data(output.utf8))
            fflush(stdout)
            return
        }

        let progress = Double(totalBytesSent) / Double(expectedSize)
        let filled = Int(progress * Double(barWidth))
        let empty = barWidth - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let percent = String(format: "%3.0f%%", progress * 100)
        let uploaded = Shared.Formatting.formatBytes(totalBytesSent)
        let total = Shared.Formatting.formatBytes(expectedSize)

        let output = "\(clearLine)   \(currentSpinner) [\(bar)] \(percent) (\(uploaded)/\(total))"
        FileHandle.standardOutput.write(Data(output.utf8))
        fflush(stdout)
    }
}

// MARK: - Errors

enum DatabaseReleaseError: Error, CustomStringConvertible {
    case missingDatabase(String, String)
    case zipFailed
    case sha256Failed
    case missingToken
    case versionNotFound
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
            No GitHub token found.

            Set CUPERTINO_DOCS_TOKEN (preferred) or GITHUB_TOKEN:
            Create a token at: https://github.com/settings/tokens
            Then: export CUPERTINO_DOCS_TOKEN=your_token
            """
        case .versionNotFound:
            return "Could not find version in Constants.swift"
        case .apiError(let message):
            return "GitHub API error: \(message)"
        }
    }
}
