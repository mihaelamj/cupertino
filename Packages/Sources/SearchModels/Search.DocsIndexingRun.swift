import Foundation

// MARK: - Search.DocsIndexingRun

/// Closure shape for running a complete `search.db` documentation
/// indexing pass: open the index, build the strategy array, walk every
/// on-disk source directory (apple-docs JSON, Swift Evolution markdown,
/// Swift.org, Apple Archive, HIG), write rows, and disconnect.
///
/// `Indexer.DocsService` accepts one of these instead of reaching
/// directly into `Search.Index` + `Search.IndexBuilder`, so the
/// Indexer SPM target keeps its dependency graph free of the
/// concrete Search-target actors. The composition root (the CLI's
/// `save` command) supplies the closure with the standard
/// `Search.Index` + `Search.IndexBuilder` wiring.
///
/// Mirrors the `Search.PackageIndexingRun` /
/// `Search.MarkdownToStructuredPage` / `Search.SampleCatalogFetch` /
/// `MakeSearchDatabase` closure-typealias pattern already in
/// SearchModels.
public extension Search {
    typealias DocsIndexingRun = @Sendable (
        _ input: DocsIndexingInput,
        _ onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> DocsIndexingOutcome
}

// MARK: - Search.DocsIndexingInput

/// Parameter bundle for `Search.DocsIndexingRun`. Carries every URL
/// the indexer needs to find the source corpus + the two markdown /
/// sample-catalog closures the indexer threads down into its strategy
/// implementations.
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
        public let sampleCatalogFetch: Search.SampleCatalogFetch

        public init(
            searchDBPath: URL,
            docsDirectory: URL,
            evolutionDirectory: URL?,
            swiftOrgDirectory: URL?,
            archiveDirectory: URL?,
            higDirectory: URL?,
            clearExisting: Bool,
            markdownStrategy: any Search.MarkdownToStructuredPageStrategy,
            sampleCatalogFetch: @escaping Search.SampleCatalogFetch
        ) {
            self.searchDBPath = searchDBPath
            self.docsDirectory = docsDirectory
            self.evolutionDirectory = evolutionDirectory
            self.swiftOrgDirectory = swiftOrgDirectory
            self.archiveDirectory = archiveDirectory
            self.higDirectory = higDirectory
            self.clearExisting = clearExisting
            self.markdownStrategy = markdownStrategy
            self.sampleCatalogFetch = sampleCatalogFetch
        }
    }
}

// MARK: - Search.DocsIndexingOutcome

/// Statistics emitted by a completed `Search.DocsIndexingRun`. The
/// Indexer translates this into its public `Indexer.DocsService.Outcome`
/// event payload.
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
