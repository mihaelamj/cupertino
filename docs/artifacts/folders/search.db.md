# search.db - FTS5 Search Index Database

SQLite database with Full-Text Search (FTS5) index for fast documentation searches.

## Location

**Default**: `~/.cupertino/search.db`

## Created By

```bash
cupertino save
```

## Purpose

- **Fast Full-Text Search** - Sub-second queries across thousands of pages
- **BM25 Ranking** - Relevance-based result ordering
- **Source Filtering** - Search within specific documentation sources
- **Framework Filtering** - Search within specific frameworks
- **Snippet Generation** - Show matching context
- **MCP Integration** - Power AI documentation search

## Database Schema

Schema version `13` (per `PRAGMA user_version`). The version constant `Search.Index.schemaVersion` lives in [`Packages/Sources/Search/SearchIndex.swift`](../../../Packages/Sources/Search/SearchIndex.swift); `createTables` lives in [`SearchIndex+Schema.swift`](../../../Packages/Sources/Search/SearchIndex+Schema.swift); migrations (`migrateToVersion3..11`) live in [`SearchIndex+Migrations.swift`](../../../Packages/Sources/Search/SearchIndex+Migrations.swift). Migrations are incremental — fresh DBs created by `cupertino save` write directly at v12; older DBs run `ALTER TABLE` migrations on open.

`search.db` holds **13 tables** grouped by purpose:

