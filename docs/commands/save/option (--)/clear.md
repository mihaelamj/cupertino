# --clear

Clear existing index before building

## Synopsis

```bash
cupertino save --clear
```

## Description

Deletes the existing search database and rebuilds from scratch.

## Default

`true` (clears by default)

## Behavior

### With --clear (Default)
- Deletes existing search.db file
- Creates fresh database
- Rebuilds entire index
- All previous search data is lost

### Without --clear
- Keeps existing index
- Adds new/updated documents
- Incremental update
- Faster for small changes

## Examples

### Rebuild Index (Default)
```bash
cupertino save --clear
```

### Incremental Update
```bash
cupertino save --no-clear
```

### Clear with Custom Database
```bash
cupertino save --clear --search-db ./my-search.db
```

## Use Cases

### Use --clear when:
- First time indexing
- Documentation structure changed significantly
- Index is corrupted
- Want fresh start

### Use --no-clear when:
- Adding new documentation to existing index
- Small updates to documentation
- Want to preserve existing index data
- Faster incremental updates

## Notes

- Default is to clear (rebuild from scratch)
- Use `--no-clear` for incremental updates
- Clearing is safer but slower
- Incremental updates are faster but may have edge cases
