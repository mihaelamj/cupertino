# samples.db - FTS5 Sample Code Search Database

SQLite database with Full-Text Search (FTS5) index for fast sample code searches.

## Location

**Default**: `~/.cupertino/samples.db`

When `cupertino save --samples` or any reader is connected, two sidecar files appear next to the main file:

- `samples.db-wal` — write-ahead log (#236; lets readers and writers proceed concurrently).
- `samples.db-shm` — shared-memory index for the WAL.

Copy all three together, or run `PRAGMA wal_checkpoint(TRUNCATE)` first to fold the WAL into the main file before the copy. Release bundles are always checkpoint-truncated before zipping.

## Created By

```bash
cupertino save --samples
```

**Important**: Run `cupertino cleanup` before indexing to remove unnecessary files from sample code archives.

## Purpose

- **Code-Level Search** - Search across project files, not just metadata
- **Project Discovery** - Find sample code by topic or framework
- **README Search** - Full-text search through project documentation
- **File-Level Access** - Search and retrieve individual source files
- **MCP Integration** - Power AI sample code discovery

## Database Structure

SQLite database with regular `projects` and `files` tables plus paired FTS5 mirrors. Schema version `3` (#228 phase 2 — added per-sample availability columns).

### `projects` table

```sql
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    frameworks TEXT NOT NULL,
    readme TEXT,
    web_url TEXT NOT NULL,
    zip_filename TEXT NOT NULL,
    file_count INTEGER NOT NULL,
    total_size INTEGER NOT NULL,
    indexed_at INTEGER NOT NULL,
    -- Availability (#228 phase 2). Populated from each sample's
    -- Package.swift platforms block when present (Apple's Xcode-project
    -- samples typically leave these NULL).
    min_ios TEXT,
    min_macos TEXT,
    min_tvos TEXT,
    min_watchos TEXT,
    min_visionos TEXT,
    availability_source TEXT  -- "sample-swift" when populated
);
```

### `projects_fts` (FTS5)

```sql
CREATE VIRTUAL TABLE projects_fts USING fts5(
    id, title, description, readme, frameworks,
    tokenize='porter unicode61'
);
```

### `files` table

```sql
CREATE TABLE files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id TEXT NOT NULL,
    path TEXT NOT NULL,
    filename TEXT NOT NULL,
    folder TEXT NOT NULL,
    extension TEXT NOT NULL,
    content TEXT NOT NULL,
    size INTEGER NOT NULL,
    -- Per-file @available(...) occurrences as JSON (#228 phase 2).
    -- Array of {line, raw, platforms[]}. NULL when the file had no
    -- attributes — distinct from "annotation never ran".
    available_attrs_json TEXT,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    UNIQUE(project_id, path)
);
```

### `files_fts` (FTS5)

```sql
CREATE VIRTUAL TABLE files_fts USING fts5(
    project_id, path, filename, content,
    tokenize='unicode61'
);
```

### `file_symbols` table — AST-extracted symbols (#81)

```sql
CREATE TABLE file_symbols (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL,               -- FK → files.id
    name TEXT NOT NULL,                     -- symbol name (e.g. "ContentView", "withTaskGroup")
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
    FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE INDEX idx_file_symbols_file   ON file_symbols(file_id);
CREATE INDEX idx_file_symbols_kind   ON file_symbols(kind);
CREATE INDEX idx_file_symbols_name   ON file_symbols(name);
CREATE INDEX idx_file_symbols_async  ON file_symbols(is_async);
```

Populated by SwiftSyntax during `cupertino save --samples`. Schema mirrors `doc_symbols` in `search.db` (same column shapes; different parent FK — `file_id` here vs `doc_uri` there).

### `file_symbols_fts` (FTS5)

```sql
CREATE VIRTUAL TABLE file_symbols_fts USING fts5(
    name,
    signature,
    attributes,
    conformances,
    tokenize='unicode61'
);
```

`unicode61` (no Porter stemming) preserves identifier exactness.

### `file_imports` table

```sql
CREATE TABLE file_imports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL,               -- FK → files.id
    module_name TEXT NOT NULL,              -- "SwiftUI", "Combine", ...
    line INTEGER NOT NULL,
    is_exported INTEGER NOT NULL DEFAULT 0, -- @_exported import
    FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE INDEX idx_file_imports_file    ON file_imports(file_id);
CREATE INDEX idx_file_imports_module  ON file_imports(module_name);
```

## Indexed Content

### Projects
- **id** - Unique identifier (from ZIP filename)
- **title** - Human-readable project title
- **description** - Project description from catalog
- **frameworks** - Frameworks used (e.g., "swiftui combine")
- **readme** - Full README.md content
- **webURL** - Apple Developer website URL
- **fileCount** - Number of source files
- **totalSize** - Total size of indexed files

### Files
- **projectId** - Parent project reference
- **path** - Relative path within project
- **filename** - File name only
- **folder** - Parent folder path
- **content** - Full file content
- **fileExtension** - File type (swift, m, h, etc.)

## Indexed File Types

| Extension | Type |
|-----------|------|
| `.swift` | Swift |
| `.h`, `.m`, `.mm` | Objective-C |
| `.c`, `.cpp`, `.hpp` | C/C++ |
| `.metal` | Metal Shaders |
| `.plist`, `.json`, `.strings` | Configuration |
| `.entitlements`, `.xcconfig` | Xcode Config |
| `.md`, `.txt` | Documentation |
| `.storyboard`, `.xib` | Interface Builder |

## Size

Varies based on number of sample code projects:

| Sample Projects | Index Size |
|----------------|------------|
| 100 projects | ~20-30 MB |
| 300 projects | ~60-100 MB |
| 600+ projects | ~150-250 MB |

## Usage

### Query with SQL
```bash
# Search projects for "SwiftUI"
sqlite3 ~/.cupertino/samples.db "SELECT title FROM projects WHERE projects MATCH 'swiftui' LIMIT 10"

# Search files for "async await"
sqlite3 ~/.cupertino/samples.db "SELECT project_id, path FROM files WHERE files MATCH 'async await' LIMIT 10"

# Search by framework
sqlite3 ~/.cupertino/samples.db "SELECT title FROM projects WHERE frameworks LIKE '%combine%'"
```

### Use with MCP
```bash
# Start MCP server (uses samples.db automatically)
cupertino serve
```

The MCP server provides sample-code-related tools:
- `search` (with `source: samples`) - Search projects and code; the pre-#239 standalone `search_samples` tool was collapsed into the unified `search`
- `list_samples` - List all indexed projects
- `read_sample` - Read project README
- `read_sample_file` - Read specific source file

## Search Features

### Full-Text Search
- Searches across project metadata and file content
- Supports phrase queries: `"exact phrase"`
- Boolean operators: `term1 AND term2`
- Prefix search: `async*`

### BM25 Ranking
- Relevance-based result ordering
- Better results for code-specific searches

### Multi-Table Search
- Search projects for metadata
- Search files for code content
- Join results for comprehensive discovery

## Rebuilding Index

```bash
# Clear and rebuild from scratch
cupertino save --samples --clear

# Force reindex all projects (even if already indexed)
cupertino save --samples --force
```

## Customizing Location

```bash
# Use custom database path
cupertino save --samples --samples-db ./my-samples.db

# Use custom sample code directory
cupertino save --samples --samples-dir ~/my-samples
```

## Technical Details

- **Engine**: SQLite FTS5
- **Tokenizer**: Porter stemming + Unicode61
- **Format**: Standard SQLite database file
- **Compatibility**: Any SQLite 3.9.0+ client
- **Performance**: Optimized for code search queries

## Used By

- `cupertino serve` - MCP server for AI integration
- MCP tools: `search` (with `source: samples`), `list_samples`, `read_sample`, `read_sample_file`
- Direct SQL queries
- Custom search applications

## Notes

- Separate from `search.db` (documentation index)
- Run `cupertino cleanup` first to reduce archive size and improve index quality
- Incremental indexing: only new projects indexed by default
- Thread-safe for concurrent reads
