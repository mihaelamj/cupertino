import Foundation
import SharedConstants
import SharedCore
import SharedUtils
import SQLite3

// MARK: - Shared publishing helpers

//
// Used by `Release.Command.Database`. Lives in a separate file so future
// release-tool subcommands (e.g. a separate Homebrew artifact pass, or a
// per-corpus release that targets a different GitHub repo) can reuse the
// same zip / sha256 / GitHub-API code without copy-pasting.

// MARK: - Repo root + version

extension Release {
    enum Publishing {
        static func findRepoRoot(override: String?) throws -> URL {
            if let override {
                return URL(fileURLWithPath: override)
            }
            let output = try Release.Shell.run("git rev-parse --show-toplevel")
            return URL(fileURLWithPath: output)
        }

        static func readCurrentVersion(from root: URL) throws -> Release.Version {
            let constantsPath = root.appendingPathComponent("Packages/Sources/Shared/Constants/Shared.Constants.swift")
            let content = try String(contentsOf: constantsPath, encoding: .utf8)
            // Read databaseVersion, not CLI version — the two are decoupled and
            // database releases follow the database axis.
            let pattern = #"public\s+static\s+let\s+databaseVersion\s*=\s*"(\d+\.\d+\.\d+)""#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
                  let versionRange = Range(match.range(at: 1), in: content),
                  let version = Release.Version(String(content[versionRange])) else {
                throw Release.Publishing.Error.versionNotFound
            }
            return version
        }
    }
}

// MARK: - Filesystem

extension Release.Publishing {
    static func fileSize(at url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? Int64 ?? 0
    }

    // MARK: - WAL checkpoint (#236)

    /// Outcome of a `wal_checkpoint(TRUNCATE)` on a SQLite file.
    /// `framesWritten` is the number of WAL frames moved into the
    /// main DB; `framesTotal` is the total WAL frame count before
    /// the checkpoint started. A `busy` return means at least one
    /// reader or writer was still using the WAL when the checkpoint
    /// ran — TRUNCATE blocks on readers, so for a release flow where
    /// nothing else should be touching the DB this would be a sign
    /// the host machine has a stray cupertino process.
    struct CheckpointOutcome {
        let busy: Bool
        let framesWritten: Int32
        let framesTotal: Int32
        let walFileExisted: Bool
        let walSizeAfter: Int64
    }

    enum CheckpointError: Swift.Error, CustomStringConvertible {
        case openFailed(path: String, message: String)
        case checkpointFailed(path: String, message: String)
        case walNotTruncated(path: String, sizeBytes: Int64)

        var description: String {
            switch self {
            case .openFailed(let path, let message):
                "Could not open \(path) for checkpoint: \(message)"
            case .checkpointFailed(let path, let message):
                "PRAGMA wal_checkpoint(TRUNCATE) failed on \(path): \(message)"
            case .walNotTruncated(let path, let size):
                "WAL sidecar at \(path) remained \(size) bytes after checkpoint — refusing to zip a partial bundle."
            }
        }
    }

    /// Run `PRAGMA wal_checkpoint(TRUNCATE)` on the SQLite file at
    /// `dbURL`, fold any WAL pages into the main file, and confirm
    /// the `.db-wal` sidecar is gone (or shrunk to zero bytes).
    ///
    /// Used by `Release.Command.Database` before zipping each
    /// cupertino DB for the GitHub Release. The bundled `.db` files
    /// users download via `cupertino setup` MUST contain all data —
    /// any pages still in a `.db-wal` sidecar at zip time would
    /// silently be missing from the user's installed corpus.
    /// See #236 and `docs/artifacts/folders/*.db.md`.
    @discardableResult
    static func checkpointTruncate(at dbURL: URL) throws -> CheckpointOutcome {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite3 error"
            sqlite3_close(db)
            throw CheckpointError.openFailed(path: dbURL.path, message: message)
        }
        defer { sqlite3_close(db) }

