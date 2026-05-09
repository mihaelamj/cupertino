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

### Main FTS5 Table

```sql
CREATE VIRTUAL TABLE docs_fts USING fts5(
    uri,        -- Unique identifier (e.g., apple-docs://swiftui/View)
    source,     -- Source type (apple-docs, swift-evolution, hig, etc.)
    framework,  -- Framework or category (swiftui, foundation, components)
    language,   -- Programming language (swift, objc)
    title,      -- Page title
    content,    -- Full page content (searchable)
    summary,    -- First paragraph or description
    symbols,    -- AST-extracted Swift symbol names (schema v12, #192 section D)
    tokenize='porter unicode61'
);
```

BM25 weights are passed per-column at query time, not stamped into the FTS
schema. The main docs-search call uses
`bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0)` — `title` 10×,
`symbols` 5×, `summary` 3×, `framework` 2×, everything else 1× (#181).
See `SearchIndex.swift` query builder.

### Metadata Table

```sql
CREATE TABLE docs_metadata (
    uri TEXT PRIMARY KEY,
    source TEXT NOT NULL DEFAULT 'apple-docs',
    framework TEXT NOT NULL,
    language TEXT NOT NULL DEFAULT 'swift',
    kind TEXT NOT NULL DEFAULT 'unknown',  -- #192 C1 taxonomy
    symbols TEXT,                           -- #192 D: denormalized symbol names for bm25
    file_path TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    last_crawled INTEGER NOT NULL,
    word_count INTEGER NOT NULL,
    source_type TEXT DEFAULT 'apple',
    package_id INTEGER,
    json_data TEXT,
    -- Availability columns (min_ios, min_macos, ...) omitted for brevity
);
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

The MCP server provides `search_docs` and `search_hig` tools to AI assistants.

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
