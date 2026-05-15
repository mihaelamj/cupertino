import Foundation

// MARK: - Indexer.PackagesService — value types + Observer protocol

extension Indexer {
    /// Builds `packages.db` from extracted package archives at
    /// `~/.cupertino/packages/<owner>/<repo>/`.
    ///
    /// The value types here (`Request`, `Outcome`, `Event`,
    /// `EventObserving`) form the foundation-only seam. The
    /// `static func run(...)` orchestrator that consumes them lives in
    /// the `Indexer` producer target as an extension on this enum.
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

            public init(
                packagesIndexed: Int,
                packagesFailed: Int,
                totalFiles: Int,
                totalBytes: Int64,
                durationSeconds: Double,
                totalPackagesInDB: Int,
                totalFilesInDB: Int,
                totalBytesInDB: Int64
            ) {
                self.packagesIndexed = packagesIndexed
                self.packagesFailed = packagesFailed
                self.totalFiles = totalFiles
                self.totalBytes = totalBytes
                self.durationSeconds = durationSeconds
                self.totalPackagesInDB = totalPackagesInDB
                self.totalFilesInDB = totalFilesInDB
                self.totalBytesInDB = totalBytesInDB
            }
        }

        public enum Event: Sendable {
            case starting(packagesRoot: URL, packagesDB: URL)
            case removingExistingDB(URL)
            case progress(name: String, done: Int, total: Int)
            case finished(Outcome)
        }

        /// GoF Observer (1994 p. 293) for `Indexer.PackagesService`
        /// lifecycle events. Replaces the inline
        /// `handler: @escaping @Sendable (Event) -> Void` closure
        /// parameter previously taken by
        /// `Indexer.PackagesService.run`. See
        /// `Indexer.DocsService.EventObserving` for the full rationale.
        public protocol EventObserving: Sendable {
            /// Called once per lifecycle transition. Implementations
            /// should be non-blocking; the service waits for return
            /// before continuing.
            func observe(event: Event)
        }
    }
}
