import Foundation

// MARK: - Sample Namespace

/// Cross-cutting namespace for every type whose responsibility is Apple sample
/// code — fetching, indexing, cleaning, querying, formatting. The previous
/// layout spread these types across module-folder namespaces (Cleanup,
/// Services, Core, SampleIndex, Search), making it hard to see at a glance
/// which corner of the system handles samples. Pulling them all under
/// `Sample.*` gives one entry point with sub-namespaces mirroring the
/// originating module so provenance stays readable.
///
/// Layout:
/// - `Sample.Cleanup.*`   — sample-archive post-fetch cleanup (was Cleanup).
/// - `Sample.Core.*`      — sample-code catalog + fetch primitives that
///                          live in the Core SPM target.
/// - `Sample.Services.*`  — sample-flavoured Services components
///                          (`CandidateFetcher` etc.).
/// - `Sample.Search.*`    — sample search service + query / result types
///                          (was Services.ReadCommands.SampleSearchService).
/// - `Sample.Index.*`     — the SampleIndex SPM target's contents.
/// - `Sample.Indexer`     — search indexer for sample code (was
///                          Search.SampleCodeIndexer).
/// - `Sample.Atom`        — `ResultAtom` conformance for sample search
///                          hits (was Search.SampleAtom).
/// - `Sample.Format.*`    — sample-flavoured `Result`s in
///                          Markdown / JSON / Text.
///
/// Sub-namespaces are declared as empty enums here so any SPM target that
/// imports SharedConstants can extend them with concrete types via
/// `extension Sample.<sub> { ... }`. Concrete types follow in the per-area
/// PRs (this file just opens the surface).
public enum Sample {
    /// Sample-archive post-fetch cleanup. The actor that prunes orphaned
    /// archives + manifests after a fetch run lives here as
    /// `Sample.Cleanup.Cleaner`.
    public enum Cleanup {}

    /// Sample-code catalog + fetch primitives shipped in the Core SPM target:
    /// `Catalog`, `Entry`, `Statistics`, `Progress`, `Project`.
    public enum Core {}

    /// Sample-flavoured Services components. Currently holds
    /// `Sample.Services.CandidateFetcher` (the `Search.CandidateFetcher`
    /// implementation that returns sample-code hits).
    public enum Services {}

    /// Sample search-service surface: the `Service` actor that wraps a
    /// SampleIndex database, plus the `Query` and `Result` value types.
    public enum Search {}

    /// The SampleIndex SPM target's contents — index database + builder +
    /// availability sidecar.
    public enum Index {}

    /// Sample-flavoured `Result`s. Sub-namespaces split by output
    /// medium: `Sample.Format.Markdown.*`, `Sample.Format.JSON.*`,
    /// `Sample.Format.Text.*`.
    public enum Format {
        /// Markdown-rendering formatters for sample search hits, sample
        /// project listings, sample-file content.
        public enum Markdown {}

        /// JSON-encoding formatters for the same.
        public enum JSON {}

        /// Plain-text formatters for the same.
        public enum Text {}
    }
}
