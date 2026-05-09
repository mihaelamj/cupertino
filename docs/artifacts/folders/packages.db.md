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

## Database Structure

SQLite database with regular `packages` and `package_files` tables plus a paired FTS5 mirror, `package_files_fts`.

### `package_files_fts` (FTS5 virtual table)

```sql
CREATE VIRTUAL TABLE package_files_fts USING fts5(
    package_id UNINDEXED,   -- e.g. "swiftlang/swift-collections"
    owner      UNINDEXED,   -- e.g. "swiftlang"
    repo       UNINDEXED,   -- e.g. "swift-collections"
    module     UNINDEXED,   -- declared SwiftPM module name
    relpath    UNINDEXED,   -- path relative to the repo root
    kind       UNINDEXED,   -- file role (source, readme, manifest, etc.)
    title,                  -- searchable: filename + module hints
    content,                -- searchable: full file contents
    symbols,                -- searchable: AST-extracted Swift symbol names
    tokenize='porter unicode61'
);
```

`UNINDEXED` columns are stored but excluded from FTS scoring; they're used as filter / projection columns. The three indexed columns (`title`, `content`, `symbols`) feed BM25.

### `packages` table

Holds per-package metadata: canonical owner/repo, declared SwiftPM module names, README, declared deployment targets (iOS/macOS/tvOS/watchOS/visionOS), `@available` annotation summary (#219), priority tier (#192 priority list).

Schema version stamped via `PRAGMA user_version` and migrated incrementally on open.

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
