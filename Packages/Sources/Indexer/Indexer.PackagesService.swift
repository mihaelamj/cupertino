import Foundation
import SearchModels
import SharedConstants
extension Indexer {
    /// Build `packages.db` from extracted package archives at
    /// `~/.cupertino/packages/<owner>/<repo>/`. Wraps an injected
    /// `Search.PackageIndexingRunner` conformer with event-emission
    /// so this target doesn't import `Search` directly — the CLI
    /// composition root supplies a `LivePackageIndexingRunner` backed
    /// by `Search.PackageIndex` + `Search.PackageIndexer`.
    public enum PackagesService {
        public struct Request: Sendable {
            public let packagesRoot: URL
            public let packagesDB: URL
            public let clear: Bool

            public init(
                packagesRoot: URL,
                packagesDB: URL,
                clear: Bool = false
            ) {
                self.packagesRoot = packagesRoot
                self.packagesDB = packagesDB
                self.clear = clear
            }
        }

        public struct Outcome: Sendable {
            public let packagesIndexed: Int
            public let packagesFailed: Int
            public let totalFiles: Int
            public let totalBytes: Int64
            public let durationSeconds: Double
            public let totalPackagesInDB: Int
            public let totalFilesInDB: Int
            public let totalBytesInDB: Int64
        }

        public enum Event: Sendable {
            case starting(packagesRoot: URL, packagesDB: URL)
            case removingExistingDB(URL)
            case progress(name: String, done: Int, total: Int)
            case finished(Outcome)
        }

        public static func run(
            _ request: Request,
            packageIndexingRunner: any Search.PackageIndexingRunner,
            handler: @escaping @Sendable (Event) -> Void = { _ in }
        ) async throws -> Outcome {
            handler(.starting(
                packagesRoot: request.packagesRoot,
                packagesDB: request.packagesDB
            ))

            if request.clear, FileManager.default.fileExists(atPath: request.packagesDB.path) {
                handler(.removingExistingDB(request.packagesDB))
                try FileManager.default.removeItem(at: request.packagesDB)
            }

            let result = try await packageIndexingRunner.run(
                packagesRoot: request.packagesRoot,
                packagesDB: request.packagesDB
            ) { name, done, total in
                handler(.progress(name: name, done: done, total: total))
            }

            let outcome = Outcome(
                packagesIndexed: result.packagesIndexed,
                packagesFailed: result.packagesFailed,
                totalFiles: result.totalFiles,
                totalBytes: result.totalBytes,
                durationSeconds: result.durationSeconds,
                totalPackagesInDB: result.totalPackagesInDB,
                totalFilesInDB: result.totalFilesInDB,
                totalBytesInDB: result.totalBytesInDB
            )
            handler(.finished(outcome))
            return outcome
        }
    }
}
