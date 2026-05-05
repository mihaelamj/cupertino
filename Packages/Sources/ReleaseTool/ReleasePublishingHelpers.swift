import Foundation
import Shared

// MARK: - Shared publishing helpers

//
// Used by `DatabaseReleaseCommand`. Lives in a separate file so future
// release-tool subcommands (e.g. a separate Homebrew artifact pass, or a
// per-corpus release that targets a different GitHub repo) can reuse the
// same zip / sha256 / GitHub-API code without copy-pasting.

// MARK: - Repo root + version

enum ReleasePublishing {
    static func findRepoRoot(override: String?) throws -> URL {
        if let override {
            return URL(fileURLWithPath: override)
        }
        let output = try Shell.run("git rev-parse --show-toplevel")
        return URL(fileURLWithPath: output)
    }

    static func readCurrentVersion(from root: URL) throws -> Version {
        let constantsPath = root.appendingPathComponent("Packages/Sources/Shared/Constants.swift")
        let content = try String(contentsOf: constantsPath, encoding: .utf8)
        // Read databaseVersion, not CLI version — the two are decoupled and
        // database releases follow the database axis.
        let pattern = #"public\s+static\s+let\s+databaseVersion\s*=\s*"(\d+\.\d+\.\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let versionRange = Range(match.range(at: 1), in: content),
              let version = Version(String(content[versionRange])) else {
            throw ReleasePublishingError.versionNotFound
        }
        return version
    }
}

// MARK: - Filesystem

extension ReleasePublishing {
    static func fileSize(at url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? Int64 ?? 0
    }

    static func createZip(containing files: [URL], at destination: URL) throws {
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

        printProgress("\(clearLine)")

        guard process.terminationStatus == 0 else {
            throw ReleasePublishingError.zipFailed
        }
    }

    static func calculateSHA256(of url: URL) throws -> String {
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
            throw ReleasePublishingError.sha256Failed
        }

        return String(hash)
    }

    static func printProgress(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
        fflush(stdout)
    }
}

// MARK: - Token resolution

extension ReleasePublishing {
    /// Resolves a GitHub token from the environment.
    /// Tries `CUPERTINO_DOCS_TOKEN` first, falls back to `GITHUB_TOKEN`.
    static func resolveToken() throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let docsToken = env[Shared.Constants.EnvVar.cupertinoDocsToken] {
            return docsToken
        }
        if let ghToken = env[Shared.Constants.EnvVar.githubToken] {
            return ghToken
        }
        throw ReleasePublishingError.missingToken
    }
}

// MARK: - GitHub API

extension ReleasePublishing {
    /// Constructs a URLRequest authenticated for GitHub's API.
    static func githubRequest(url: URL, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Fine-grained tokens start with `github_pat_`; classic with `ghp_`.
        let authValue = token.hasPrefix("ghp_") ? "token \(token)" : "Bearer \(token)"
        request.setValue(authValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    static func checkReleaseExists(repo: String, tag: String, token: String) async throws -> Bool {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
        let request = githubRequest(url: url, token: token)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }

    static func deleteRelease(repo: String, tag: String, token: String) async throws {
        let getURL = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
        let getRequest = githubRequest(url: getURL, token: token)

        let (data, _) = try await URLSession.shared.data(for: getRequest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releaseId = json["id"] as? Int else {
            throw ReleasePublishingError.apiError("Failed to get release ID")
        }

        let deleteURL = URL(string: "https://api.github.com/repos/\(repo)/releases/\(releaseId)")!
        let deleteRequest = githubRequest(url: deleteURL, token: token, method: "DELETE")

        let (_, response) = try await URLSession.shared.data(for: deleteRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw ReleasePublishingError.apiError("Failed to delete release")
        }

        // Best-effort tag cleanup; missing tag is fine.
        let tagURL = URL(string: "https://api.github.com/repos/\(repo)/git/refs/tags/\(tag)")!
        let tagRequest = githubRequest(url: tagURL, token: token, method: "DELETE")
        _ = try? await URLSession.shared.data(for: tagRequest)
    }

    /// Creates a release on the given repo and returns the upload URL for asset attachment.
    static func createRelease(
        repo: String,
        tag: String,
        token: String,
        name: String,
        body: String
    ) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases")!
        var request = githubRequest(url: url, token: token, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "tag_name": tag,
            "name": name,
            "body": body,
            "prerelease": false,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw ReleasePublishingError.apiError(message)
            }
            throw ReleasePublishingError.apiError("Failed to create release")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadURL = json["upload_url"] as? String else {
            throw ReleasePublishingError.apiError("Missing upload_url in response")
        }

        return uploadURL.replacingOccurrences(of: "{?name,label}", with: "")
    }

    static func uploadAsset(
        uploadURL: String,
        file: URL,
        filename: String,
        token: String
    ) async throws {
        guard let url = URL(string: "\(uploadURL)?name=\(filename)") else {
            throw ReleasePublishingError.apiError("Invalid upload URL")
        }

        var request = githubRequest(url: url, token: token, method: "POST")
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")

        let size = try fileSize(at: file)
        let delegate = UploadProgressDelegate(filename: filename, totalSize: size)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (data, response) = try await session.upload(for: request, fromFile: file)

        // Move past the in-place progress bar.
        printProgress("\n")

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] as? String {
                throw ReleasePublishingError.apiError(message)
            }
            throw ReleasePublishingError.apiError("Failed to upload asset")
        }
    }
}

// MARK: - Upload progress

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
        _: URLSession,
        task _: URLSessionTask,
        didSendBodyData _: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let currentSpinner = spinner[spinnerIndex % spinner.count]
        spinnerIndex += 1

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

enum ReleasePublishingError: Error, CustomStringConvertible {
    case missingDatabase(String, String)
    case zipFailed
    case sha256Failed
    case missingToken
    case versionNotFound
    case apiError(String)

    var description: String {
        switch self {
        case let .missingDatabase(filename, dir):
            "Database not found: \(filename) in \(dir)"
        case .zipFailed:
            "Failed to create zip file"
        case .sha256Failed:
            "Failed to calculate SHA256"
        case .missingToken:
            """
            No GitHub token found.

            Set CUPERTINO_DOCS_TOKEN (preferred) or GITHUB_TOKEN:
            Create a token at: https://github.com/settings/tokens
            Then: export CUPERTINO_DOCS_TOKEN=your_token
            """
        case .versionNotFound:
            "Could not find databaseVersion in Constants.swift"
        case let .apiError(message):
            "GitHub API error: \(message)"
        }
    }
}
