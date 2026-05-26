import Foundation
import SharedConstants

// MARK: - Animated Progress Display

extension RemoteSync {
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
        public func render(_ progress: RemoteSync.Progress) -> String {
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
            let elapsedStr = Shared.Utils.Formatting.formatDuration(progress.elapsed)
            line += " | \(elapsedStr)"

            return line
        }

        /// Render a single-line status update
        public func renderCompact(_ progress: RemoteSync.Progress) -> String {
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

        // #1042 Cluster 11 sub-1: Phase is an open RawRepresentable
        // struct; emojis live in a dict keyed by phase. Unknown
        // phases get a generic "•" so the dispatch path doesn't crash.
        private static let phaseEmojis: [RemoteSync.IndexState.Phase: String] = [
            .docs: "📚",
            .evolution: "📋",
            .archive: "📜",
            .swiftOrg: "🔶",
            .packages: "📦",
        ]

        private func phaseEmoji(_ phase: RemoteSync.IndexState.Phase) -> String {
            Self.phaseEmojis[phase] ?? "•"
        }
    }
}
