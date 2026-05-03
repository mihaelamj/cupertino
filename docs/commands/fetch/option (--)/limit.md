# --limit

Maximum number of items to fetch

## Synopsis

```bash
cupertino fetch --type <type> --limit <number>
```

## Description

Limits the total number of items to fetch. Useful for testing or partial downloads.

## Default

No limit (fetches all available items)

## Examples

### Fetch First 50 Packages
```bash
cupertino fetch --type packages --limit 50
```

### Fetch First 10 Sample Code Projects
```bash
cupertino fetch --type code --limit 10
```

### Fetch 100 Packages to Custom Directory
```bash
cupertino fetch --type packages --limit 100 --output-dir ./test-packages
```

## Behavior

- For `packages`: Stops after fetching N package metadata entries
- For `code`: Stops after downloading N ZIP files

## Notes

- Fetches items in order they appear in source
- Re-running with a larger `--limit` continues from the saved checkpoint (resume is automatic)
- Pass `--start-clean` to discard the checkpoint and start over
