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
cupertino fetch --type code --authenticate --limit 10
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
- Can be combined with `--resume` to fetch more later
- Progress is saved in checkpoint, so you can resume to get more
