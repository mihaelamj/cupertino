import Foundation
import SampleIndexModels
import SharedConstants
import SharedCore

extension Indexer {
    /// Build `samples.db` from extracted sample-code zips at
    /// `~/.cupertino/sample-code/`. Wraps an injected
    /// `Sample.Index.SamplesIndexingRun` closure with event-emission
    /// so this target doesn't import `SampleIndex` or `CoreSampleCode`
    /// directly — the CLI composition root supplies a closure backed
    /// by `Sample.Index.Database` + `Sample.Index.Builder` +
    /// `Sample.Core.Catalog`.
    public enum SamplesService {
        public struct Request: Sendable {
            public let sampleCodeDir: URL
            public let samplesDB: URL
            public let clear: Bool
            public let force: Bool

            public init(
                sampleCodeDir: URL,
                samplesDB: URL,
                clear: Bool = false,
                force: Bool = false
            ) {
                self.sampleCodeDir = sampleCodeDir
                self.samplesDB = samplesDB
                self.clear = clear
                self.force = force
            }
        }

        public struct Outcome: Sendable {
            public let samplesDBPath: URL
            public let projectsIndexedThisRun: Int
            public let projectsTotal: Int
            public let filesTotal: Int
            public let symbolsTotal: Int
            public let importsTotal: Int
            public let durationSeconds: Double
        }

        public enum Event: Sendable {
            public enum Phase: String, Sendable {
                case extracting
                case indexingFiles
                case completed
                case failed
            }

            case starting(sampleCodeDir: URL, samplesDB: URL)
            case removingExistingDB(URL)
            case clearingExistingIndex
            case existingIndexNotice(projects: Int, files: Int)
            case loadingCatalog
            case catalogLoaded(entryCount: Int)
            case indexingStart
            case projectProgress(name: String, percent: Double, phase: Phase)
            case finished(Outcome)
        }

        public enum ServiceError: Error, CustomStringConvertible {
            case sampleCodeDirectoryNotFound(URL)

            public var description: String {
                switch self {
                case .sampleCodeDirectoryNotFound(let url):
                    return "Sample code directory not found: \(url.path)"
                }
            }
        }

        public static func run(
            _ request: Request,
            samplesIndexingRun: Sample.Index.SamplesIndexingRun,
            handler: @escaping @Sendable (Event) -> Void = { _ in }
        ) async throws -> Outcome {
            handler(.starting(
                sampleCodeDir: request.sampleCodeDir,
                samplesDB: request.samplesDB
            ))

            guard FileManager.default.fileExists(atPath: request.sampleCodeDir.path) else {
                throw ServiceError.sampleCodeDirectoryNotFound(request.sampleCodeDir)
            }

            // Drop the existing DB for a clean re-index. Matches the
            // search.db / packages.db pattern.
            if FileManager.default.fileExists(atPath: request.samplesDB.path) {
                handler(.removingExistingDB(request.samplesDB))
                try FileManager.default.removeItem(at: request.samplesDB)
            }

            let input = Sample.Index.SamplesIndexingInput(
                sampleCodeDir: request.sampleCodeDir,
                samplesDB: request.samplesDB,
                clear: request.clear,
                force: request.force
            )

            let result = try await samplesIndexingRun(input) { phase in
                switch phase {
                case .clearingExistingIndex:
                    handler(.clearingExistingIndex)
                case .existingIndexNotice(let projects, let files):
                    handler(.existingIndexNotice(projects: projects, files: files))
                case .loadingCatalog:
                    handler(.loadingCatalog)
                case .catalogLoaded(let entryCount):
                    handler(.catalogLoaded(entryCount: entryCount))
                case .indexingStart:
                    handler(.indexingStart)
                case .projectProgress(let name, let percent, let p):
                    let mapped: Event.Phase
                    switch p {
                    case .extracting: mapped = .extracting
                    case .indexingFiles: mapped = .indexingFiles
                    case .completed: mapped = .completed
                    case .failed: mapped = .failed
                    }
                    handler(.projectProgress(name: name, percent: percent, phase: mapped))
                }
            }

            let outcome = Outcome(
                samplesDBPath: request.samplesDB,
                projectsIndexedThisRun: result.projectsIndexedThisRun,
                projectsTotal: result.projectsTotal,
                filesTotal: result.filesTotal,
                symbolsTotal: result.symbolsTotal,
                importsTotal: result.importsTotal,
                durationSeconds: result.durationSeconds
            )
            handler(.finished(outcome))
            return outcome
        }
    }
}
