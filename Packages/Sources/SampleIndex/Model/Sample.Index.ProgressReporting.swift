import Foundation
import SharedConstants

// MARK: - Sample.Index.IndexProgress (canonical home in the seam)

extension Sample.Index {
    /// Progress information emitted during a sample-index build run.
    /// Sendable, foundation-only. Lives in the `SampleIndexModels` seam
    /// target so any conformer of `Sample.Index.ProgressReporting` can
    /// receive these values without `import SampleIndex` (the producer
    /// target that owns `Sample.Index.Builder`). Strict GoF Observer
    /// (1994 p. 293): the abstraction is reachable without the subject.
    ///
    /// `Sample.Index.Builder.IndexProgress` is a typealias for this type
    /// (declared inside the `SampleIndex` producer target) so existing
    /// call sites continue to compile.
    public struct IndexProgress: Sendable {
        public let currentProject: String
        public let projectIndex: Int
        public let totalProjects: Int
        public let filesIndexed: Int
        public let status: Status

        public enum Status: Sendable {
            case extracting
            case indexingFiles
            case completed
            case failed(String)
        }

        public var percentComplete: Double {
            guard totalProjects > 0 else { return 0 }
            return Double(projectIndex) / Double(totalProjects) * 100
        }

        public init(
            currentProject: String,
            projectIndex: Int,
            totalProjects: Int,
            filesIndexed: Int,
            status: Status
        ) {
            self.currentProject = currentProject
            self.projectIndex = projectIndex
            self.totalProjects = totalProjects
            self.filesIndexed = filesIndexed
            self.status = status
        }
    }
}

// MARK: - Sample.Index.ProgressReporting (Observer protocol)

extension Sample.Index {
    /// GoF Observer (1994 p. 293) for sample-index build progress.
    /// Replaces the previous `Sample.Index.Builder.ProgressCallback =
    /// @Sendable (IndexProgress) -> Void` closure typealias.
    ///
    /// Strict GoF: the abstraction (this protocol) and its payload
    /// (`Sample.Index.IndexProgress`) both live in the foundation-only
    /// `SampleIndexModels` seam target. A conformer can implement
    /// `report(progress:)` with only `import SampleIndexModels` — no
    /// dependency on the `Sample.Index.Builder` actor target.
    ///
    /// Aligns with the standing cupertino rule "no closures, they ate
    /// magic" (see `mihaela-agents/Rules/swift/gof-di-rules.md` rule 5).
    public protocol ProgressReporting: Sendable {
        /// Called once per project lifecycle transition. Implementations
        /// should be non-blocking; the indexer waits for return before
        /// continuing.
        func report(progress: Sample.Index.IndexProgress)
    }
}
