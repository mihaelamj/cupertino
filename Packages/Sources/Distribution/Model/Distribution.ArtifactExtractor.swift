import Foundation

// MARK: - Distribution.ArtifactExtractor — Observer protocol

extension Distribution {
    /// ZIP extractor namespace. The concrete `extract(...)` static
    /// function lives in the `Distribution` producer target as an
    /// extension on this enum.
    public enum ArtifactExtractor {
        /// GoF Observer (1994 p. 293) for ZIP extraction progress.
        /// Replaces the previous inline
        /// `tickHandler: (@Sendable () -> Void)?` closure parameter on
        /// `ArtifactExtractor.extract`. The "payload" here is just the
        /// fact that a tick happened, so the protocol method takes no
        /// arguments. Callers typically render an animated progress
        /// bar one frame per tick.
        public protocol TickObserving: Sendable {
            /// Called periodically while the ZIP is being extracted.
            /// Frequency depends on the extractor implementation (~10
            /// Hz on the standard ZIP library). Implementations should
            /// be non-blocking.
            func observeTick()
        }
    }
}
