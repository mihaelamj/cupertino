import Foundation

// MARK: - Search.DocsIndexing.Runner

/// Sub-namespace grouping the three DocsIndexing-related types
/// (Runner protocol + Input value type + Outcome value type). Post-#1042
/// type-name deepening: pre-rename `Search.DocsIndexingRunner` /
/// `Search.DocsIndexingInput` / `Search.DocsIndexingOutcome` sat at
/// the same nesting level under `extension Search`; the deeper form
/// makes the family obvious to readers. Back-compat typealiases at
/// the bottom keep pre-rename call-sites compiling.
extension Search {
    public enum DocsIndexing {}
}

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
/// Progress reporting goes through the typed `Search.IndexingProgressReporting`
/// Observer protocol (GoF p. 293); per the standing cupertino rule
/// "no closures, they ate magic." The Indexer orchestrator
/// (`Indexer.DocsService.run`) bridges its closure-shaped `handler:`
/// parameter to a `Search.IndexingProgressReporting` conformer before
/// invoking this method.
extension Search.DocsIndexing {
    public protocol Runner: Sendable {
        /// Run one full indexing pass and return its outcome.
        ///
        /// - Parameters:
        ///   - input: The full parameter bundle (paths + injected
        ///     markdown strategy + injected sample-catalog provider).
        ///   - progress: Observer receiving `(processed, total)` reports
        ///     as the indexer makes progress. Pass a Noop conformer to
        ///     opt out of progress reports.
        /// - Returns: The aggregated `Outcome`.
        func run(
            input: Input,
            progress: any Search.IndexingProgressReporting
        ) async throws -> Outcome
    }

    /// Parameter bundle for `Search.DocsIndexing.Runner.run`. Carries
    /// every URL the indexer needs to find the source corpus + the two
    /// strategy / provider conformers the indexer threads down into its
    /// strategy implementations.
    public struct Input: Sendable {
        public let searchDBPath: URL
        public let docsDirectory: URL
        public let evolutionDirectory: URL?
        public let swiftOrgDirectory: URL?
        public let archiveDirectory: URL?
        public let higDirectory: URL?
        public let clearExisting: Bool
        public let markdownStrategy: any Search.MarkdownToStructuredPageStrategy
        public let sampleCatalogProvider: any Search.SampleCatalog.Provider

        /// #1045 Gap 4: registry-derived per-source directory map.
        /// Composition root populates `provider.definition.id → fetchInfo.outputDir`
        /// for every registered provider; the indexer's
        /// `resolveSourceDirectory(for:input:)` consults this dict
        /// first and falls back to the pre-#1045 typed-field switch
        /// for sources the dict doesn't cover.
        ///
        /// Pre-fix `resolveSourceDirectory` was a 7-arm `switch
        /// provider.definition.id`. A new source needed both a new
        /// typed `*Directory` field above AND a new switch arm. With
        /// `directoryByKey` populated, the dict lookup covers
        /// arbitrary new sources without touching either surface.
        ///
        /// The 5 typed `*Directory` fields above stay for back-compat
        /// (today's resolveSourceDirectory still uses them via the
        /// fallback path for the 2 sentinel arms — `samples` and
        /// `swiftBook` — that aren't pure directory lookups). A
        /// follow-up will dissolve the typed fields once every
        /// dispatch arm migrates to the dict.
        public let directoryByKey: [String: URL?]

        public init(
            searchDBPath: URL,
            docsDirectory: URL,
            evolutionDirectory: URL?,
            swiftOrgDirectory: URL?,
            archiveDirectory: URL?,
            higDirectory: URL?,
            clearExisting: Bool,
            markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
            sampleCatalogProvider: any Search.SampleCatalog.Provider,
            directoryByKey: [String: URL?] = [:]
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
            self.directoryByKey = directoryByKey
        }
    }

    /// Statistics emitted by a completed `Search.DocsIndexing.Runner`
    /// run. The Indexer translates this into its public
    /// `Indexer.DocsService.Outcome` event payload.
    public struct Outcome: Sendable {
        public let documentCount: Int
        public let frameworkCount: Int
        /// #588 import-diligence aggregated breakdown over every
        /// strategy that ran. Zero for legacy callers; populated by
        /// the apple-docs strategy post-#588.
        public let breakdown: Search.ImportDiligenceBreakdown

        public init(
            documentCount: Int,
            frameworkCount: Int,
            breakdown: Search.ImportDiligenceBreakdown = .zero
        ) {
            self.documentCount = documentCount
            self.frameworkCount = frameworkCount
            self.breakdown = breakdown
        }
    }
}

/// Back-compat aliases for pre-#1042 consumers.
extension Search {
    public typealias DocsIndexingRunner = DocsIndexing.Runner
    public typealias DocsIndexingInput = DocsIndexing.Input
    public typealias DocsIndexingOutcome = DocsIndexing.Outcome
}
