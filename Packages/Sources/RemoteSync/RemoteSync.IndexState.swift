import Foundation

// MARK: - Remote Index State

extension RemoteSync {
    /// Persistent state for resumable remote indexing.
    /// Tracks progress at file level within each framework for precise resume.
    public struct IndexState: Codable, Sendable, Equatable {
        /// App version that created this state
        public let version: String

        /// When indexing started
        public let started: Date

        /// Current phase being indexed
        public let phase: Phase

        /// Phases that have been completed
        public let phasesCompleted: [Phase]

        /// Current framework being indexed (nil if between frameworks)
        public let currentFramework: String?

        /// Frameworks that have been fully indexed in current phase
        public let frameworksCompleted: [String]

        /// Total number of frameworks in current phase
        public let frameworksTotal: Int

        /// Current file index within the current framework
        public let currentFileIndex: Int

        /// Total files in current framework
        public let filesTotal: Int

        /// Indexing phases in order
        public enum Phase: String, Codable, Sendable, CaseIterable {
            case docs
            case evolution
            case archive
            case swiftOrg
            case packages
        }

        // MARK: - Initialization

        public init(
            version: String,
            started: Date = Date(),
            phase: Phase = .docs,
            phasesCompleted: [Phase] = [],
            currentFramework: String? = nil,
            frameworksCompleted: [String] = [],
            frameworksTotal: Int = 0,
            currentFileIndex: Int = 0,
            filesTotal: Int = 0
        ) {
            self.version = version
            self.started = started
            self.phase = phase
            self.phasesCompleted = phasesCompleted
            self.currentFramework = currentFramework
            self.frameworksCompleted = frameworksCompleted
            self.frameworksTotal = frameworksTotal
            self.currentFileIndex = currentFileIndex
            self.filesTotal = filesTotal
        }

        // MARK: - State Updates (returns new state - immutable)

        /// Start a new phase
        public func startingPhase(_ phase: Phase, frameworksTotal: Int) -> IndexState {
            IndexState(
                version: version,
                started: started,
                phase: phase,
                phasesCompleted: phasesCompleted,
                currentFramework: nil,
                frameworksCompleted: [],
                frameworksTotal: frameworksTotal,
                currentFileIndex: 0,
                filesTotal: 0
            )
        }

        /// Start a new framework within current phase
        public func startingFramework(_ name: String, filesTotal: Int) -> IndexState {
            IndexState(
                version: version,
                started: started,
                phase: phase,
                phasesCompleted: phasesCompleted,
                currentFramework: name,
                frameworksCompleted: frameworksCompleted,
                frameworksTotal: frameworksTotal,
                currentFileIndex: 0,
                filesTotal: filesTotal
            )
        }

        /// Update file progress within current framework
        public func updatingFileIndex(_ index: Int) -> IndexState {
            IndexState(
                version: version,
                started: started,
                phase: phase,
                phasesCompleted: phasesCompleted,
                currentFramework: currentFramework,
                frameworksCompleted: frameworksCompleted,
                frameworksTotal: frameworksTotal,
                currentFileIndex: index,
                filesTotal: filesTotal
            )
        }

        /// Complete current framework
        public func completingFramework() -> IndexState {
            guard let framework = currentFramework else { return self }
            return IndexState(
                version: version,
                started: started,
                phase: phase,
                phasesCompleted: phasesCompleted,
                currentFramework: nil,
                frameworksCompleted: frameworksCompleted + [framework],
                frameworksTotal: frameworksTotal,
                currentFileIndex: 0,
                filesTotal: 0
            )
        }

        /// Complete current phase
        public func completingPhase() -> IndexState {
            IndexState(
                version: version,
                started: started,
                phase: phase,
                phasesCompleted: phasesCompleted + [phase],
                currentFramework: nil,
                frameworksCompleted: [],
                frameworksTotal: 0,
                currentFileIndex: 0,
                filesTotal: 0
            )
        }

        // MARK: - Persistence

        /// Save state to file
        public func save(to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
        }

        /// Load state from file
        public static func load(from url: URL) throws -> IndexState {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(IndexState.self, from: data)
        }

        /// Check if state file exists
        public static func exists(at url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
        }

        /// Delete state file
        public static func delete(at url: URL) throws {
            if exists(at: url) {
                try FileManager.default.removeItem(at: url)
            }
        }

        // MARK: - Progress Helpers

        /// Overall progress percentage (0.0 to 1.0)
        public var overallProgress: Double {
            let completedPhases = Double(phasesCompleted.count)
            let totalPhases = Double(Phase.allCases.count)

            // Progress within current phase
            let phaseProgress: Double
            if frameworksTotal > 0 {
                let completedFrameworks = Double(frameworksCompleted.count)
                let frameworkProgress = filesTotal > 0
                    ? Double(currentFileIndex) / Double(filesTotal)
                    : 0.0
                phaseProgress = (completedFrameworks + frameworkProgress) / Double(frameworksTotal)
            } else {
                phaseProgress = 0.0
            }

            return (completedPhases + phaseProgress) / totalPhases
        }

        /// Human-readable progress string
        public var progressDescription: String {
            if let framework = currentFramework {
                return "\(phase.rawValue): \(framework) (\(currentFileIndex)/\(filesTotal) files)"
            } else {
                return "\(phase.rawValue): \(frameworksCompleted.count)/\(frameworksTotal) frameworks"
            }
        }
    }
}
