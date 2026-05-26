# --limit

Maximum number of items to fetch

## Synopsis

```bash
cupertino fetch --source <id> --limit <number>
```

## Description

Limits the total number of items to fetch. Useful for testing or partial downloads.

## Default

No limit (fetches all available items)

## Examples

### Fetch First 50 Packages
```bash
cupertino fetch --source packages --limit 50
```

### Fetch First 10 Sample Code Projects
```bash
cupertino fetch --source apple-sample-code --limit 10
```

### Fetch 100 Packages to Custom Directory
```bash
cupertino fetch --source packages --limit 100 --output-dir ./test-packages
```

## Behavior

- For `packages` (stage 1, metadata refresh): stops after fetching N package metadata entries. Has no effect on stage 2 (archive download), the archive set is driven by `PriorityPackagesCatalog`, not the metadata limit.
- For `code`: Stops after downloading N ZIP files

## Notes

- Fetches items in order they appear in source
- Re-running with a larger `--limit` continues from the saved checkpoint (resume is automatic)
- Pass `--start-clean` to discard the checkpoint and start over
- For packages, combine with `--skip-archives` if you only want a limited metadata sample