| Group | Tables |
|---|---|
| Documentation FTS | `docs_fts`, `docs_metadata`, `docs_structured`, `framework_aliases` |
| Cross-reference targets | `packages`, `package_dependencies` |
| Apple sample-code crawl | `sample_code_fts`, `sample_code_metadata` |
| Code examples extracted from docs | `doc_code_examples`, `doc_code_fts` |
| AST-extracted symbols (#81) | `doc_symbols`, `doc_symbols_fts`, `doc_imports` |

Every table is named with the prefix that signals its purpose (`docs_`, `package_`, `sample_code_`, `doc_code_`, `doc_symbols_`, `doc_imports`). FTS5 virtual tables use the same root name with `_fts` suffix and pair with a regular relational table.

### `docs_fts` — primary documentation FTS5 index

```sql
CREATE VIRTUAL TABLE docs_fts USING fts5(
    uri,        -- Unique identifier (e.g., apple-docs://swiftui/View)
    source,     -- Source type (apple-docs, swift-evolution, hig, etc.)
    framework,  -- Framework or category (swiftui, foundation, components)
    language,   -- Programming language (swift, objc)
    title,      -- Page title
    content,    -- Full page content (searchable)
    summary,    -- First paragraph or description
    symbols,    -- AST-extracted Swift symbol names (added in schema v12, #192 D)
    tokenize='porter unicode61'
);
```

BM25 weights are passed per-column at query time, not stamped into the FTS schema. The main docs-search call uses `bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0)` — `title` 10×, `symbols` 5×, `summary` 3×, `framework` 2×, everything else 1× (#181). Heuristic boosts on top (exact title match 50× / 20×, framework-authority tiebreak, force-include canonical type pages) live in [`SearchIndex+Search.swift`](../../../Packages/Sources/Search/SearchIndex+Search.swift) — the multi-pass `search()` function and its supporting `fetchCanonicalTypePages` / `fetchFrameworkRoot` / `fetchMatchingSymbols` helpers.

### `docs_metadata` — per-document relational mirror

```sql
CREATE TABLE docs_metadata (
    uri TEXT PRIMARY KEY,
    source TEXT NOT NULL DEFAULT 'apple-docs',
    framework TEXT NOT NULL,
    language TEXT NOT NULL DEFAULT 'swift',
    kind TEXT NOT NULL DEFAULT 'unknown',   -- #192 C1 taxonomy (see Kind Taxonomy below)
    symbols TEXT,                           -- #192 D denormalized symbol names for BM25
    file_path TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    last_crawled INTEGER NOT NULL,
    word_count INTEGER NOT NULL,
    source_type TEXT DEFAULT 'apple',
    package_id INTEGER,                     -- FK → packages.id (cross-source link)
    json_data TEXT,                         -- Full StructuredDocumentationPage JSON
    -- Availability filtering (#220) — pre-extracted so cupertino-search
    -- doesn't have to JSON-parse json_data on every query.
    min_ios TEXT,                           -- e.g. "13.0"
    min_macos TEXT,                         -- e.g. "10.15"
    min_tvos TEXT,
    min_watchos TEXT,
    min_visionos TEXT,
    availability_source TEXT,               -- 'api' | 'parsed' | 'inherited' | 'derived'
    FOREIGN KEY (package_id) REFERENCES packages(id)
);

CREATE INDEX idx_source        ON docs_metadata(source);
CREATE INDEX idx_framework     ON docs_metadata(framework);
CREATE INDEX idx_language      ON docs_metadata(language);
CREATE INDEX idx_kind          ON docs_metadata(kind);
CREATE INDEX idx_source_type   ON docs_metadata(source_type);
CREATE INDEX idx_min_ios       ON docs_metadata(min_ios);
CREATE INDEX idx_min_macos     ON docs_metadata(min_macos);
CREATE INDEX idx_min_tvos      ON docs_metadata(min_tvos);
CREATE INDEX idx_min_watchos   ON docs_metadata(min_watchos);
CREATE INDEX idx_min_visionos  ON docs_metadata(min_visionos);
```

`uri` is the canonical key — every other docs table references it via FK. `json_data` carries the full saved `StructuredDocumentationPage` JSON; for fields that need querying (kind, framework, availability), the schema lifts them to dedicated columns rather than make every query parse JSON.

### `docs_structured` — extracted structured fields

```sql
CREATE TABLE docs_structured (
    uri TEXT PRIMARY KEY,                   -- FK → docs_metadata.uri
    url TEXT NOT NULL,
    title TEXT NOT NULL,
    kind TEXT,
    abstract TEXT,
    declaration TEXT,
    overview TEXT,
    module TEXT,
    platforms TEXT,
    conforms_to TEXT,                       -- comma-separated protocol names
    inherited_by TEXT,                      -- comma-separated subclass names
    conforming_types TEXT,                  -- comma-separated conformer names
    attributes TEXT,                        -- @MainActor, @Sendable, @available, ...
    FOREIGN KEY (uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
);

CREATE INDEX idx_docs_kind        ON docs_structured(kind);
CREATE INDEX idx_docs_module      ON docs_structured(module);
CREATE INDEX idx_docs_attributes  ON docs_structured(attributes);
```

Surfaces the `StructuredDocumentationPage` fields the JSON crawler populates so MCP / CLI queries can filter on relationship metadata without JSON parsing. The HTML crawler doesn't populate `conforms_to` / `inherited_by` / `conforming_types` / `platforms` / `module` (see the v1.0.x dual-corpus investigation note in `mihaela-blog-ideas/cupertino/research/`).

### `framework_aliases` — identifier ↔ import-name ↔ display-name

```sql
CREATE TABLE framework_aliases (
    identifier TEXT PRIMARY KEY,            -- "appintents" (lowercase, URL/folder name)
    import_name TEXT NOT NULL,              -- "AppIntents" (Swift import statement)
    display_name TEXT NOT NULL,             -- "App Intents" (human-readable, JSON module field)
    synonyms TEXT                           -- comma-separated alternates ("nfc" → "corenfc")
);

CREATE INDEX idx_alias_import    ON framework_aliases(import_name);
CREATE INDEX idx_alias_display   ON framework_aliases(display_name);
```

Used by smart-query (`SmartQuery`) to translate user input — "AppIntents", "App Intents", and "appintents" all resolve to the same framework filter.

### `packages` — Swift package metadata (cross-reference target)

```sql
CREATE TABLE packages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    owner TEXT NOT NULL,
    repository_url TEXT NOT NULL,
    documentation_url TEXT,
    stars INTEGER,
    last_updated INTEGER,
    is_apple_official INTEGER DEFAULT 0,    -- bool
    description TEXT,
    UNIQUE(owner, name)
);

CREATE INDEX idx_package_owner    ON packages(owner);
CREATE INDEX idx_package_official ON packages(is_apple_official);
```

This is the **cross-reference** packages table — used by `docs_metadata.package_id` to link a documentation page to its source package. The full per-file source-tree FTS lives separately in [`packages.db`](packages.db.md) under a different schema (`package_metadata`, `package_files`, `package_files_fts`).

### `package_dependencies` — declared inter-package edges

```sql
CREATE TABLE package_dependencies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    package_id INTEGER NOT NULL,                -- FK → packages.id
    depends_on_package_id INTEGER NOT NULL,     -- FK → packages.id
    version_requirement TEXT,                   -- SemVer constraint, e.g. ">=5.10.0"
    FOREIGN KEY (package_id) REFERENCES packages(id),
    FOREIGN KEY (depends_on_package_id) REFERENCES packages(id)
);

CREATE INDEX idx_pkg_dep_package  ON package_dependencies(package_id);
CREATE INDEX idx_pkg_dep_depends  ON package_dependencies(depends_on_package_id);
```

### `sample_code_fts` — Apple sample-code metadata FTS5

```sql
CREATE VIRTUAL TABLE sample_code_fts USING fts5(
    url,
    framework,
    title,
    description,
    tokenize='porter unicode61'
);
```

Matches the `sample_code_metadata` table 1:1. Holds **Apple sample-code listing pages** (the things that appear at `developer.apple.com/documentation/.../<sample-name>` with a downloadable ZIP), not the extracted source-file FTS — that one lives in [`samples.db`](samples.db.md) under a different schema.

### `sample_code_metadata` — Apple sample-code listings

```sql
CREATE TABLE sample_code_metadata (
    url TEXT PRIMARY KEY,
    framework TEXT NOT NULL,
    zip_filename TEXT NOT NULL,
    web_url TEXT NOT NULL,
    last_indexed INTEGER,
    -- Availability derived from the framework column
    min_ios TEXT,
    min_macos TEXT,
    min_tvos TEXT,
    min_watchos TEXT,
    min_visionos TEXT
);

CREATE INDEX idx_sample_framework      ON sample_code_metadata(framework);
CREATE INDEX idx_sample_min_ios        ON sample_code_metadata(min_ios);
CREATE INDEX idx_sample_min_macos      ON sample_code_metadata(min_macos);
CREATE INDEX idx_sample_min_tvos       ON sample_code_metadata(min_tvos);
CREATE INDEX idx_sample_min_watchos    ON sample_code_metadata(min_watchos);
CREATE INDEX idx_sample_min_visionos   ON sample_code_metadata(min_visionos);
```

### `doc_code_examples` — code blocks extracted from docs

```sql
CREATE TABLE doc_code_examples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    doc_uri TEXT NOT NULL,                  -- FK → docs_metadata.uri
    code TEXT NOT NULL,
    language TEXT DEFAULT 'swift',
    position INTEGER DEFAULT 0,             -- position within the doc (0-based)
    FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri)
);

CREATE INDEX idx_code_doc_uri    ON doc_code_examples(doc_uri);
CREATE INDEX idx_code_language   ON doc_code_examples(language);
```

### `doc_code_fts` — FTS5 over code-example bodies

```sql
CREATE VIRTUAL TABLE doc_code_fts USING fts5(
    code,
    tokenize='unicode61'
);
```

`unicode61` (no Porter stemming) is intentional — code identifiers shouldn't get stemmed (`hashed` and `hashable` are different symbols).

### `doc_symbols` — AST-extracted symbols (#81)

```sql
CREATE TABLE doc_symbols (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    doc_uri TEXT NOT NULL,                  -- FK → docs_metadata.uri
    name TEXT NOT NULL,                     -- "ObservableObject", "withTaskGroup", ...
    kind TEXT NOT NULL,                     -- "class" | "struct" | "actor" | "func" | ...
    line INTEGER NOT NULL,
    column INTEGER NOT NULL,
    signature TEXT,
    is_async INTEGER NOT NULL DEFAULT 0,
    is_throws INTEGER NOT NULL DEFAULT 0,
    is_public INTEGER NOT NULL DEFAULT 0,
    is_static INTEGER NOT NULL DEFAULT 0,
    attributes TEXT,                        -- comma-separated @MainActor, @Sendable, ...
    conformances TEXT,                      -- comma-separated protocol names
    generic_params TEXT,                    -- comma-separated generic constraints
    FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
);

CREATE INDEX idx_doc_symbols_uri    ON doc_symbols(doc_uri);
CREATE INDEX idx_doc_symbols_kind   ON doc_symbols(kind);
CREATE INDEX idx_doc_symbols_name   ON doc_symbols(name);
CREATE INDEX idx_doc_symbols_async  ON doc_symbols(is_async);
```

Populated from `cupertino save` running SwiftSyntax over each doc's code blocks. Backs the semantic-search MCP tools (`search_symbols`, `search_property_wrappers`, `search_concurrency`, `search_conformances`).

### `doc_symbols_fts` — FTS5 over symbol names + signatures

```sql
CREATE VIRTUAL TABLE doc_symbols_fts USING fts5(
    name,
    signature,
    attributes,
    conformances,
    tokenize='unicode61'
);
```

Used by the docs-search ranker (`SearchIndex+Search.swift`) to boost canonical Swift type pages — when a query exactly matches a symbol name with an indexed `kind`, the corresponding doc page gets a 3× post-rank boost. Pre-1.0 a sign error in the multiplier was demoting these instead; fixed in v1.0.0 (#254).

### `doc_imports` — `import` statements in code examples

```sql
CREATE TABLE doc_imports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    doc_uri TEXT NOT NULL,                  -- FK → docs_metadata.uri
    module_name TEXT NOT NULL,              -- "SwiftUI", "Combine", ...
    line INTEGER NOT NULL,
    is_exported INTEGER NOT NULL DEFAULT 0, -- @_exported import
    FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
);

CREATE INDEX idx_doc_imports_uri     ON doc_imports(doc_uri);
CREATE INDEX idx_doc_imports_module  ON doc_imports(module_name);
```

### Kind Taxonomy

Every row in `docs_metadata` carries a high-level `kind` value assigned at
index time by `Search.Classify.kind(source:structuredKind:uriPath:)`. Used by
the smart-query wrapper (#192 section E) to route per-intent.

| Kind                | What                              | Source branch                |
|---------------------|-----------------------------------|------------------------------|
| `symbolPage`        | API reference with a declaration  | `apple-docs` + decl kind     |
| `article`           | Discussion / overview prose       | `apple-docs` + article/coll. |
| `tutorial`          | DocC tutorial chapter             | `apple-docs` + tutorial      |
| `sampleCode`        | Apple sample-code landing page    | `apple-docs` + `/samplecode/` |
| `evolutionProposal` | Swift Evolution proposal          | `swift-evolution`            |
| `swiftBook`         | The Swift Programming Language    | `swift-book`                 |
| `swiftOrgDoc`       | Other Swift.org docs              | `swift-org`                  |
| `hig`               | Human Interface Guidelines        | `hig`                        |
| `archive`           | Legacy Apple Archive guide        | `apple-archive`              |
| `unknown`           | Fallback — classifier gap         | any                          |

Reserved for future sources (not yet produced): `wwdcTranscript` (#58),
`swiftForumsThread` (#89), `externalLibraryDoc` (#116). Adding a source
requires one new case in `DocKind` and one new branch in `Classify.kind(...)`.

### Tokenizer

- **`porter`** - Porter stemming algorithm (search "running" finds "run", "runs", "running")
- **`unicode61`** - Unicode-aware tokenization (handles international characters)

## Source Types

All 8 documentation sources are indexed into the same `docs_fts` table:

### 1. Apple Documentation (`apple-docs`)

| Field | Example |
|-------|---------|
| URI | `apple-docs://swiftui/View` |
| Source | `apple-docs` |
| Framework | `swiftui`, `foundation`, `uikit`, etc. |
| Path | `~/.cupertino/docs/{framework}/*.json` |

### 2. Swift Evolution (`swift-evolution`)

| Field | Example |
|-------|---------|
| URI | `swift-evolution://SE-0306` |
| Source | `swift-evolution` |
| Framework | `NULL` |
| Path | `~/.cupertino/swift-evolution/SE-*.md` |

### 3. Swift.org (`swift-org`)

| Field | Example |
|-------|---------|
| URI | `swift-org://concurrency` |
| Source | `swift-org` |
| Framework | `NULL` |
| Path | `~/.cupertino/swift-org/*.md` |

### 4. Swift Book (`swift-book`)

| Field | Example |
|-------|---------|
| URI | `swift-book://closures` |
| Source | `swift-book` |
| Framework | `NULL` |
| Path | `~/.cupertino/swift-org/swift-book/*.md` |

### 5. Apple Archive (`apple-archive`)

| Field | Example |
|-------|---------|
| URI | `apple-archive://TP40014097/about-views` |
| Source | `apple-archive` |
| Framework | From YAML front matter (e.g., `QuartzCore`) |
| Path | `~/.cupertino/archive/{guideUID}/*.md` |

### 6. Human Interface Guidelines (`hig`)

| Field | Example |
|-------|---------|
| URI | `hig://components/buttons` |
| Source | `hig` |
| Framework | Category (`foundations`, `patterns`, `components`, `inputs`, `technologies`) |
| Path | `~/.cupertino/hig/{category}/*.md` |

### 7. Sample Code (`apple-sample-code`)

| Field | Example |
|-------|---------|
| URI | `apple-sample-code://BuildingAGreatMacApp` |
| Source | `apple-sample-code` |
| Framework | `swiftui`, `uikit`, etc. |
| Path | Bundled in `swift-sample-code-catalog.json` |

### 8. Swift Packages (`packages`)

| Field | Example |
|-------|---------|
| URI | `packages://apple/swift-nio` |
| Source | `packages` |
| Framework | `NULL` |
| Path | Bundled in `swift-packages-catalog.json` |

## Size

Typically ~10-20% of source documentation size:

| Documentation Size | Index Size |
|-------------------|------------|
| 100 MB | ~15 MB |
| 500 MB | ~75 MB |
| 1 GB | ~150 MB |

## Usage

### CLI Search

```bash
# Search all sources
cupertino search "async"

# Search specific source
cupertino search "buttons" --source hig

# Search specific framework
cupertino search "View" --framework swiftui

# Combine filters
cupertino search "animation" --source apple-docs --framework swiftui
```

### Query with SQL

```bash
# Search for "async" across all sources
sqlite3 ~/.cupertino/search.db \
  "SELECT uri, title, source FROM docs_fts WHERE docs_fts MATCH 'async' LIMIT 10"

# Search within HIG only
sqlite3 ~/.cupertino/search.db \
  "SELECT uri, title FROM docs_fts WHERE docs_fts MATCH 'buttons' AND source = 'hig' LIMIT 10"

# Search SwiftUI framework
sqlite3 ~/.cupertino/search.db \
  "SELECT uri, title FROM docs_fts WHERE docs_fts MATCH 'view' AND framework = 'swiftui' LIMIT 10"

# Get snippets with highlighting
sqlite3 ~/.cupertino/search.db \
  "SELECT snippet(docs_fts, 5, '<b>', '</b>', '...', 32) FROM docs_fts WHERE docs_fts MATCH 'concurrency'"
```

### MCP Server

```bash
# Start MCP server (uses search.db automatically)
cupertino
```

The MCP server provides the unified `search` tool (with `source` filter), plus `list_frameworks`, `read_document`, and the four AST-powered semantic-search tools (`search_symbols`, `search_property_wrappers`, `search_concurrency`, `search_conformances`). The pre-#239 per-source tools (`search_docs`, `search_hig`, `search_samples`, `search_all`) were collapsed into the unified `search`.

## Search Features

### Full-Text Search
- Searches across title, content, and summary
- Supports phrase queries: `"exact phrase"`
- Boolean operators: `term1 AND term2`, `term1 OR term2`
- Prefix search: `asyn*` matches "async", "asynchronous"

### Porter Stemming
- `running` matches `run`, `runs`, `running`, `ran`
- `documentation` matches `document`, `docs`
- Improves recall without exact matching

### BM25 Ranking
- Relevance-based result ordering
- Term frequency and inverse document frequency
- Source-based boosting (apple-docs ranked higher)

### Source Filtering
```sql
-- Only HIG results
WHERE source = 'hig'

-- Multiple sources
WHERE source IN ('apple-docs', 'hig')

-- Exclude packages
WHERE source != 'packages'
```

### Framework Filtering
```sql
-- Only SwiftUI results
WHERE framework = 'swiftui'

-- Multiple frameworks
WHERE framework IN ('swift', 'foundation')
```

## Rebuilding Index

```bash
# Clear and rebuild from scratch (recommended)
cupertino save --clear

# Rebuild with specific directories
cupertino save --docs-dir ~/my-docs --evolution-dir ~/proposals
```

## Customizing Location

```bash
# Use custom database path
cupertino save --search-db ./my-search.db

# Search with custom database
cupertino search "query" --search-db ./my-search.db
```

## Technical Details

- **Engine**: SQLite FTS5
- **Tokenizer**: Porter stemming + Unicode61
- **Format**: Standard SQLite database file
- **Compatibility**: Any SQLite 3.9.0+ client
- **Performance**: Sub-100ms queries on 50k+ documents
- **Thread Safety**: Safe for concurrent reads

## Notes

- Standard SQLite file - can be queried with any SQLite tool
- FTS5 provides production-grade full-text search
- Rebuilding is fast (~2-5 minutes for full documentation)
- Can be backed up like any SQLite database
- Delete and run `cupertino save` to rebuild from scratch
