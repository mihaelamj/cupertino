import Foundation

// MARK: - Indexer.DocsService — value types + Observer protocol

extension Indexer {
    /// Builds `search.db` from the on-disk docs corpus (apple-docs JSON,
    /// Swift Evolution markdown, Swift.org, Apple Archive, HIG).
    ///
    /// The value types here (`Request`, `Outcome`, `Event`,
    /// `EventObserving`) form the foundation-only seam. The
    /// `static func run(...)` orchestrator that consumes them lives in
    /// the `Indexer` producer target as an extension on this enum.
    public enum DocsService {
        public struct Request: Sendable {
            public let baseDir: URL
            public let docsDir: URL?
            public let evolutionDir: URL?
            public let swiftOrgDir: URL?
            public let archiveDir: URL?
            public let higDir: URL?
            public let searchDB: URL?
            public let clear: Bool

            public init(
                baseDir: URL,
                docsDir: URL? = nil,
                evolutionDir: URL? = nil,
                swiftOrgDir: URL? = nil,
                archiveDir: URL? = nil,
                higDir: URL? = nil,
                searchDB: URL? = nil,
                clear: Bool = false
            ) {
                self.baseDir = baseDir
                self.docsDir = docsDir
                self.evolutionDir = evolutionDir
                self.swiftOrgDir = swiftOrgDir
                self.archiveDir = archiveDir
                self.higDir = higDir
                self.searchDB = searchDB
                self.clear = clear
            }
        }

        public struct Outcome: Sendable {
            public let searchDBPath: URL
            public let documentCount: Int
            public let frameworkCount: Int

            public init(
                searchDBPath: URL,
                documentCount: Int,
                frameworkCount: Int
            ) {
                self.searchDBPath = searchDBPath
                self.documentCount = documentCount
                self.frameworkCount = frameworkCount
            }
        }

        public enum Event: Sendable {
            /// Emitted once at the start of `run`, before any disk
            /// activity, carrying the resolved on-disk `search.db`
            /// destination. Lets users + log readers confirm upfront
            /// where the output is being written without having to
            /// re-derive base-dir + filename composition from the CLI
            /// args. Independent of `.removingExistingDB` (which only
            /// fires when an existing DB needs to be wiped first).
            case databaseTarget(URL)
            case removingExistingDB(URL)
            case initializingIndex
            case missingOptionalSource(label: String, url: URL)
            /// Emitted once per optional source (Swift Evolution / Swift.org /
            /// Apple Archive / HIG) whose directory IS present on disk at
            /// startup. Mirrors `missingOptionalSource` on the success side
            /// so long-running save jobs surface upfront which sources will
            /// be indexed; without this event the success path is silent
            /// and the user has to wait until the per-source strategy
            /// actually runs (potentially hours later) to confirm.
            case foundOptionalSource(label: String, url: URL)
            case availabilityMissing
            case progress(processed: Int, total: Int, percent: Double)
            case finished(Outcome)
        }

        /// GoF Observer (1994 p. 293) for `Indexer.DocsService` lifecycle
        /// events. Replaces the inline
        /// `handler: @escaping @Sendable (Event) -> Void` closure
        /// parameter previously taken by `Indexer.DocsService.run`.
        ///
        /// The CLI binary's `cupertino save --source apple-docs` composition root
        /// builds a named struct conformer that translates events into
        /// progress-bar updates and log lines. A test stub can return a
        /// non-blocking observer that collects events into an array for
        /// assertion.
        ///
        /// Aligns with the standing cupertino rule "no closures, they
        /// ate magic" (see `mihaela-agents/Rules/swift/gof-di-rules.md`
        /// rule 5).
        public protocol EventObserving: Sendable {
            /// Called once per lifecycle transition. Implementations
            /// should be non-blocking; the service waits for return
            /// before continuing.
            func observe(event: Event)
        }
    }
}
