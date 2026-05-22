import ASTIndexer
import Foundation
import SearchModels
import SharedConstants

// MARK: - Sample.Index.Writer

/// Write-side seam for the SampleIndex database actor.
///
/// `Sample.Index.Database` (the concrete actor in the `SampleIndexSQLite`
/// SPM target) ships a full read+write surface, but the only legitimate
/// internal-target consumer of the write methods is
/// `Sample.Index.Builder` (in `SampleIndex`) which walks the unzipped
/// sample-code catalog and feeds rows into the database. Lifting those
/// methods into a protocol here lets `Builder` be typed against the
/// abstraction and stay in the orchestration `SampleIndex` target while
/// the SQLite-backed `Database` lives in `SampleIndexSQLite`.
///
/// Mirrors the `Search.IndexWriter` seam in `SearchModels`: protocol
/// lives in a foundation-only target; the concrete actor conforms via
/// a one-line witness extension in its owning SPM target; composition
/// roots instantiate the concrete and upcast it to
/// `any Sample.Index.Writer` when handing it to consumers.
extension Sample.Index {
    public protocol Writer: Sendable {
        /// Insert or replace a project row plus its sidecar columns.
        func indexProject(_ project: Sample.Index.Project) async throws

        /// Insert or replace a single source-file row. Uses the
        /// project_id from the file argument.
        func indexFile(_ file: Sample.Index.File) async throws

        /// Look up the rowid of a previously-indexed file. Lives on the
        /// write seam because Builder uses it between `indexFile` and
        /// the per-file symbol/import writes: the symbol + import rows
        /// carry the file's rowid as a foreign key. Returning nil from
        /// this method causes Builder to silently drop every symbol +
        /// import row for that file (`if let fileId = ...` guard), so
        /// conformers MUST return the rowid of the row that
        /// `indexFile(_:)` just inserted; a no-op return is a silent
        /// data-loss bug.
        func getFileId(projectId: String, path: String) async throws -> Int64?

        /// Insert the symbol rows extracted by the AST pass for one
        /// file. Symbols carry the file_id rowid returned by
        /// `getFileId`.
        func indexSymbols(fileId: Int64, symbols: [ASTIndexer.Symbol]) async throws

        /// Insert the import rows extracted by the AST pass for one
        /// file. Mirrors `indexSymbols` on shape.
        func indexImports(fileId: Int64, imports: [ASTIndexer.Import]) async throws

        /// Delete every row tied to a project (files, symbols, imports,
        /// FTS entries, project row itself). Used by Builder's
        /// force-reindex path.
        func deleteProject(id: String) async throws

        /// Apply the authoritative Apple-type static-constraints lookup
        /// to the sample-code file_symbols table. Idempotent; stamps
        /// `enrichment_version` on each updated row. Used by the
        /// `Enrichment.SamplesAppleConstraintsPass`. Returns the
        /// affected-row count; nil `lookup` short-circuits to 0
        /// without touching the DB.
        func applyAppleStaticConstraints(
            lookup: (any Search.StaticConstraintsLookup)?,
            enrichmentVersion: Int
        ) async throws -> Int
    }
}
