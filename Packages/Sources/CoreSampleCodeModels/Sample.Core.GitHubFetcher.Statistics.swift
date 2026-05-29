import Foundation
import SharedConstants

// MARK: - Sample.Core.GitHubFetcher result value types

//
// `FetchStatistics` + `FetchAction` are pure Foundation value types
// describing the outcome of a `Sample.Core.GitHubFetcher.fetch` run.
// They live in this foundation-only seam (not the `CoreSampleCode`
// producer) so the `Sample.Core.GitHubFetching` protocol can declare
// `fetch` returning them and the SampleCodeSource fetch strategy can
// read them without `import CoreSampleCode`. Moved out of the producer
// during #536 (lift 3).
//

extension Sample.Core {
    public struct FetchStatistics: Sendable {
        public var action: FetchAction = .cloned
        public var projectCount: Int = 0
        public var startTime: Date?
        public var endTime: Date?

        public init(
            action: FetchAction = .cloned,
            projectCount: Int = 0,
            startTime: Date? = nil,
            endTime: Date? = nil
        ) {
            self.action = action
            self.projectCount = projectCount
            self.startTime = startTime
            self.endTime = endTime
        }

        public var duration: TimeInterval? {
            guard let start = startTime, let end = endTime else {
                return nil
            }
            return end.timeIntervalSince(start)
        }
    }

    public enum FetchAction: Sendable {
        case cloned
        case pulled

        public var description: String {
            switch self {
            case .cloned: return "Cloned repository"
            case .pulled: return "Pulled latest changes"
            }
        }
    }
}
