import Foundation

// MARK: - Search.DocsIndexingRunner

/// Runner for a complete `search.db` documentation indexing pass:
/// open the index, build the strategy array, walk every on-disk
/// source directory (apple-docs JSON, Swift Evolution markdown,
/// Swift.org, Apple Archive, HIG), write rows, and disconnect.
/// GoF Strategy pattern (Gamma et al, 1994): a family of algorithms
/// (production `Search.Index` + `Search.IndexBuilder` pipeline,
/// test fixture stubs) interchangeable behind a named protocol.
///
/// `Indexer.DocsService` accepts a conformer at run-time so the
/// Indexer SPM target keeps its dependency graph free of the
/// concrete Search-target actors. The composition root (the CLI's
/// `save` command) supplies a `LiveDocsIndexingRunner` backed by the
/// standard `Search.Index` + `Search.IndexBuilder` wiring.
///
/// This replaces the previous
/// `Search.DocsIndexingRun = @Sendable (DocsIndexingInput, callback) async throws -> Outcome`
/// closure typealias. The protocol form names the contract at the
/// constructor site (`docsIndexingRunner:`), makes captured-state
/// surface explicit on the conforming type's stored properties, and
/// produces one-line test mocks instead of multi-arg async closures.
///
/// Progress reporting goes through the typed `Search.IndexingProgressReporting`
/// Observer protocol (GoF p. 293) — the previous design carve-out for
/// "genuine (processed, total) callback" closures is reversed per the
/// standing cupertino rule "no closures, they ate magic." The Indexer
/// orchestrator (`Indexer.DocsService.run`) bridges its closure-shaped
/// `handler:` parameter to a `Search.IndexingProgressReporting` conformer
/// before invoking this method.
public extension Search {
    protocol DocsIndexingRunner: Sendable {
        /// Run one full indexing pass and return its outcome.
        ///
        /// - Parameters:
        ///   - input: The full parameter bundle (paths + injected
        ///     markdown strategy + injected sample-catalog provider).
        ///   - progress: Observer receiving `(processed, total)` reports
        ///     as the indexer makes progress. Pass a Noop conformer to
        ///     opt out of progress reports.
        /// - Returns: The aggregated `DocsIndexingOutcome`.
        func run(
            input: DocsIndexingInput,
            progress: any Search.IndexingProgressReporting
        ) async throws -> DocsIndexingOutcome
    }
}

// MARK: - Search.DocsIndexingInput

/// Parameter bundle for `Search.DocsIndexingRunner.run`. Carries
/// every URL the indexer needs to find the source corpus + the two
/// strategy / provider conformers the indexer threads down into its
/// strategy implementations.
public extension Search {
    struct DocsIndexingInput: Sendable {
        public let searchDBPath: URL
        public let docsDirectory: URL
        public let evolutionDirectory: URL?
        public let swiftOrgDirectory: URL?
        public let archiveDirectory: URL?
        public let higDirectory: URL?
        public let clearExisting: Bool
        public let markdownStrategy: any Search.MarkdownToStructuredPageStrategy
        public let sampleCatalogProvider: any Search.SampleCatalogProvider

        public init(
            searchDBPath: URL,
            docsDirectory: URL,
            evolutionDirectory: URL?,
            swiftOrgDirectory: URL?,
            archiveDirectory: URL?,
            higDirectory: URL?,
            clearExisting: Bool,
            markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
            sampleCatalogProvider: any Search.SampleCatalogProvider
        ) {
            self.searchDBPath = searchDBPath
            self.docsDirectory = docsDirectory
            self.evolutionDirectory = evolutionDirectory
            self.swiftOrgDirectory = swiftOrgDirectory
            self.archiveDirectory = archiveDirectory
            self.higDirectory = higDirectory
            self.clearExisting = clearExisting
            self.markdownStrategy = markdownStrategy
            self.sampleCatalogProvider = sampleCatalogProvider
        }
    }
}

// MARK: - Search.DocsIndexingOutcome

/// Statistics emitted by a completed `Search.DocsIndexingRunner` run.
/// The Indexer translates this into its public
/// `Indexer.DocsService.Outcome` event payload.
public extension Search {
    struct DocsIndexingOutcome: Sendable {
        public let documentCount: Int
        public let frameworkCount: Int

        public init(documentCount: Int, frameworkCount: Int) {
            self.documentCount = documentCount
            self.frameworkCount = frameworkCount
        }
    }
}
