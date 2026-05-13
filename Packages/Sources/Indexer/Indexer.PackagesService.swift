import Foundation
import Search
import SharedConstants
import SharedCore
import SearchModels

extension Indexer {
    /// Build `packages.db` from extracted package archives at
    /// `~/.cupertino/packages/<owner>/<repo>/`. Wraps
    /// `Search.PackageIndexer` and emits progress events.
    public enum PackagesService {
        public struct Request: Sendable {
            public let packagesRoot: URL
            public let packagesDB: URL
            public let clear: Bool

            public init(
                packagesRoot: URL,
                packagesDB: URL = Shared.Constants.defaultPackagesDatabase,
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

            let index = try await Search.PackageIndex()
            let indexer = Search.PackageIndexer(rootDirectory: request.packagesRoot, index: index)

            let stats = try await indexer.indexAll { name, done, total in
                handler(.progress(name: name, done: done, total: total))
            }

            let summary = try await index.summary()
            await index.disconnect()

            let outcome = Outcome(
                packagesIndexed: stats.packagesIndexed,
                packagesFailed: stats.packagesFailed,
                totalFiles: stats.totalFiles,
                totalBytes: stats.totalBytes,
                durationSeconds: stats.durationSeconds,
                totalPackagesInDB: summary.packageCount,
                totalFilesInDB: summary.fileCount,
                totalBytesInDB: summary.bytesIndexed
            )
            handler(.finished(outcome))
            return outcome
        }
    }
}
