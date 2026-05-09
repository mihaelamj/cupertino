import Foundation
import Shared
import SQLite3

// swiftlint:disable type_body_length function_body_length
// Justification: extracted from SearchIndex.swift; the original 4598-line
// file's class_body_length / function_body_length / function_parameter_count
// rationale carries forward to the per-concern slices.

extension Search.Index {
    func createTables() async throws {
        guard let database else {
            throw SearchError.databaseNotInitialized
        }

        // FTS5 virtual table for full-text search
        // source: high-level category (apple-docs, swift-evolution, swift-org, swift-book)
        // framework: specific framework (swiftui, foundation, etc.) - same as source for non-apple-docs
        // language: programming language (swift, objc) - extracted from Apple's interfaceLanguage
        let sql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
            uri,
            source,
            framework,
            language,
            title,
            content,
            summary,
            symbols,            -- #192 D: AST-extracted Swift symbol names; enables bm25 boost for type-name queries
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
            FOREIGN KEY (package_id) REFERENCES packages(id)
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

        CREATE TABLE IF NOT EXISTS packages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            owner TEXT NOT NULL,
            repository_url TEXT NOT NULL,
            documentation_url TEXT,
            stars INTEGER,
            last_updated INTEGER,
            is_apple_official INTEGER DEFAULT 0,
            description TEXT,
            UNIQUE(owner, name)
        );

        CREATE INDEX IF NOT EXISTS idx_package_owner ON packages(owner);
        CREATE INDEX IF NOT EXISTS idx_package_official ON packages(is_apple_official);

        CREATE TABLE IF NOT EXISTS package_dependencies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            package_id INTEGER NOT NULL,
            depends_on_package_id INTEGER NOT NULL,
            version_requirement TEXT,
            FOREIGN KEY (package_id) REFERENCES packages(id),
            FOREIGN KEY (depends_on_package_id) REFERENCES packages(id),
            UNIQUE(package_id, depends_on_package_id)
        );

        CREATE INDEX IF NOT EXISTS idx_pkg_dep_package ON package_dependencies(package_id);
        CREATE INDEX IF NOT EXISTS idx_pkg_dep_depends ON package_dependencies(depends_on_package_id);

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
            FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_doc_symbols_uri ON doc_symbols(doc_uri);
        CREATE INDEX IF NOT EXISTS idx_doc_symbols_kind ON doc_symbols(kind);
        CREATE INDEX IF NOT EXISTS idx_doc_symbols_name ON doc_symbols(name);
        CREATE INDEX IF NOT EXISTS idx_doc_symbols_async ON doc_symbols(is_async);

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
        """

        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }

        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let errorMessage = errorPointer.map { String(cString: $0) } ?? "Unknown error"
            throw SearchError.sqliteError("Failed to create tables: \(errorMessage)")
        }
    }

    // MARK: - Package Indexing
}
