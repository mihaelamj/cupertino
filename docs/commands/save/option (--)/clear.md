# --clear

Clear existing index before building

## Synopsis

```bash
cupertino save --clear
```

## Description

Wipes the existing index for the in-scope database(s) and rebuilds from scratch. Without `--clear`, `cupertino save` runs incrementally: it walks the corpus, computes content hashes, and only re-indexes documents whose hash differs from the row already in the DB. The unchanged-hash check (#1146) happens BEFORE the expensive AST symbol extraction (the slow step of a save), so an incremental run is fast and a save that was interrupted partway through **resumes** from where it stopped on the next non-`--clear` run. `--clear` empties the DB first, so nothing matches and the full index runs.

## Default

Off (`--clear` not set → incremental). The flag is a plain `@Flag` without an inversion pair, so `--no-clear` is **not** a valid invocation; just omit `--clear`.

## Behavior

### With `--clear`
- Drops or wipes the rows for the in-scope databases (the per-source docs DBs such as `apple-documentation.db`, plus `packages.db` / `apple-sample-code.db`, depending on which sources are in scope).
- Recreates schema from the current SchemaVersion.
- Rebuilds the entire index.
- Previous index data is lost.

### Without `--clear` (default)
- Keeps existing index rows.
- Adds new documents and replaces rows whose content hash changed.
- Skips an unchanged doc (same `content_hash`) BEFORE AST symbol extraction (#1146), so an interrupted index resumes from where it stopped and an all-unchanged re-save is a near no-op.
- Drops rows for files that no longer exist on disk.
- Faster for partial recrawls.

Note: `--source samples` always wipes-and-rebuilds inside its scope independent of `--clear` (the samples-side schema doesn't yet support partial updates). `--clear` is meaningful for the docs sources (e.g. `--source apple-docs` → `apple-documentation.db`) and `--source packages` (`packages.db`).

## Examples

### Rebuild from scratch (force full re-index of apple-documentation.db)
```bash
cupertino save --clear
```

### Default incremental update
```bash
cupertino save --all
```

### Clear targeted at a custom DB path
```bash
cupertino save --clear --search-db ./apple-documentation.db
```

## Use Cases

### Use `--clear` when:
- Schema has changed (post-migration cleanup)
- Documentation structure changed significantly
- Index is suspected corrupted
- You want a known-clean baseline

### Skip `--clear` (default) when:
- Adding to an existing index
- Re-indexing after a partial recrawl
- Day-to-day rebuilds where most pages haven't changed
- You want the fastest cycle

## Notes

- Default is incremental (no clear). `--no-clear` is not a valid flag, there's no inversion pair.
- Clearing scope depends on which sources are in scope (`--source <id>`, repeatable, or `--all`).
- For `--source samples` the scope is always wiped-and-rebuilt regardless of `--clear`.
