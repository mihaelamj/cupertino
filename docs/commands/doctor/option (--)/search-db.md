# --search-db

Override the apple-docs database path (legacy flag name)

## Synopsis

```bash
cupertino doctor --search-db <path>
```

## Description

Points the apple-docs health check at a specific database file. Post-#1037 the apple-docs index is the per-source `apple-documentation.db`, resolved through the registry; this legacy flag overrides that path. The doctor command verifies the database exists, is readable, and has a valid FTS5 schema.

## Default

`~/.cupertino/apple-documentation.db`

## Examples

### Check Default Database
```bash
cupertino doctor
```

### Check Custom Database
```bash
cupertino doctor --search-db ./apple-documentation.db
```

### Check Specific Database
```bash
cupertino doctor --search-db ~/.cupertino/apple-documentation.db
```

### Absolute Path
```bash
cupertino doctor --search-db /Users/username/Documents/apple-documentation.db
```

## Health Check Behavior

The doctor command checks:
- ✓ Database file exists
- ✓ Database is readable
- ✓ SQLite format is valid
- ✓ FTS5 schema is correct
- ✓ Can query framework count
- ✓ Reports database size
- ✓ Reports indexed framework count

Example output:
```
🔍 Apple Developer Documentation (apple-documentation.db)
   ✓ Database: ~/.cupertino/apple-documentation.db
   ✓ Size: 2.82 GB
   ✓ Frameworks: 398
   ✓ Schema version: 18 (matches binary)
```

If not found:
```
🔍 Apple Developer Documentation (apple-documentation.db)
   ✗ Database: ~/.cupertino/apple-documentation.db (not found)
     → Run: cupertino setup  (or `cupertino save --source apple-docs`)
```

If corrupted:
```
🔍 Search Index
   ✗ Database error: unable to open database file
     → Run: cupertino setup  (or `cupertino save --source apple-docs`)
```

## Database Schema

The search database contains:
- `docs_fts` - FTS5 full-text search table
- `docs_metadata` - Document metadata
- Indexes for fast lookups

## Database Size Examples

Approximate, snapshot of the v1.3.0 corpus (your local DB will vary):

| Documentation Size | Index Size |
|-------------------|------------|
| ~277,000 pages (Apple docs + HIG + archive + Swift Book + swift.org), post-#283 dedup | ~2.4 GB |
| ~500 proposals (Swift Evolution) | ~2-3 MB |
| Combined `apple-documentation.db` | ~2.8 GB |

(`packages.db` and `apple-sample-code.db` are separate from `apple-documentation.db` and aren't sized in by `--search-db`.)

## Notes

- Tilde (`~`) expansion is supported
- Database created by `cupertino setup` (or `cupertino save --source apple-docs`)
- Uses SQLite FTS5 extension
- Required for search functionality in MCP server
- Can be queried directly with SQLite tools
- Doctor validates schema integrity
- If missing, MCP server will start but search tools won't be available
