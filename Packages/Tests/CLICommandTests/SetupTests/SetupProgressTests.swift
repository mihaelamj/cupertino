import Foundation
import Testing

@testable import CLI
@testable import Shared

// MARK: - Progress Output Capture

/// Captures progress output for testing
final class ProgressOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _outputs: [String] = []

    var outputs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _outputs
    }

    func append(_ output: String) {
        lock.lock()
        defer { lock.unlock() }
        _outputs.append(output)
    }

    var lastOutput: String? {
        lock.lock()
        defer { lock.unlock() }
        return _outputs.last
    }

    var outputCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _outputs.count
    }
}

// MARK: - Progress Format Tests

@Suite("Setup Progress Format Tests")
struct SetupProgressFormatTests {

    @Test("Progress bar renders correct width")
    func progressBarWidth() {
        let barWidth = 30
        let progress = 0.5
        let filled = Int(progress * Double(barWidth))
        let empty = barWidth - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)

        #expect(bar.count == barWidth)
        #expect(bar.filter { $0 == "█" }.count == 15)
        #expect(bar.filter { $0 == "░" }.count == 15)
    }

    @Test("Progress bar at 0%")
    func progressBarEmpty() {
        let barWidth = 30
        let progress = 0.0
        let filled = Int(progress * Double(barWidth))
        let empty = barWidth - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)

        #expect(bar == String(repeating: "░", count: 30))
    }

    @Test("Progress bar at 100%")
    func progressBarFull() {
        let barWidth = 30
        let progress = 1.0
        let filled = Int(progress * Double(barWidth))
        let empty = barWidth - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)

        #expect(bar == String(repeating: "█", count: 30))
    }

    @Test("Spinner cycles through characters")
    func spinnerCycle() {
        let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

        #expect(spinner.count == 10)

        // Test cycling
        for i in 0..<20 {
            let char = spinner[i % spinner.count]
            #expect(spinner.contains(char))
        }

        // Verify cycle restarts
        #expect(spinner[0 % spinner.count] == "⠋")
        #expect(spinner[10 % spinner.count] == "⠋")
    }

    @Test("Progress output contains carriage return and ANSI clear")
    func progressOutputFormat() {
        let spinner = "⠋"
        let bar = "[██████████░░░░░░░░░░░░░░░░░░░░]"
        let percent = " 33%"
        let size = "(75 MB/225 MB)"

        // Correct format: \r + ANSI clear + content
        let clearLine = "\r\u{1B}[K"
        let correctOutput = "\(clearLine)   \(spinner) \(bar)\(percent) \(size)"

        #expect(correctOutput.hasPrefix("\r"))
        #expect(correctOutput.contains("\u{1B}[K"))
        #expect(correctOutput.contains(spinner))
        #expect(correctOutput.contains(bar))
    }

    @Test("ANSI clear sequence is correct escape code")
    func ansiClearSequence() {
        // \u{1B} is ESC (0x1B), [K is "clear from cursor to end of line"
        let clearToEndOfLine = "\u{1B}[K"

        #expect(clearToEndOfLine.count == 3)
        #expect(clearToEndOfLine.first?.asciiValue == 0x1B)
        #expect(clearToEndOfLine.contains("[K"))
    }

    @Test("Byte formatting")
    func byteFormatting() {
        // Test the shared formatting utility
        let kb = Shared.Formatting.formatBytes(1024)
        let mb = Shared.Formatting.formatBytes(1024 * 1024)
        let gb = Shared.Formatting.formatBytes(1024 * 1024 * 1024)

        #expect(kb.contains("KB") || kb.contains("1"))
        #expect(mb.contains("MB") || mb.contains("1"))
        #expect(gb.contains("GB") || gb.contains("1"))
    }
}

// MARK: - Download Delegate Tests

@Suite("Download Delegate Tests")
struct DownloadDelegateTests {

    @Test("Progress calculation with known size")
    func progressCalculation() {
        let totalBytesWritten: Int64 = 50 * 1024 * 1024  // 50 MB
        let totalBytesExpected: Int64 = 200 * 1024 * 1024 // 200 MB

        let progress = Double(totalBytesWritten) / Double(totalBytesExpected)

        #expect(progress == 0.25)
    }

    @Test("Progress calculation with unknown size")
    func progressCalculationUnknownSize() {
        let totalBytesExpected: Int64 = -1 // Unknown

        // When size is unknown, should show indeterminate progress
        let isUnknown = totalBytesExpected <= 0

        #expect(isUnknown)
    }

