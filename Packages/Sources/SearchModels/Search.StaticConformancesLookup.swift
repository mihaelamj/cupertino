import Foundation

// MARK: - Search.StaticConformancesLookup

extension Search {
    /// Read seam for the symbolgraph-derived Apple conformance graph
    /// (`apple-conformances.json`). Mirrors `Search.StaticConstraintsLookup`:
    /// the composition root constructs a concrete (an
    /// `AppleConstraintsKit.ConformanceTable`) from JSON and injects it as
    /// `any Search.StaticConformancesLookup`, so the SearchSQLite enrichment
    /// pass never imports AppleConstraintsKit (foundation-only protocol seam,
    /// gof-di-rules Rule 3).
    ///
    /// Why this exists separately from the AST-extracted `doc_symbols.conformances`:
    /// DocC markdown + the indexed source declare only a fraction of an Apple
    /// type's conformances; the SDK symbol-graph carries the full set (~108k
    /// `conformsTo` edges vs ~8.6k in the DB). This is the conformance analogue
    /// of the constraints pass (#759): symbol-graph truth the rendered docs omit.
    public protocol StaticConformancesLookup: Sendable {
        /// All conformance entries (one per conforming type URI that has at
        /// least one kept `conformsTo` / `inheritsFrom` edge).
        func allConformanceEntries() async throws -> [StaticConformanceEntry]
    }

    /// One conforming type's symbol-graph conformances: the type's
    /// `apple-docs://` URI plus the protocol / superclass display names it
    /// conforms to or inherits from (e.g. `["View", "Equatable"]`).
    /// Structurally parallel to `StaticConstraintEntry`.
    public struct StaticConformanceEntry: Sendable, Hashable, Codable {
        public let docURI: String
        public let conformsTo: [String]

        public init(docURI: String, conformsTo: [String]) {
            self.docURI = docURI
            self.conformsTo = conformsTo
        }
    }
}
