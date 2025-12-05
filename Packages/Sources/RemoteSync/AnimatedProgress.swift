import Foundation

// MARK: - Animated Progress Display

/// Terminal progress display for remote sync operations.
/// Shows animated progress bar with ETA and current status.
public struct AnimatedProgress: Sendable {
    /// Progress bar width in characters
    public let barWidth: Int

    /// Whether to use emoji in output
    public let useEmoji: Bool

    public init(barWidth: Int = 20, useEmoji: Bool = true) {
        self.barWidth = barWidth
        self.useEmoji = useEmoji
    }

    // MARK: - Rendering

    /// Render progress to string (for terminal output)
    public func render(_ progress: RemoteSyncProgress) -> String {
        // Phase and framework progress
        let phaseIcon = useEmoji ? phaseEmoji(progress.phase) : "-"
        let frameworkBar = renderBar(
            current: progress.frameworkIndex,
            total: progress.frameworksTotal
        )
        let phaseLabel = progress.phase.rawValue.capitalized
        let counts = "\(progress.frameworkIndex)/\(progress.frameworksTotal)"

        var line = "\(phaseIcon) \(phaseLabel): \(frameworkBar) \(counts)"

        // Current framework and file progress
        if let framework = progress.framework {
            let fileProgress = progress.filesTotal > 0
                ? "(\(progress.fileIndex)/\(progress.filesTotal) files)"
                : ""
            line += " - \(framework) \(fileProgress)"
        }

        // Time info
        let elapsedStr = formatDuration(progress.elapsed)
        line += " | \(elapsedStr)"

        return line
    }

    /// Render a single-line status update
    public func renderCompact(_ progress: RemoteSyncProgress) -> String {
        let bar = renderBar(current: progress.frameworkIndex, total: progress.frameworksTotal)
        let framework = progress.framework ?? "..."
        let fileInfo = progress.filesTotal > 0 ? " (\(progress.fileIndex)/\(progress.filesTotal))" : ""
        return "\(bar) \(progress.frameworkIndex)/\(progress.frameworksTotal) \(framework)\(fileInfo)"
    }

    // MARK: - Private Helpers

    private func renderBar(current: Int, total: Int) -> String {
        guard total > 0 else { return "[\(String(repeating: "░", count: barWidth))]" }

        let progress = Double(current) / Double(total)
        let filled = Int(progress * Double(barWidth))
        let empty = barWidth - filled

        let filledStr = String(repeating: "█", count: filled)
        let emptyStr = String(repeating: "░", count: empty)

        return "[\(filledStr)\(emptyStr)]"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func phaseEmoji(_ phase: RemoteIndexState.Phase) -> String {
        switch phase {
        case .docs: return "📚"
        case .evolution: return "📋"
        case .archive: return "📜"
        case .swiftOrg: return "🔶"
        case .packages: return "📦"
        }
    }
}

// MARK: - Terminal Output

/// Protocol for terminal output (allows testing)
public protocol TerminalOutput: Sendable {
    func write(_ string: String)
    func clearLine()
    func moveCursorUp(_ lines: Int)
}

/// Standard terminal output using print
public struct StandardTerminalOutput: TerminalOutput, Sendable {
    public init() {}

    public func write(_ string: String) {
        print(string)
    }

    public func clearLine() {
        print("\u{1B}[2K\u{1B}[G", terminator: "")
    }

    public func moveCursorUp(_ lines: Int) {
        print("\u{1B}[\(lines)A", terminator: "")
    }
}

// MARK: - Progress Reporter

/// Reports progress to terminal with animated updates
public final class ProgressReporter: @unchecked Sendable {
    private let display: AnimatedProgress
    private let output: TerminalOutput
    private let lock = NSLock()
    private var spinnerIndex = 0
    private let spinnerChars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    public init(
        display: AnimatedProgress = AnimatedProgress(),
        output: TerminalOutput = StandardTerminalOutput()
    ) {
        self.display = display
        self.output = output
    }

    /// Update progress display (single line, overwrites previous)
    public func update(_ progress: RemoteSyncProgress) {
        lock.lock()
        defer { lock.unlock() }

        // Get spinner character
        let spinner = spinnerChars[spinnerIndex % spinnerChars.count]
        spinnerIndex += 1

        // Clear current line and write new progress
        let rendered = display.render(progress)
        let outputStr = "\r\u{1B}[K\(spinner) \(rendered)"
        FileHandle.standardOutput.write(Data(outputStr.utf8))
    }

    /// Print final summary
    public func finish(message: String) {
        lock.lock()
        defer { lock.unlock() }

        // Move to new line after progress
        print("")
        if !message.isEmpty {
            output.write(message)
        }
    }
}
