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
    private static let searchDBFilename = Shared.Constants.FileName.searchDatabase
    private static let samplesDBFilename = Shared.Constants.FileName.samplesDatabase

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

        // Wait for process using termination handler
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Animate spinner while waiting
            let spinner = ExtractionSpinner()
            spinner.start()

            // Store spinner reference to stop it when process ends
            objc_setAssociatedObject(process, "spinner", spinner, .OBJC_ASSOCIATION_RETAIN)
        }

        // Clear the spinner line
        printProgress("\r\u{1B}[K")

        guard status == 0 else {
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

        // Use downloadTask with delegate for progress - wrap in continuation
        let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let delegate = DownloadProgressDelegate(
                name: name,
                expectedSize: Shared.Constants.App.approximateZipSize,
                onComplete: { result in
                    continuation.resume(with: result)
                }
            )

            // Create session with delegate to receive progress callbacks
            // Use extended timeout for large database downloads (~400MB)
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300  // 5 minutes for request
            config.timeoutIntervalForResource = 600 // 10 minutes for entire download

            let session = URLSession(
                configuration: config,
                delegate: delegate,
                delegateQueue: nil
            )

            let task = session.downloadTask(with: url)
            task.resume()
        }

        // Move to new line after progress
        printProgress("\n")

        // Get file size for display
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
        let sizeStr = Shared.Formatting.formatBytes(fileSize)

        // Move to destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        Logging.ConsoleLogger.info("   ✓ \(name) (\(sizeStr))")
    }

    private func printProgress(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
        fflush(stdout)
    }
}

// MARK: - Extraction Spinner

private final class ExtractionSpinner: @unchecked Sendable {
    private let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let clearLine = "\r\u{1B}[K"
    private var timer: DispatchSourceTimer?
    private var index = 0

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        let s = spinner[index % spinner.count]
        let output = "\(clearLine)   \(s) Extracting databases..."
        FileHandle.standardOutput.write(Data(output.utf8))
        fflush(stdout)
        index += 1
    }

    deinit {
        timer?.cancel()
    }
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let name: String
    private let expectedSize: Int64
    private let onComplete: (Result<URL, Error>) -> Void

    private let barWidth = 30
    private let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var spinnerIndex = 0

    init(name: String, expectedSize: Int64, onComplete: @escaping (Result<URL, Error>) -> Void) {
        self.name = name
        self.expectedSize = expectedSize
        self.onComplete = onComplete
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let currentSpinner = spinner[spinnerIndex % spinner.count]
        spinnerIndex += 1

        // ANSI escape: \r = carriage return, \u{1B}[K = clear to end of line
        let clearLine = "\r\u{1B}[K"

        // Use expected size from server, fall back to approximate size
        let totalSize = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize

        guard totalSize > 0 else {
            let downloaded = Shared.Formatting.formatBytes(totalBytesWritten)
            let output = "\(clearLine)   \(currentSpinner) Downloading... \(downloaded)"
            FileHandle.standardOutput.write(Data(output.utf8))
            fflush(stdout)
            return
        }

        let progress = Double(totalBytesWritten) / Double(totalSize)
        let filled = Int(progress * Double(barWidth))
        let empty = barWidth - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let percent = String(format: "%3.0f%%", progress * 100)
        let downloaded = Shared.Formatting.formatBytes(totalBytesWritten)
        let total = Shared.Formatting.formatBytes(totalSize)

        let output = "\(clearLine)   \(currentSpinner) [\(bar)] \(percent) (\(downloaded)/\(total))"
        FileHandle.standardOutput.write(Data(output.utf8))
        fflush(stdout)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Copy to a temp location that won't be deleted when session invalidates
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".zip")

        do {
            try FileManager.default.copyItem(at: location, to: tempFile)
            onComplete(.success(tempFile))
        } catch {
            onComplete(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            onComplete(.failure(error))
        }
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
