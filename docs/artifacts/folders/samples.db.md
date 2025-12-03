# samples.db - FTS5 Sample Code Search Database

SQLite database with Full-Text Search (FTS5) index for fast sample code searches.

## Location

**Default**: `~/.cupertino/samples.db`

## Created By

```bash
cupertino index
```

**Important**: Run `cupertino cleanup` before indexing to remove unnecessary files from sample code archives.

## Purpose

- **Code-Level Search** - Search across project files, not just metadata
- **Project Discovery** - Find sample code by topic or framework
- **README Search** - Full-text search through project documentation
- **File-Level Access** - Search and retrieve individual source files
- **MCP Integration** - Power AI sample code discovery

## Database Structure

SQLite database with two FTS5 virtual tables:

### Projects Table
```sql
CREATE VIRTUAL TABLE projects_fts USING fts5(
    id,              -- Project slug (e.g., "adopting-common-protocols")
    title,           -- Project title
    description,     -- Project description
    frameworks,      -- Space-separated frameworks
    readme,          -- Full README content
    tokenize = 'porter unicode61'
);
```

### Files Table
```sql
CREATE VIRTUAL TABLE files_fts USING fts5(
    project_id,      -- Parent project ID
    path,            -- File path (e.g., "Sources/Views/ContentView.swift")
    filename,        -- File name (e.g., "ContentView.swift")
    folder,          -- Folder path (e.g., "Sources/Views")
    content,         -- Full file content
    tokenize = 'porter unicode61'
);
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

The MCP server provides sample code search tools:
- `search_samples` - Search projects and code
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
cupertino index --clear

# Force reindex all projects (even if already indexed)
cupertino index --force
```

## Customizing Location

```bash
# Use custom database path
cupertino index --database ./my-samples.db

# Use custom sample code directory
cupertino index --sample-code-dir ~/my-samples
```

## Technical Details

- **Engine**: SQLite FTS5
- **Tokenizer**: Porter stemming + Unicode61
- **Format**: Standard SQLite database file
- **Compatibility**: Any SQLite 3.9.0+ client
- **Performance**: Optimized for code search queries

## Used By

- `cupertino serve` - MCP server for AI integration
- MCP tools: `search_samples`, `list_samples`, `read_sample`, `read_sample_file`
- Direct SQL queries
- Custom search applications

## Notes

- Separate from `search.db` (documentation index)
- Run `cupertino cleanup` first to reduce archive size and improve index quality
- Incremental indexing: only new projects indexed by default
- Thread-safe for concurrent reads
