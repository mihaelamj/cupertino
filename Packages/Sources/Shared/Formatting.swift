import Foundation

// MARK: - Formatting Utilities

extension Shared {
    /// Shared formatting utilities
    public enum Formatting {
        // MARK: - Byte Formatting

        /// Format bytes to human-readable string (e.g., "1.5 MB", "2.3 GB")
        /// Uses ByteCountFormatter for consistent, localized output
        /// - Parameter bytes: The number of bytes to format
        /// - Returns: Human-readable string representation
        public static func formatBytes(_ bytes: Int64) -> String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }

        /// Format bytes to human-readable string (Int version)
        /// - Parameter bytes: The number of bytes to format
        /// - Returns: Human-readable string representation
        public static func formatBytes(_ bytes: Int) -> String {
            formatBytes(Int64(bytes))
        }

        // MARK: - Duration Formatting

        /// Format time interval to human-readable string (e.g., "1:23:45" or "05:30")
        /// - Parameter interval: The time interval in seconds
        /// - Returns: Formatted duration string (H:MM:SS or MM:SS)
        public static func formatDuration(_ interval: TimeInterval) -> String {
            let totalSeconds = Int(interval)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }

        /// Format time interval to verbose human-readable string (e.g., "1h 23m 45s")
        /// - Parameter interval: The time interval in seconds
        /// - Returns: Formatted duration string with unit labels
        public static func formatDurationVerbose(_ interval: TimeInterval) -> String {
            let totalSeconds = Int(interval)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return "\(hours)h \(minutes)m \(seconds)s"
            } else if minutes > 0 {
                return "\(minutes)m \(seconds)s"
            }
            return "\(seconds)s"
        }
    }
}