        // sqlite3_wal_checkpoint_v2 returns the busy / frame counts
        // we need; the PRAGMA-string form swallows them. Per the
        // SQLite docs:
        //   pnLog out: Size of WAL log in frames
        //   pnCkpt out: Total number of frames checkpointed
        // Both are -1 if not in WAL mode.
        var framesLog: Int32 = 0
        var framesCheckpointed: Int32 = 0
        let rc = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, &framesLog, &framesCheckpointed)
        // SQLITE_OK (0) or SQLITE_BUSY (5). Both are non-fatal in
        // theory; SQLITE_BUSY here would be very surprising in a
        // release flow.
        guard rc == SQLITE_OK || rc == SQLITE_BUSY else {
            let message = String(cString: sqlite3_errmsg(db))
            throw CheckpointError.checkpointFailed(path: dbURL.path, message: "rc=\(rc) \(message)")
        }

        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        let walExists = FileManager.default.fileExists(atPath: walURL.path)
        let walSize: Int64
        if walExists {
            walSize = (try? fileSize(at: walURL)) ?? 0
        } else {
            walSize = 0
        }

        // TRUNCATE either deletes the sidecar or shrinks it to 0.
        // Anything else means data is still trapped in the WAL —
        // refuse to ship a partial bundle.
        if walSize > 0 {
            throw CheckpointError.walNotTruncated(path: walURL.path, sizeBytes: walSize)
        }

        return CheckpointOutcome(
            busy: rc == SQLITE_BUSY,
            framesWritten: framesCheckpointed,
            framesTotal: framesLog,
            walFileExisted: walExists,
            walSizeAfter: walSize
        )
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
            let glyph = spinner[spinnerIndex % spinner.count]
            let output = "\(clearLine)   \(glyph) Compressing databases..."
            FileHandle.standardOutput.write(Data(output.utf8))
            fflush(stdout)
            spinnerIndex += 1
            Thread.sleep(forTimeInterval: 0.1)
        }

        printProgress("\(clearLine)")

        guard process.terminationStatus == 0 else {
            throw Release.Publishing.Error.zipFailed
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
            throw Release.Publishing.Error.sha256Failed
        }

        return String(hash)
    }

    static func printProgress(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
        fflush(stdout)
    }
}

// MARK: - Token resolution

extension Release.Publishing {
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
        throw Release.Publishing.Error.missingToken
    }
}

// MARK: - GitHub API

extension Release.Publishing {
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
        let url = try URL(knownGood: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")
        let request = githubRequest(url: url, token: token)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }

    static func deleteRelease(repo: String, tag: String, token: String) async throws {
        let getURL = try URL(knownGood: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")
        let getRequest = githubRequest(url: getURL, token: token)

        let (data, _) = try await URLSession.shared.data(for: getRequest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releaseId = json["id"] as? Int else {
            throw Release.Publishing.Error.apiError("Failed to get release ID")
        }

        let deleteURL = try URL(knownGood: "https://api.github.com/repos/\(repo)/releases/\(releaseId)")
        let deleteRequest = githubRequest(url: deleteURL, token: token, method: "DELETE")

        let (_, response) = try await URLSession.shared.data(for: deleteRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw Release.Publishing.Error.apiError("Failed to delete release")
        }

        // Best-effort tag cleanup; missing tag is fine.
        let tagURL = try URL(knownGood: "https://api.github.com/repos/\(repo)/git/refs/tags/\(tag)")
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
        let url = try URL(knownGood: "https://api.github.com/repos/\(repo)/releases")
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
                throw Release.Publishing.Error.apiError(message)
            }
            throw Release.Publishing.Error.apiError("Failed to create release")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadURL = json["upload_url"] as? String else {
            throw Release.Publishing.Error.apiError("Missing upload_url in response")
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
            throw Release.Publishing.Error.apiError("Invalid upload URL")
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
                throw Release.Publishing.Error.apiError(message)
            }
            throw Release.Publishing.Error.apiError("Failed to upload asset")
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
            let uploaded = Shared.Utils.Formatting.formatBytes(totalBytesSent)
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
        let uploaded = Shared.Utils.Formatting.formatBytes(totalBytesSent)
        let total = Shared.Utils.Formatting.formatBytes(expectedSize)

        let output = "\(clearLine)   \(currentSpinner) [\(bar)] \(percent) (\(uploaded)/\(total))"
        FileHandle.standardOutput.write(Data(output.utf8))
        fflush(stdout)
    }
}

// Error moved to Release.Publishing.Error.swift
