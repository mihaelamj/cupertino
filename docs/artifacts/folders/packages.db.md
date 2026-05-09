# packages.db - FTS5 Swift Package Search Database

SQLite database with Full-Text Search (FTS5) index for fast Swift package code searches. Bundled with `search.db` and `samples.db` in the `cupertino-databases-vX.zip` release artifact (since #246 / #259 — the v1.0 release simplification).

## Location

**Default**: `~/.cupertino/packages.db`

## Created By

```bash
cupertino save --packages
```

Builds the index from per-package source archives downloaded by `cupertino fetch --type packages` (which itself runs the Swift Package Index metadata refresh and the GitHub source-archive download stage). See [`fetch --type packages`](../../commands/fetch/) and [`save --packages`](../../commands/save/) for the full pipeline.

## Purpose

- **Code-Level Search** - Lexical FTS5 search across the source files of curated Swift packages
- **Symbol Search** - AST-extracted Swift symbol names enable type-name boost in BM25 ranking
- **Repo Discovery** - Find packages by topic, framework, or canonical repo name
- **MCP Integration** - Powers the unified `search` tool's `packages` source path
- **CLI Integration** - Backs `cupertino search --source packages` and the focused `cupertino package-search` command

## Database Schema

Schema version `2` (per `PRAGMA user_version`). Defined end-to-end in [`Packages/Sources/Search/PackageIndex.swift`](../../../Packages/Sources/Search/PackageIndex.swift); the version constant is `PackageIndex.schemaVersion`. Migrations are incremental — fresh DBs created by `cupertino save --packages` write directly at v2; older DBs run `ALTER TABLE` migrations on open.

`packages.db` holds **3 tables**:

| Table | Purpose |
|---|---|
| `package_metadata` | One row per indexed package. Canonical owner/repo, source-tarball stats, declared deployment targets (#219), Apple-official flag. |
| `package_files` | One row per indexed source file. FK → `package_metadata`. Carries kind, module, size, and per-file `@available` annotations (#219). |
| `package_files_fts` | FTS5 over file titles, content, and AST-extracted symbol names. UNINDEXED filter columns mirror `package_files` for direct projection without joins. |

### `package_metadata`

```sql
CREATE TABLE package_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner TEXT NOT NULL,                    -- "swiftlang", "pointfreeco", ...
    repo TEXT NOT NULL,                     -- "swift-collections", "swift-dependencies", ...
    url TEXT NOT NULL,                      -- canonical repository URL
    branch_used TEXT,                       -- the branch the source archive came from
    stars INTEGER,                          -- GitHub star count at fetch time
    is_apple_official INTEGER NOT NULL DEFAULT 0,
    tarball_bytes INTEGER,                  -- compressed download size
    total_bytes INTEGER,                    -- extracted source-tree size
    fetched_at INTEGER NOT NULL,            -- Unix epoch of source-archive fetch
    cupertino_version TEXT,                 -- cupertino binary version that did the fetch
    hosted_doc_url TEXT,                    -- canonical hosted DocC URL if available
    parents_json TEXT,                      -- transitive package dependency tree (JSON)
    -- Availability columns (#219, mirrors docs_metadata pattern in search.db)
    min_ios TEXT,
    min_macos TEXT,
    min_tvos TEXT,
    min_watchos TEXT,
    min_visionos TEXT,
    availability_source TEXT,               -- 'package-swift' | 'inferred' | NULL
    UNIQUE(owner, repo)
);

CREATE INDEX idx_pkg_owner          ON package_metadata(owner);
CREATE INDEX idx_pkg_apple          ON package_metadata(is_apple_official);
CREATE INDEX idx_pkg_min_ios        ON package_metadata(min_ios);
CREATE INDEX idx_pkg_min_macos      ON package_metadata(min_macos);
CREATE INDEX idx_pkg_min_tvos       ON package_metadata(min_tvos);
CREATE INDEX idx_pkg_min_watchos    ON package_metadata(min_watchos);
CREATE INDEX idx_pkg_min_visionos   ON package_metadata(min_visionos);
```

> **Naming note**: `package_metadata` here in `packages.db` is the **per-package source-tree metadata**. The `packages` table in `search.db` is a different, smaller cross-reference table used by `docs_metadata.package_id` to link docs pages to package identity. Both exist; they are not duplicates.

### `package_files`

```sql
CREATE TABLE package_files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    package_id INTEGER NOT NULL,            -- FK → package_metadata.id
    relpath TEXT NOT NULL,                  -- path relative to repo root
    kind TEXT NOT NULL,                     -- 'source' | 'readme' | 'manifest' | 'doc' | ...
    module TEXT,                            -- declared SwiftPM module the file belongs to
    size_bytes INTEGER NOT NULL,
    indexed_at INTEGER NOT NULL,            -- Unix epoch of last index pass
    -- Per-file @available occurrences (#219). JSON array of
    -- {line, raw, platforms[]}. NULL when the file had no @available
    -- attributes — distinct from "annotation never ran".
    available_attrs_json TEXT,
    FOREIGN KEY (package_id) REFERENCES package_metadata(id) ON DELETE CASCADE,
    UNIQUE(package_id, relpath)
);

CREATE INDEX idx_file_package    ON package_files(package_id);
CREATE INDEX idx_file_kind       ON package_files(kind);
CREATE INDEX idx_file_module     ON package_files(module);
```

### `package_files_fts`

```sql
CREATE VIRTUAL TABLE package_files_fts USING fts5(
    package_id UNINDEXED,                   -- FK → package_metadata.id
    owner      UNINDEXED,                   -- denormalized for filter-without-join
    repo       UNINDEXED,
    module     UNINDEXED,
    relpath    UNINDEXED,
    kind       UNINDEXED,
    title,                                  -- searchable: filename + module hints
    content,                                -- searchable: full file contents
    symbols,                                -- searchable: AST-extracted Swift symbol names
    tokenize='porter unicode61'
);
```

`UNINDEXED` columns are stored but excluded from FTS scoring; they're filter / projection columns the rank query uses without joining back to `package_files` (#256 follow-on). The three indexed columns (`title`, `content`, `symbols`) feed BM25.

## Ranking

`PackageQuery` runs BM25F over `package_files_fts` with per-column weights matching the docs index pattern. Title weighted highest, content modest, symbols boosted (#192 D + #256 follow-on). When a query token (or its dash-joined form) matches an indexed `repo` name exactly, the canonical repo's top BM25 file is force-included as a candidate so cross-source ranking doesn't bury obvious hits (the v1.0.0 fix for `vapor middleware` → vapor/vapor, `swift testing` → swiftlang/swift-testing, `swift dependencies` → pointfreeco/swift-dependencies).

## Rebuilding Index

```bash
# Clear and rebuild from scratch
cupertino save --packages --clear

# Force re-index every package even if already in the DB
cupertino save --packages --force
```

## Customizing Location

```bash
# Use custom database path
cupertino save --packages --packages-db ./my-packages.db

# Use custom packages directory (containing the per-package source trees)
cupertino save --packages --packages-dir ~/my-packages
```

## Technical Details

- **Engine**: SQLite FTS5
- **Tokenizer**: Porter stemming + Unicode61
- **Format**: Standard SQLite database file
- **Compatibility**: Any SQLite 3.9.0+ client
- **Size**: ~990 MB at v1.0.0 corpus state (~1,587 packages)

## Used By

- `cupertino serve` — MCP server, for the `search` tool's `packages` source path
- `cupertino search` — CLI, both default fan-out and `--source packages`
- `cupertino package-search` — focused single-source query against `packages.db` only
- `cupertino read --source packages` — fetches file content directly from `package_files_fts.content` (no on-disk packages tree required at read time)

## Notes

- Separate from `search.db` (documentation FTS) and `samples.db` (sample-code FTS)
- Index reads `~/.cupertino/packages/` source trees written by `cupertino fetch --type packages`
- Pre-#246 / pre-v1.0 the package metadata lived in a separate `cupertino-packages` GitHub repo with its own release zip; that companion repo was folded into `cupertino-docs` and the bundle is now single-zip
- Thread-safe for concurrent reads
- Uses the same dev-base override pattern as the docs index: `--packages-db <path>` for explicit override, `cupertino.config.json` next to the dev binary for redirection (#211)
