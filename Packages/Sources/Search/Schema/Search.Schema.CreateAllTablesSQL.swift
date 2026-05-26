import Foundation
import SearchModels

// MARK: - Search.Schema.createAllTablesSQL

public extension Search.Schema {
    /// Single DDL script that creates every table, view, FTS5 virtual
    /// table, and index in the canonical `search.db` schema. Used by
    /// `Search.Index.createTables()` (in the `Search` target) on a
    /// fresh database, and indirectly by the migration pipeline when
    /// it needs to recreate the schema.
    ///
    /// Idempotent: every `CREATE` is `IF NOT EXISTS`. Safe to re-run
    /// against a database whose schema is already up to date.
    ///
    /// Lifted from `Search/Search.Index.Schema.swift` (where it was an
    /// inline `let sql = """..."""` inside `createTables()`) to
    /// `SearchSchema` by epic #893's child #898 sub-PR A. The executor
    /// (`createTables()` itself) stays in the `Search` target because
    /// it needs access to the `Search.Index` actor's internal `database`
    /// stored property and `sqlite3_exec`.
    ///
    /// ## Schema overview
    ///
    /// - `docs_fts` (FTS5): full-text search over per-page content
    /// - `docs_metadata`: per-URI metadata, including platform-min columns
    /// - `docs_structured`: extracted JSON fields for structured querying
    /// - `framework_aliases`: identifier / import-name / display-name mapping
    /// - `sample_code_fts` + `sample_code_metadata`: Apple sample-code search + lookup
    /// - `doc_code_examples` + `doc_code_fts`: embedded code-block index
    /// - `doc_symbols` + `doc_symbols_fts`: SwiftSyntax-AST-derived symbol index (#81)
    /// - `doc_imports`: import-statement index (#81)
    /// - `inheritance`: class-inheritance edges (#274)
    static let createAllTablesSQL: String = """
    CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
        uri,
        source,
        framework,
        language,
        title,
        content,
        summary,
        symbols,            -- #192 D: AST-extracted Swift symbol names; enables bm25 boost for type-name queries
        symbol_components,  -- #77:  acronym-aware CamelCase splits of `symbols` (LazyVGrid → Lazy / VGrid / Grid); BM25F weight 1.5 vs symbols' 5.0
        tokenize='porter unicode61'
    );

    CREATE TABLE IF NOT EXISTS docs_metadata (
        uri TEXT PRIMARY KEY,
        source TEXT NOT NULL DEFAULT 'apple-docs',
        framework TEXT NOT NULL,
        language TEXT NOT NULL DEFAULT 'swift',
        kind TEXT NOT NULL DEFAULT 'unknown',   -- #192 C1 taxonomy
        symbols TEXT,                            -- #192 D denormalized symbol names
        file_path TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        last_crawled INTEGER NOT NULL,
        word_count INTEGER NOT NULL,
        source_type TEXT DEFAULT 'apple',
        package_id INTEGER,
        json_data TEXT,
        -- Availability columns for efficient filtering (no JSON parsing needed)
        min_ios TEXT,           -- e.g., "13.0"
        min_macos TEXT,         -- e.g., "10.15"
        min_tvos TEXT,
        min_watchos TEXT,
        min_visionos TEXT,
        availability_source TEXT, -- 'api', 'parsed', 'inherited', 'derived'
        -- #225 Part B: Swift toolchain version a swift-evolution proposal
        -- landed in; NULL on non-evolution rows and on evolution rows whose
        -- markdown the parser couldn't read a version from.
        implementation_swift_version TEXT
        -- #789: removed FOREIGN KEY (package_id) REFERENCES packages(id)
        -- along with the dropped `packages` table. `package_id` column
        -- preserved on docs_metadata for back-compat; always NULL post-#789.
    );

    CREATE INDEX IF NOT EXISTS idx_source ON docs_metadata(source);
    CREATE INDEX IF NOT EXISTS idx_framework ON docs_metadata(framework);
    CREATE INDEX IF NOT EXISTS idx_language ON docs_metadata(language);
    CREATE INDEX IF NOT EXISTS idx_kind ON docs_metadata(kind);
    CREATE INDEX IF NOT EXISTS idx_source_type ON docs_metadata(source_type);
    CREATE INDEX IF NOT EXISTS idx_min_ios ON docs_metadata(min_ios);
    CREATE INDEX IF NOT EXISTS idx_min_macos ON docs_metadata(min_macos);
    CREATE INDEX IF NOT EXISTS idx_min_tvos ON docs_metadata(min_tvos);
    CREATE INDEX IF NOT EXISTS idx_min_watchos ON docs_metadata(min_watchos);
    CREATE INDEX IF NOT EXISTS idx_min_visionos ON docs_metadata(min_visionos);
    CREATE INDEX IF NOT EXISTS idx_implementation_swift_version ON docs_metadata(implementation_swift_version);

    -- Structured documentation fields (extracted from JSON for querying)
    CREATE TABLE IF NOT EXISTS docs_structured (
        uri TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        kind TEXT,
        abstract TEXT,
        declaration TEXT,
        overview TEXT,
        module TEXT,
        platforms TEXT,
        conforms_to TEXT,
        inherited_by TEXT,
        conforming_types TEXT,
        attributes TEXT,  -- @MainActor, @Sendable, @available, etc. (comma-separated)
        FOREIGN KEY (uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_docs_kind ON docs_structured(kind);
    CREATE INDEX IF NOT EXISTS idx_docs_module ON docs_structured(module);
    CREATE INDEX IF NOT EXISTS idx_docs_attributes ON docs_structured(attributes);

    -- Framework aliases: maps identifier, import name, and display name
    -- identifier: appintents (lowercase, URL path, folder name)
    -- import_name: AppIntents (CamelCase, Swift import statement)
    -- display_name: App Intents (human-readable, from JSON module field)
    -- synonyms: comma-separated alternate names (e.g., "nfc" for corenfc)
    CREATE TABLE IF NOT EXISTS framework_aliases (
        identifier TEXT PRIMARY KEY,
        import_name TEXT NOT NULL,
        display_name TEXT NOT NULL,
        synonyms TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_alias_import ON framework_aliases(import_name);
    CREATE INDEX IF NOT EXISTS idx_alias_display ON framework_aliases(display_name);

    -- #789: `packages` + `package_dependencies` tables removed from
    -- search.db. The canonical packages store is `packages.db`
    -- (built by `cupertino save --source packages`, queried by
    -- `cupertino package-search`). DROP-on-upgrade lives in
    -- Search.Index.Migrations migrateToVersion18.

    CREATE VIRTUAL TABLE IF NOT EXISTS sample_code_fts USING fts5(
        url,
        framework,
        title,
        description,
        tokenize='porter unicode61'
    );

    CREATE TABLE IF NOT EXISTS sample_code_metadata (
        url TEXT PRIMARY KEY,
        framework TEXT NOT NULL,
        zip_filename TEXT NOT NULL,
        web_url TEXT NOT NULL,
        last_indexed INTEGER,
        -- Availability columns (derived from framework)
        min_ios TEXT,
        min_macos TEXT,
        min_tvos TEXT,
        min_watchos TEXT,
        min_visionos TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_sample_framework ON sample_code_metadata(framework);
    CREATE INDEX IF NOT EXISTS idx_sample_min_ios ON sample_code_metadata(min_ios);
    CREATE INDEX IF NOT EXISTS idx_sample_min_macos ON sample_code_metadata(min_macos);
    CREATE INDEX IF NOT EXISTS idx_sample_min_tvos ON sample_code_metadata(min_tvos);
    CREATE INDEX IF NOT EXISTS idx_sample_min_watchos ON sample_code_metadata(min_watchos);
    CREATE INDEX IF NOT EXISTS idx_sample_min_visionos ON sample_code_metadata(min_visionos);

    -- Code examples embedded in documentation pages
    CREATE TABLE IF NOT EXISTS doc_code_examples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_uri TEXT NOT NULL,
        code TEXT NOT NULL,
        language TEXT DEFAULT 'swift',
        position INTEGER DEFAULT 0,
        FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri)
    );

    CREATE INDEX IF NOT EXISTS idx_code_doc_uri ON doc_code_examples(doc_uri);
    CREATE INDEX IF NOT EXISTS idx_code_language ON doc_code_examples(language);

    -- FTS for searching inside code examples
    CREATE VIRTUAL TABLE IF NOT EXISTS doc_code_fts USING fts5(
        code,
        tokenize='unicode61'
    );

    -- Symbols extracted from Swift code via SwiftSyntax AST (#81)
    -- generic_params: type parameter names (`T`, `Element`).
    -- generic_constraints: constraint half of `T: Collection` form,
    --                      joined `,` across multiple params, plus
    --                      where-clause constraints harvested from
    --                      the signature column at index time (#755).
    CREATE TABLE IF NOT EXISTS doc_symbols (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_uri TEXT NOT NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        line INTEGER NOT NULL,
        column INTEGER NOT NULL,
        signature TEXT,
        is_async INTEGER NOT NULL DEFAULT 0,
        is_throws INTEGER NOT NULL DEFAULT 0,
        is_public INTEGER NOT NULL DEFAULT 0,
        is_static INTEGER NOT NULL DEFAULT 0,
        attributes TEXT,
        conformances TEXT,
        generic_params TEXT,
        generic_constraints TEXT,
        FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_doc_symbols_uri ON doc_symbols(doc_uri);
    CREATE INDEX IF NOT EXISTS idx_doc_symbols_kind ON doc_symbols(kind);
    CREATE INDEX IF NOT EXISTS idx_doc_symbols_name ON doc_symbols(name);
    CREATE INDEX IF NOT EXISTS idx_doc_symbols_async ON doc_symbols(is_async);
    CREATE INDEX IF NOT EXISTS idx_doc_symbols_generic_constraints ON doc_symbols(generic_constraints);

    -- FTS for symbol name search
    CREATE VIRTUAL TABLE IF NOT EXISTS doc_symbols_fts USING fts5(
        name,
        signature,
        attributes,
        conformances,
        tokenize='unicode61'
    );

    -- Imports extracted from code examples (#81)
    CREATE TABLE IF NOT EXISTS doc_imports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_uri TEXT NOT NULL,
        module_name TEXT NOT NULL,
        line INTEGER NOT NULL,
        is_exported INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_doc_imports_uri ON doc_imports(doc_uri);
    CREATE INDEX IF NOT EXISTS idx_doc_imports_module ON doc_imports(module_name);

    -- #274: class-inheritance edges. One row per parent→child link,
    -- extracted from Apple's DocC `relationshipsSections.inheritsFrom`
    -- and `inheritedBy` arrays at index time. Both walk directions
    -- are indexed so `WHERE child_uri = ?` (walk-up to ancestors) and
    -- `WHERE parent_uri = ?` (walk-down to descendants) are equally
    -- fast on the 280k-row apple-docs corpus.
    --
    -- Schema choice rationale: a dedicated edge table (vs a JSON
    -- column on docs_metadata) because a single class can have
    -- thousands of descendants (`NSObject`, `UIView`, etc.) and a
    -- JSON-blob column would be both unscanable and bloated. The
    -- composite primary key prevents duplicate edges if the same
    -- (parent, child) pair appears in both `inheritsFrom` (from
    -- the child's page) and `inheritedBy` (from the parent's page).
    CREATE TABLE IF NOT EXISTS inheritance (
        parent_uri TEXT NOT NULL,
        child_uri  TEXT NOT NULL,
        PRIMARY KEY (parent_uri, child_uri)
    );

    CREATE INDEX IF NOT EXISTS inheritance_by_parent ON inheritance (parent_uri);
    CREATE INDEX IF NOT EXISTS inheritance_by_child  ON inheritance (child_uri);
    """
}
