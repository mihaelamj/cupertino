# --search-db

Path to search database file

## Synopsis

```bash
cupertino doctor --search-db <path>
```

## Description

Specifies the SQLite search database file to check. The doctor command will verify that the database exists, is readable, and has valid FTS5 schema.

## Default

`~/.cupertino/search.db`

## Examples

### Check Default Database
```bash
cupertino doctor
```

### Check Custom Database
```bash
cupertino doctor --search-db ./my-search.db
```

### Check Specific Database
```bash
cupertino doctor --search-db ~/.cupertino/apple-search.db
```

### Absolute Path
```bash
cupertino doctor --search-db /Users/username/Documents/search.db
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
🔍 Search Index
   ✓ Database: ~/.cupertino/search.db
   ✓ Size: 2.5 GB
   ✓ Frameworks: 261
   ✓ Schema version: 12 (matches binary)
```

If not found:
```
🔍 Search Index
   ✗ Database: ~/.cupertino/search.db (not found)
     → Run: cupertino save
```

If corrupted:
```
🔍 Search Index
   ✗ Database error: unable to open database file
     → Run: cupertino save
```

## Database Schema

The search database contains:
- `docs_fts` - FTS5 full-text search table
- `docs_metadata` - Document metadata
- Indexes for fast lookups

## Database Size Examples

Approximate, snapshot of the v1.0.2 corpus (your local DB will vary):

| Documentation Size | Index Size |
|-------------------|------------|
| ~277,000 pages (Apple docs + HIG + archive + Swift Book + swift.org), post-#283 dedup | ~2.4 GB |
| ~500 proposals (Swift Evolution) | ~2-3 MB |
| Combined `search.db` | ~2.4 GB |

(`packages.db` and `samples.db` are separate from `search.db` and aren't sized in by `--search-db`.)

## Notes

- Tilde (`~`) expansion is supported
- Database must be created by `cupertino save`
- Uses SQLite FTS5 extension
- Required for search functionality in MCP server
- Can be queried directly with SQLite tools
- Doctor validates schema integrity
- If missing, MCP server will start but search tools won't be available
