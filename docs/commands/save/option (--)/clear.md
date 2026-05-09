# --clear

Clear existing index before building

## Synopsis

```bash
cupertino save --clear
```

## Description

Wipes the existing index for the in-scope database(s) and rebuilds from scratch. Without `--clear`, `cupertino save` runs incrementally: it walks the corpus, computes content hashes, and only re-indexes documents whose hash differs from the row already in the DB.

## Default

Off (`--clear` not set → incremental). The flag is a plain `@Flag` without an inversion pair, so `--no-clear` is **not** a valid invocation; just omit `--clear`.

## Behavior

### With `--clear`
- Drops or wipes the rows for the in-scope database (search.db / packages.db / samples.db depending on which scope flags are set).
- Recreates schema from the current SchemaVersion.
- Rebuilds the entire index.
- Previous index data is lost.

### Without `--clear` (default)
- Keeps existing index rows.
- Adds new documents and replaces rows whose content hash changed.
- Drops rows for files that no longer exist on disk.
- Faster for partial recrawls.

Note: `--samples` always wipes-and-rebuilds inside its scope independent of `--clear` (the samples-side schema doesn't yet support partial updates). `--clear` is meaningful for `--docs` (search.db) and `--packages` (packages.db).

## Examples

### Rebuild from scratch (force full re-index of search.db)
```bash
cupertino save --clear
```

### Default incremental update
```bash
cupertino save
```

### Clear targeted at a custom DB path
```bash
cupertino save --clear --search-db ./my-search.db
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

- Default is incremental (no clear). `--no-clear` is not a valid flag — there's no inversion pair.
- Clearing scope depends on which scope flags are passed (`--docs` / `--packages` / `--samples`); when none are passed, `--clear` applies to whichever scopes the default run touches.
- For `--samples` the scope is always wiped-and-rebuilt regardless of `--clear`.
