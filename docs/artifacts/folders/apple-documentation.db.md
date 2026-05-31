# apple-documentation.db - Apple Developer Documentation FTS5 Index

Per-source SQLite FTS5 database for Apple Developer Documentation. One of the eight per-source databases produced by the v1.3.0 split of the former unified `search.db` ([#1036](https://github.com/mihaelamj/cupertino/issues/1036)).

## Location

**Default**: `~/.cupertino/apple-documentation.db`

Ships in rollback (`journal=delete`) mode ([#1192](https://github.com/mihaelamj/cupertino/issues/1192)): it opens read-only with no `-wal` / `-shm` sidecar, so the file is self-contained for copy and distribution. Bundled in `cupertino-databases-v<version>.zip` and installed by `cupertino setup`. Every query / read / serve connection opens it read-only ([#1194](https://github.com/mihaelamj/cupertino/issues/1194)).

## Contents

| Property | Value |
|---|---|
| Source id | `apple-docs` |
| URI scheme | `apple-docs://swiftui/View` |
| Approx. documents | ~351,505 |
| Approx. size | ~2.8 GB |
| Schema version (`PRAGMA user_version`) | 18 |

240,543 ast symbols across 420+ frameworks.

## Schema

Shares the documentation FTS5 schema with the other per-source docs databases: the `docs_fts` / `docs_metadata` / `docs_structured` / `framework_aliases` / `doc_code_examples` / `doc_code_fts` / `doc_symbols` / `doc_symbols_fts` / `doc_imports` family. The schema is identical across all six per-source docs databases; the full schema (tables, BM25F weights, enrichment passes) is described in the [database architecture reference](../../architecture/database.md), which links to the canonical DDL in `Search.Index.Schema.swift`.

## See also

- [Artifacts index](README.md)
- [database architecture reference](../../architecture/database.md) - full schema, BM25F weights, enrichment passes
- Per-source split rationale: [#1036](https://github.com/mihaelamj/cupertino/issues/1036)