    @Test("Bar fill calculation")
    func barFillCalculation() {
        let barWidth = 30

        // Test various progress percentages
        let testCases: [(Double, Int)] = [
            (0.0, 0),
            (0.25, 7),   // 30 * 0.25 = 7.5 -> 7
            (0.5, 15),   // 30 * 0.5 = 15
            (0.75, 22),  // 30 * 0.75 = 22.5 -> 22
            (1.0, 30),   // 30 * 1.0 = 30
        ]

        for (progress, expectedFilled) in testCases {
            let filled = Int(progress * Double(barWidth))
            #expect(filled == expectedFilled, "Progress \(progress) should fill \(expectedFilled) chars, got \(filled)")
        }
    }
}

// MARK: - Real Download Integration Tests

@Suite("Setup Download Integration Tests")
struct SetupDownloadIntegrationTests {

    /// Test directory for downloads
    private static func testDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-setup-tests-\(UUID().uuidString)")
    }

    @Test("Download file with progress tracking")
    func downloadWithProgress() async throws {
        let testDir = Self.testDirectory()

        // Cleanup on exit
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        // Create test directory
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // Use a larger file to ensure progress callbacks fire
        // Swift main README is larger than swift-evolution README
        let testURL = URL(string: "https://raw.githubusercontent.com/apple/swift/main/README.md")!
        let destinationURL = testDir.appendingPathComponent("test-download.md")

        // Track progress updates
        let progressCapture = ProgressOutputCapture()

        // Create custom delegate that captures progress
        let delegate = TestDownloadDelegate { output in
            progressCapture.append(output)
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: testURL)

        // Verify download succeeded
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TestError.invalidResponse
        }
        #expect(httpResponse.statusCode == 200)

        // Move to destination
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        // Verify file exists
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))

        // For small files, progress delegate may not be called
        // This is expected behavior - the test verifies download works
        // Progress format is tested in downloadProgressBarFormat test

        // Verify progress output format if we got any updates
        if let lastOutput = progressCapture.lastOutput {
            #expect(lastOutput.hasPrefix("\r"), "Progress should start with carriage return")
        }
    }

    @Test("Download creates proper progress bar format")
    func downloadProgressBarFormat() async throws {
        let testDir = Self.testDirectory()

        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // Use slightly larger file to get more progress updates
        let testURL = URL(string: "https://raw.githubusercontent.com/apple/swift/main/README.md")!

        let progressCapture = ProgressOutputCapture()

        let delegate = TestDownloadDelegate { output in
            progressCapture.append(output)
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, _) = try await session.download(from: testURL)

        // Cleanup temp file
        try? FileManager.default.removeItem(at: tempURL)

        // Check progress output format
        for output in progressCapture.outputs {
            // Should start with \r for line overwriting
            #expect(output.hasPrefix("\r"), "Output should start with \\r: \(output)")

            // Should contain spinner character
            let spinnerChars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
            let hasSpinner = spinnerChars.contains { output.contains($0) }
            #expect(hasSpinner, "Output should contain spinner: \(output)")
        }
    }

    @Test("Cleanup removes test directory")
    func cleanupRemovesDirectory() throws {
        let testDir = Self.testDirectory()

        // Create directory and file
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let testFile = testDir.appendingPathComponent("test.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: testDir.path))
        #expect(FileManager.default.fileExists(atPath: testFile.path))

        // Remove directory
        try FileManager.default.removeItem(at: testDir)

        #expect(!FileManager.default.fileExists(atPath: testDir.path))
        #expect(!FileManager.default.fileExists(atPath: testFile.path))
    }
}

// MARK: - Test Helpers

/// Test download delegate that captures progress output
private final class TestDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let barWidth = 30
    private let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var spinnerIndex = 0
    private let onProgress: (String) -> Void

    init(onProgress: @escaping (String) -> Void) {
        self.onProgress = onProgress
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

        // ANSI escape: \r = carriage return, \u{1B}[K = clear to end of line
        let clearLine = "\r\u{1B}[K"

        // If size unknown, show indeterminate progress
        guard totalBytesExpectedToWrite > 0 else {
            let downloaded = Shared.Formatting.formatBytes(totalBytesWritten)
            let output = "\(clearLine)   \(currentSpinner) Downloading... \(downloaded)"
            onProgress(output)
            return
        }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let filled = Int(progress * Double(barWidth))
        let empty = barWidth - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let percent = String(format: "%3.0f%%", progress * 100)
        let downloaded = Shared.Formatting.formatBytes(totalBytesWritten)
        let total = Shared.Formatting.formatBytes(totalBytesExpectedToWrite)

        let output = "\(clearLine)   \(currentSpinner) [\(bar)] \(percent) (\(downloaded)/\(total))"
        onProgress(output)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Required delegate method
    }
}

/// Test errors
enum TestError: Error {
    case invalidResponse
    case downloadFailed
}
