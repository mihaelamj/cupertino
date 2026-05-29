import Foundation

// MARK: - Search.EnrichmentInput

extension Search {
    /// Declarative description of an enrichment INPUT a source needs present
    /// before it can be indexed at full coverage.
    ///
    /// Carried per-source on `Search.SourceDefinition.requiredEnrichmentInputs`
    /// and checked by ONE generic preflight (`Search.EnrichmentInputPreflight`)
    /// over the selected sources. This replaces the pre-2026-05-28 hardcoded
    /// per-source guards (the #1072 `apple-constraints.json` check and
    /// `assertPackageAvailabilityComplete`), each of which was a per-source
    /// edit-point sitting in central save logic, i.e. a Source Independence
    /// Axiom violation. A new source declares its inputs here; the generic
    /// preflight needs no per-source branch.
    public struct EnrichmentInput: Sendable, Equatable, Hashable {
        /// Where the input file is expected to live. A closed set of location
        /// KINDS, reused by every source (never extended per source), so the
        /// generic preflight can interpret it without an id-switch.
        public enum Scope: Sendable, Equatable, Hashable {
            /// A single file at `<baseDirectory>/<filename>` (e.g.
            /// `apple-constraints.json`).
            case baseDirectoryFile
            /// A sidecar required alongside every corpus item that carries
            /// `marker`. The preflight walks the source's corpus directory,
            /// finds each directory holding a `marker` file, and flags those
            /// missing `filename` (e.g. each `<owner>/<repo>/` with a
            /// `manifest.json` must also carry `availability.json`).
            case perCorpusItem(marker: String)
        }

        /// File the source's enrichment needs (e.g. `apple-constraints.json`,
        /// `availability.json`).
        public let filename: String

        /// One line on the coverage lost without it, surfaced in the preflight
        /// error so the operator understands the cost.
        public let purpose: String

        /// The exact command that produces or fetches the file, surfaced in
        /// the preflight error so the operator recovers without reading source.
        public let howToObtain: String

        /// Where the file is expected to live.
        public let scope: Scope

        public init(filename: String, purpose: String, howToObtain: String, scope: Scope) {
            self.filename = filename
            self.purpose = purpose
            self.howToObtain = howToObtain
            self.scope = scope
        }
    }
}

// MARK: - Shared input constants

extension Search.EnrichmentInput {
    /// Apple SDK generic-constraint table consumed by the constraints
    /// enrichment passes on apple-docs / samples / packages (#759 iter 3).
    /// Without it the pass silently runs at iter 1+2 (~16% coverage) instead
    /// of iter 3 (~38%). Reused by every source that runs a constraints pass.
    public static let appleConstraints = Search.EnrichmentInput(
        filename: "apple-constraints.json",
        purpose: "Apple generic-constraint enrichment (iter 3 ~38% vs iter 1+2 ~16% coverage)",
        howToObtain: "Run `cupertino setup` to fetch it, or `cupertino-constraints-gen` to produce it locally.",
        scope: .baseDirectoryFile
    )

    /// Apple SDK conformance table consumed by the conformance enrichment
    /// passes on apple-docs / samples / packages, the conformance sibling of
    /// `appleConstraints`. Without it the authoritative SDK conformance graph
    /// (~108k edges) is dropped and only the AST-derived conformances (~8.6k)
    /// stand, visible only by inspecting the DB. Required symmetrically with
    /// `appleConstraints` on every source that runs a conformance pass.
    public static let appleConformances = Search.EnrichmentInput(
        filename: "apple-conformances.json",
        purpose: "Apple SDK conformance enrichment (~108k SDK edges vs ~8.6k AST-derived)",
        howToObtain: "Run `cupertino setup` to fetch it, or `cupertino-constraints-gen conformances` to produce it locally.",
        scope: .baseDirectoryFile
    )

    /// Per-package availability sidecar produced by the availability
    /// annotator. Without it `swift_tools_version` degrades and the
    /// `@available` platform floors are lost. One sidecar per package
    /// (`<owner>/<repo>/availability.json`, keyed off the package's
    /// `manifest.json`).
    public static let packageAvailability = Search.EnrichmentInput(
        filename: "availability.json",
        purpose: "package @available platform floors plus accurate swift-tools-version",
        howToObtain: "Run `cupertino fetch --source packages --annotate-availability` to write it in place (no re-download), then re-run save.",
        scope: .perCorpusItem(marker: "manifest.json")
    )
}
