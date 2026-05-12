import Core
import CoreProtocols
import Foundation
import SampleIndex
import SharedConstants
import SharedCore

extension Indexer {
    /// Build `samples.db` from extracted sample-code zips at
    /// `~/.cupertino/sample-code/`. Wraps `SampleIndex.Builder` and emits
    /// progress events.
    public enum SamplesService {
        public struct Request: Sendable {
            public let sampleCodeDir: URL
            public let samplesDB: URL
            public let clear: Bool
            public let force: Bool

            public init(
                sampleCodeDir: URL = SampleIndex.defaultSampleCodeDirectory,
                samplesDB: URL = SampleIndex.defaultDatabasePath,
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

            let database = try await SampleIndex.Database(dbPath: request.samplesDB)
            if request.clear {
                handler(.clearingExistingIndex)
                try await database.clearAll()
            }

            let existingProjects = try await database.projectCount()
            let existingFiles = try await database.fileCount()
            if existingProjects > 0, !request.force, !request.clear {
                handler(.existingIndexNotice(projects: existingProjects, files: existingFiles))
            }

            handler(.loadingCatalog)
            let catalogEntries = await Sample.Core.Catalog.allEntries
            handler(.catalogLoaded(entryCount: catalogEntries.count))

            let entries = catalogEntries.map { entry in
                SampleIndex.SampleCodeEntryInfo(
                    title: entry.title,
                    description: entry.description,
                    frameworks: [entry.framework],
                    webURL: entry.webURL,
                    zipFilename: entry.zipFilename
                )
            }

            handler(.indexingStart)
            let builder = SampleIndex.Builder(
                database: database,
                sampleCodeDirectory: request.sampleCodeDir
            )

            let startTime = Date()
            let indexed = try await builder.indexAll(
                entries: entries,
                forceReindex: request.force
            ) { progress in
                let phase: Event.Phase
                switch progress.status {
                case .extracting: phase = .extracting
                case .indexingFiles: phase = .indexingFiles
                case .completed: phase = .completed
                case .failed: phase = .failed
                }
                handler(.projectProgress(
                    name: progress.currentProject,
                    percent: progress.percentComplete,
                    phase: phase
                ))
            }

            let duration = Date().timeIntervalSince(startTime)

            let finalProjects = try await database.projectCount()
            let finalFiles = try await database.fileCount()
            let finalSymbols = try await database.symbolCount()
            let finalImports = try await database.importCount()

            let outcome = Outcome(
                samplesDBPath: request.samplesDB,
                projectsIndexedThisRun: indexed,
                projectsTotal: finalProjects,
                filesTotal: finalFiles,
                symbolsTotal: finalSymbols,
                importsTotal: finalImports,
                durationSeconds: duration
            )
            handler(.finished(outcome))
            return outcome
        }
    }
}
