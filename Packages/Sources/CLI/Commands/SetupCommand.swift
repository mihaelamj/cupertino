import ArgumentParser
import Foundation
import Logging
import Shared

// MARK: - Setup Command

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Download pre-built search databases from GitHub"
    )

    @Option(name: .long, help: "Base directory for databases")
    var baseDir: String?

    @Flag(name: .long, help: "Force re-download even if files exist")
    var force: Bool = false

    // MARK: - Constants

    private static let releaseBaseURL = "https://github.com/mihaelamj/cupertino-docs/releases/download"
    private static let searchDBFilename = "search.db"
    private static let samplesDBFilename = "samples.db"

    /// Release tag matches CLI version for database schema compatibility
    private static var releaseTag: String {
        "v\(Shared.Constants.App.version)"
    }

    private static var zipFilename: String {
        "cupertino-databases-\(releaseTag).zip"
    }

    private static var releaseURL: String {
        "\(releaseBaseURL)/\(releaseTag)"
    }

    // MARK: - Run

    mutating func run() async throws {
        Logging.ConsoleLogger.info("📦 Cupertino Setup\n")

        let baseURL = baseDir.map { URL(fileURLWithPath: $0).expandingTildeInPath }
            ?? Shared.Constants.defaultBaseDirectory

        // Create directory if needed
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let searchDBURL = baseURL.appendingPathComponent(Self.searchDBFilename)
        let samplesDBURL = baseURL.appendingPathComponent(Self.samplesDBFilename)

        // Check if both files exist
        let searchExists = FileManager.default.fileExists(atPath: searchDBURL.path)
        let samplesExists = FileManager.default.fileExists(atPath: samplesDBURL.path)

        if !force, searchExists, samplesExists {
            Logging.ConsoleLogger.info("✅ Databases already exist")
            Logging.ConsoleLogger.info("   Documentation: \(searchDBURL.path)")
            Logging.ConsoleLogger.info("   Sample code:   \(samplesDBURL.path)")
            Logging.ConsoleLogger.info("\n💡 Use --force to overwrite with latest version")
            Logging.ConsoleLogger.info("💡 Start the server with: cupertino serve")
            return
        }

        // Warn about overwriting
        if force, searchExists || samplesExists {
            Logging.ConsoleLogger.info("⚠️  Existing databases will be overwritten\n")
        }

        // Download and extract zip
        let zipURL = baseURL.appendingPathComponent(Self.zipFilename)
        try await downloadFile(
            name: "Databases",
            from: "\(Self.releaseURL)/\(Self.zipFilename)",
            to: zipURL
        )

        // Extract zip
        Logging.ConsoleLogger.info("📂 Extracting databases...")
        try await extractZip(at: zipURL, to: baseURL)

        // Remove zip file
        try? FileManager.default.removeItem(at: zipURL)

        // Verify files exist
        guard FileManager.default.fileExists(atPath: searchDBURL.path) else {
            throw SetupError.missingFile(Self.searchDBFilename)
        }
        guard FileManager.default.fileExists(atPath: samplesDBURL.path) else {
            throw SetupError.missingFile(Self.samplesDBFilename)
        }

        // Done
        Logging.ConsoleLogger.output("")
        Logging.ConsoleLogger.info("✅ Setup complete!")
        Logging.ConsoleLogger.info("   Documentation: \(searchDBURL.path)")
        Logging.ConsoleLogger.info("   Sample code:   \(samplesDBURL.path)")
        Logging.ConsoleLogger.info("\n💡 Start the server with: cupertino serve")
    }

    // MARK: - Extract

    private func extractZip(at zipURL: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SetupError.extractionFailed
        }
        Logging.ConsoleLogger.info("   ✓ Extracted")
    }

    // MARK: - Download

    private func downloadFile(name: String, from urlString: String, to destination: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw SetupError.invalidURL(urlString)
        }

        Logging.ConsoleLogger.info("⬇️  Downloading \(name)...")
        printProgress("   ⠋ Starting download...\r")
        fflush(stdout)

        // Use delegate for progress tracking
        let delegate = DownloadDelegate(name: name)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (tempURL, response) = try await session.download(from: url)

        // Move to new line after progress
        printProgress("\n")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SetupError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw SetupError.notFound(url)
            }
            throw SetupError.httpError(httpResponse.statusCode)
        }

        // Get file size for display
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
        let sizeStr = formatBytes(fileSize)

        // Move to destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        Logging.ConsoleLogger.info("   ✓ \(name) (\(sizeStr))")
    }

    private func printProgress(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
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

enum SetupError: Error, CustomStringConvertible {
    case invalidURL(String)
    case invalidResponse
    case notFound(URL)
    case httpError(Int)
    case extractionFailed
    case missingFile(String)

    var description: String {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Invalid response from server"
        case .notFound(let url):
            return """
            File not found: \(url)

            The release may not exist yet. Check: https://github.com/mihaelamj/cupertino-docs/releases
            """
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .extractionFailed:
            return "Failed to extract zip file"
        case .missingFile(let filename):
            return "Expected file not found after extraction: \(filename)"
        }
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let name: String
    private let barWidth = 30
    private let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var spinnerIndex = 0

    init(name: String) {
        self.name = name
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let currentSpinner = spinner[spinnerIndex % spinner.count]
        spinnerIndex += 1

        // If size unknown, show indeterminate progress
        guard totalBytesExpectedToWrite > 0 else {
            let downloaded = formatBytes(totalBytesWritten)
            let output = "\r   \(currentSpinner) Downloading... \(downloaded)"
            FileHandle.standardOutput.write(Data(output.utf8))
            fflush(stdout)
            return
        }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let filled = Int(progress * Double(barWidth))
        let empty = barWidth - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let percent = String(format: "%3.0f%%", progress * 100)
        let downloaded = formatBytes(totalBytesWritten)
        let total = formatBytes(totalBytesExpectedToWrite)

        let output = "\r   \(currentSpinner) [\(bar)] \(percent) (\(downloaded)/\(total))"
        FileHandle.standardOutput.write(Data(output.utf8))
        fflush(stdout)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Required delegate method - actual file handling done in downloadFile
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1000000
        if megabytes >= 1000 {
            return String(format: "%.1f GB", megabytes / 1000)
        }
        return String(format: "%.1f MB", megabytes)
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
