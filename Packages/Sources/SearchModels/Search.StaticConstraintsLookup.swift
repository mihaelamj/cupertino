import Foundation

extension Search {
    /// Cross-target seam (#759 iteration 3) for the authoritative
    /// Apple-type generic-constraints table.
    ///
    /// **Background.** Iterations 1 (AST `genericWhereClause` walk in
    /// `ASTIndexer.Extractor`) and 2 (post-save hierarchy propagation
    /// in `Search.Index.HierarchyConstraints`) extract / propagate
    /// constraint info from what Apple's flattened DocC JSON
    /// (`declaration.code` field) happens to carry. Iteration 3 adds
    /// the authoritative source: Apple's symbol-graph output from
    /// `swift symbolgraph-extract` against the Apple SDKs. Each
    /// symbol-graph carries structured `swiftGenerics.constraints`
    /// entries that don't depend on the corpus crawler having
    /// preserved them. The `AppleConstraintsKit` package parses
    /// the symbol-graph JSON, maps `pathComponents` to
    /// `apple-docs://...` URIs, and produces a filtered constraint
    /// table the indexer reads at index time.
    ///
    /// **Why a protocol here, not a concrete import in Search.**
    /// Per `gof-di-rules.md` rule 3 ("Cross-target seams are named
    /// protocols, declared in foundation-only *Models targets") + rule
    /// 5 ("every package can be pulled out of monorepo anytime"):
    /// `Search` declares the contract it needs; the binary
    /// (composition root) wires `AppleConstraintsKit.Table` (or any
    /// future alternative source) in. Search remains foundation-only
    /// and stays standalone-portable.
    ///
    /// **Use site.** `Search.IndexBuilder.buildIndex(...)` takes an
    /// optional `lookup: any StaticConstraintsLookup`. When non-nil,
    /// the build's post-iteration-2 pass calls
    /// `Search.Index.applyAppleStaticConstraints(table:)`, which
    /// iterates the lookup's entries and overrides
    /// `doc_symbols.generic_constraints` for matching URIs.
    public protocol StaticConstraintsLookup: Sendable {
        /// Snapshot of every (doc-URI, constraints) entry in the
        /// static table. Returned in one call rather than per-URI
        /// because typical sources (a JSON-on-disk Codable file) hold
        /// the full table in memory anyway, and the indexer iterates
        /// every entry exactly once during pass 3. An async signature
        /// preserves room for future implementations that load
        /// lazily.
        ///
        /// **Order.** Implementations may return entries in any order.
        /// The indexer treats the result as a set; duplicate URIs in
        /// the input collapse to a last-write-wins semantic at the
        /// SQL UPDATE layer.
        ///
        /// **Empty result is valid.** An empty array means the table
        /// loaded successfully but carries no entries (e.g. the
        /// generator hadn't been run yet). The indexer logs and
        /// proceeds without applying constraints from this source.
        func allEntries() async throws -> [StaticConstraintEntry]
    }

    /// One row in the authoritative constraint table.
    ///
    /// `docURI` is the cupertino-internal URI shape
    /// (`apple-docs://<framework>/<path-segments-lowercased>`) that
    /// matches the `doc_symbols.doc_uri` column.
    ///
    /// `constraints` is the joined-comma blob to write into
    /// `doc_symbols.generic_constraints`, e.g.
    /// `["View", "Hashable"]` for `Picker<Label: View, SelectionValue:
    /// Hashable, Content: View>`. Duplicates within the array (e.g.
    /// two View constraints when two params both require View) are
    /// preserved; the substring-LIKE search predicate doesn't care.
    public struct StaticConstraintEntry: Sendable, Hashable, Codable {
        public let docURI: String
        public let constraints: [String]

        public init(docURI: String, constraints: [String]) {
            self.docURI = docURI
            self.constraints = constraints
        }
    }
}
