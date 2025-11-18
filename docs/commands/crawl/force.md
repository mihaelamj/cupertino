# --force

Force recrawl of all pages

## Synopsis

```bash
cupertino crawl --force
```

## Description

Forces the crawler to re-download all pages, ignoring the cached content hashes in `metadata.json`. Use this when you want a fresh crawl regardless of changes.

## Default Behavior (Without --force)

By default, the crawler uses change detection:
- Checks content hash in `metadata.json`
- Only re-downloads pages that have changed
- Skips unchanged pages

## With --force

- Ignores all cached metadata
- Re-downloads every page
- Updates all content hashes
- Useful for fresh starts or when metadata is corrupted

## Examples

### Force Recrawl Everything
```bash
cupertino crawl --force
```

### Force Recrawl with Limits
```bash
cupertino crawl --force --max-pages 100
```

### Force Recrawl Specific Type
```bash
cupertino crawl --type swift --force
```

## Use Cases

- Starting fresh after metadata corruption
- Ensuring all pages are current
- Testing crawler behavior
- Metadata file was deleted or modified externally

## Notes

- Can be slower than regular crawl
- Downloads all pages regardless of changes
- Cannot be combined with `--resume`
