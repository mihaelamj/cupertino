import Foundation
import LoggingModels
import SearchModels
import SearchSchema
import SharedConstants
import SQLite3
import SQLiteSupport

// MARK: - Search Index

/// SQLite FTS5-based full-text search index for documentation
extension Search {
    public actor Index {
        /// Current schema version - increment when schema changes
        /// Version history:
        /// - 1: Initial schema (docs_fts, docs_metadata, packages, package_dependencies, sample_code)
        /// - 2: Added doc_code_examples and doc_code_fts tables
        /// - 3: Added json_data column to docs_metadata for full JSON storage
        /// - 4: Added source field to docs_fts and docs_metadata for source-based filtering
        /// - 5: Added language field to docs_fts and docs_metadata (BREAKING: requires database rebuild)
        /// - 6: Added availability columns (min_ios, min_macos, etc.) for efficient filtering
        /// - 7: Previous version
        /// - 8: Added attributes column to docs_structured for @attribute indexing
        /// - 9: Added doc_symbols, doc_imports tables for SwiftSyntax AST indexing (#81)
        /// - 10: Added synonyms column to framework_aliases
        /// - 11: Added kind + symbols columns to docs_metadata (#192 section C). `kind` is
        ///       the C1 taxonomy (`symbolPage`, `article`, ...) populated by
        ///       `Search.Classify.kind(...)`. `symbols` is a denormalized text blob of
        ///       symbol names written for SQL consumers.
        /// - 12: Added `symbols` column to docs_fts (#192 section D) so bm25 can weight
        ///       directly on AST-derived symbol names. BREAKING — FTS5 does not support
        ///       ALTER TABLE ADD COLUMN, so existing DBs must be rebuilt.
        /// - 13: URL case canonicalization (#283). v12 DBs carry case-axis URI duplicates
        ///       (~30% of rows in shipped v1.0.0/v1.0.1) because the pre-#283
        ///       `URLUtilities.filename(_:)` hashed the raw case-preserving URL.
        ///       BREAKING: existing v12 DBs are rejected at open. Upgrade path is
        ///       `cupertino setup` to download the v1.0.2 bundle, which ships
        ///       pre-built at v13 with zero case-axis duplicate clusters.
        /// - 14: Index-time CamelCase expansion (#77). Adds `symbol_components`
        ///       FTS column carrying acronym-aware splits of every AST-derived
        ///       symbol name on the page (`LazyVGrid → Lazy / VGrid / Grid`,
        ///       `URLSession → URL / Session`, etc.). BM25F slot weighted at
        ///       1.5 so `search("grid")` surfaces the LazyVGrid page without
        ///       diluting exact-symbol ranking (the `symbols` column stays
        ///       at 5.0). BREAKING — FTS5 does not support ALTER TABLE ADD
        ///       COLUMN; existing v13 DBs are rejected at open with the same
        ///       "rebuild required" message v12 received.
        /// - 15: Class-inheritance edges (#274). New `inheritance` table
        ///       persists parent→child rows extracted from Apple's DocC
        ///       JSON `relationshipsSections.inheritsFrom` and
        ///       `inheritedBy` arrays. Two `B-tree` indexes
        ///       (`inheritance_by_parent`, `inheritance_by_child`) cover
        ///       both walk directions; the same data the v13/v14 indexer
        ///       already had access to (via `relationshipsSections`)
        ///       finally gets a queryable edge table instead of being
        ///       dropped into a default-section bucket. BREAKING — the
        ///       table is created in `createTables()` only on fresh
        ///       inits, and existing DBs without it have no rows to
        ///       walk; the only meaningful upgrade path is a re-index.
        /// - 16: `implementation_swift_version` column on `docs_metadata`
        ///       (#225 Part B). Captures the Swift toolchain version a
        ///       swift-evolution proposal landed in (parsed from
        ///       `Implementation: Swift <X.Y>` / `Status: Implemented (Swift <X.Y>)`
        ///       lines in the proposal markdown). Populated only for
        ///       swift-evolution rows; NULL on every other source.
        ///       Filter surface: `cupertino search --swift <ver>`. Old
        ///       rows on a v15 DB migrate in place via ALTER TABLE ADD
        ///       COLUMN — values stay NULL until the next re-index
        ///       parses them, which matches the #226 platform-filter
        ///       semantic (NULL rows are rejected when a filter is set,
        ///       passed through when it isn't).
        /// - 17: `generic_constraints` column on `doc_symbols` (#755).
        ///       The pre-fix `generic_params` column stored type-parameter
        ///       NAMES only (`T`, `Element`, `Result`); the MCP
        ///       `search_generics` tool advertised constraint search
        ///       but the corpus never carried constraint clauses
        ///       (only 17 rows of 351,495 had constraint-form values).
        ///       The new column stores constraint halves harvested
        ///       from two sources at index time: (1) the AST extractor's
        ///       `"T: Collection"` output (split into name + constraint
        ///       pair, written to `generic_params` and
        ///       `generic_constraints` respectively); (2) where-clause
        ///       + inline `<T: X>` patterns parsed from the `signature`
        ///       column for symbols whose declarations carry them.
        ///       Search predicate moves from `generic_params LIKE` to
        ///       `generic_constraints LIKE`. v16 DBs migrate in place
        ///       via ALTER TABLE ADD COLUMN; values stay NULL until
        ///       the next re-index populates them.
        /// Current `search.db` schema version. Source of truth lives at
        /// `Search.Schema.currentVersion` in the foundation-only
        /// `SearchSchema` target (lifted by epic #893's child #898 sub-PR A).
        /// Re-exported here so existing call sites that reference
        /// `Search.Index.schemaVersion` (test fixtures, doctor diagnostics)
        /// compile unchanged. New code should prefer
        /// `Search.Schema.currentVersion` directly.
        public static let schemaVersion: Int32 = Search.Schema.currentVersion

        // Properties are module-internal (default visibility) so the
        // Search.Index.<Concern>.swift extension files (all in this same
        // SearchSQLite target) can access them. Public API surface is
        // unchanged; internal only widens visibility within this
        // SearchSQLite target, not outside.
        public nonisolated let connection: Search.Connection
        var database: OpaquePointer? {
            connection.database
        }

        public nonisolated var dbPath: URL {
            connection.dbPath
        }

        public nonisolated var readOnly: Bool {
            connection.readOnly
        }

        var isInitialized: Bool {
            connection.isInitialized
        }

        /// GoF Strategy seam for log emission (1994 p. 315). Injected by
        /// the binary's composition root.
        let logger: any LoggingModels.Logging.Recording
        /// Composition-root-injected map from source id to its indexer
        /// concrete. Consumed by `indexItem(_:extractSymbols:)` to
        /// dispatch a `Search.SourceItem` to the right indexer. Pre-#932
        /// this lookup went through the static `Search.IndexerRegistry`
        /// enum; #932 deleted that and lifted the dict onto the actor so
        /// adding a new source no longer means editing a static dict.
        /// Defaulted to `[:]` so test fixtures that never call
        /// `indexItem` keep zero churn; the production composition root
        /// in `CLIImpl.Command.Save.Indexers.swift` passes the full
        /// production dict at construction.
        ///
        /// Marked `nonisolated public` because the value is set at init
        /// and never mutated; downstream tests (and future stricter
        /// consumers) need read access to verify the composition-root
        /// assembly is the sole source of truth. Sendable holds because
        /// `Search.SourceIndexer` requires Sendable conformance.
        public nonisolated let indexers: [String: any Search.SourceIndexer]
        /// Composition-root-injected `Search.SourceLookup` carrying the
        /// full set of `Search.SourceDefinition` rows the binary knows
        /// about. Replaces pre-#934 reach-for-the-static lookups against
        /// `Search.SourceRegistry.all`. The ranking path in
        /// `Search.Index.Search` reads source properties + boosted-source
        /// lists from this value; the composition root in CLI inlines
        /// the 8-entry production list. Defaulted to `.empty` is NOT
        /// allowed at the init level: every call site explicitly passes
        /// `sourceLookup:` per `gof-di-rules.md` Rule 2.
        public nonisolated let sourceLookup: Search.SourceLookup

        /// Count of docs the incremental indexer skipped this run because the
        /// doc was already in the DB with an unchanged `content_hash` (#1146).
        /// `indexStructuredDocument` skips such docs BEFORE the expensive AST
        /// extraction, so a non-`--clear` save resumes / updates incrementally.
        /// A `--clear` run wipes the DB first, so this stays 0 there.
        public internal(set) var incrementalSkips = 0

        public init(
            connection: Search.Connection,
            logger: any LoggingModels.Logging.Recording,
            indexers: [String: any Search.SourceIndexer],
            sourceLookup: Search.SourceLookup
        ) {
            self.connection = connection
            self.logger = logger
            self.indexers = indexers
            self.sourceLookup = sourceLookup
        }

        public init(
            dbPath: URL,
            logger: any LoggingModels.Logging.Recording,
            indexers: [String: any Search.SourceIndexer],
            sourceLookup: Search.SourceLookup,
            readOnly: Bool = false
        ) async throws {
            let connection = Search.Connection(dbPath: dbPath, logger: logger, readOnly: readOnly)
            try connection.connect()

            self.init(
                connection: connection,
                logger: logger,
                indexers: indexers,
                sourceLookup: sourceLookup
            )

            if !readOnly {
                let indexer = Search.Indexer(
                    connection: connection,
                    logger: logger,
                    indexers: indexers,
                    sourceLookup: sourceLookup
                )
                try await indexer.checkAndMigrateSchema()
                try await indexer.createTables()
                try await indexer.setSchemaVersion()
            } else {
                let currentVersion = getSchemaVersion()
                if currentVersion != Self.schemaVersion {
                    throw Search.Error.schemaVersionMismatch(
                        currentDBVersion: Int(currentVersion),
                        expectedBinaryVersion: Int(Self.schemaVersion),
                        dbPath: dbPath.path
                    )
                }
            }
        }

        // Note: deinit cannot access actor-isolated properties
        // SQLite connections will be closed when the process terminates
        // For explicit cleanup, call disconnect() before deallocation

        /// Close the database connection explicitly
        public func disconnect() {
            connection.disconnect()
        }

        /// Inspect `PRAGMA synchronous` on the actor's own connection
        /// (returns 0..3, matching SQLite's enum: 0=OFF, 1=NORMAL,
        /// 2=FULL, 3=EXTRA). The setting is per-connection and not
        /// persistent in the file header, so this is the only honest
        /// way to assert what the writer is actually using —
        /// `Diagnostics.Probes` opens its own connection and would
        /// see SQLite's defaults instead. Test-facing.
        public func currentSynchronousMode() -> Int32? {
            readIntegerPragma("PRAGMA synchronous;")
        }

        /// Inspect `PRAGMA journal_size_limit` on the actor's own
        /// connection (bytes, or -1 for unlimited). Same per-connection
        /// caveat as `currentSynchronousMode`.
        public func currentJournalSizeLimit() -> Int64? {
            guard let database else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, "PRAGMA journal_size_limit;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int64(stmt, 0)
        }

        private func readIntegerPragma(_ pragma: String) -> Int32? {
            guard let database else { return nil }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(database, pragma, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW
            else {
                return nil
            }
            return sqlite3_column_int(stmt, 0)
        }

        func getSchemaVersion() -> Int32 {
            guard let database else { return 0 }

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                return 0
            }

            return sqlite3_column_int(statement, 0)
        }

        // MARK: - Database Setup
    }
}
