import Foundation

// MARK: - Progress Callback

extension RemoteSync {
    /// Progress information for callbacks
    public struct Progress: Sendable {
        public let phase: IndexState.Phase
        public let framework: String?
        public let frameworkIndex: Int
        public let frameworksTotal: Int
        public let fileIndex: Int
        public let filesTotal: Int
        public let elapsed: TimeInterval
        public let overallProgress: Double

        public init(
            phase: IndexState.Phase,
            framework: String?,
            frameworkIndex: Int,
            frameworksTotal: Int,
            fileIndex: Int,
            filesTotal: Int,
            elapsed: TimeInterval,
            overallProgress: Double
        ) {
            self.phase = phase
            self.framework = framework
            self.frameworkIndex = frameworkIndex
            self.frameworksTotal = frameworksTotal
            self.fileIndex = fileIndex
            self.filesTotal = filesTotal
            self.elapsed = elapsed
            self.overallProgress = overallProgress
        }

        /// Estimated time remaining based on current progress
        public var estimatedTimeRemaining: TimeInterval? {
            guard overallProgress > 0.01 else { return nil }
            let totalEstimated = elapsed / overallProgress
            return totalEstimated - elapsed
        }
    }
}
