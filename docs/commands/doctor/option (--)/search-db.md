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
   ✓ Size: 52.3 MB
   ✓ Frameworks: 287
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

| Documentation Size | Index Size |
|-------------------|------------|
| 13,000 pages (Apple) | ~50 MB |
| 400 proposals (Evolution) | ~2 MB |
| Combined | ~52 MB |

## Notes

- Tilde (`~`) expansion is supported
- Database must be created by `cupertino save`
- Uses SQLite FTS5 extension
- Required for search functionality in MCP server
- Can be queried directly with SQLite tools
- Doctor validates schema integrity
- If missing, MCP server will start but search tools won't be available
