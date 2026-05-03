# Default Options Behavior

When no options are specified for `fetch` command

## Synopsis

```bash
cupertino fetch
```

## Default Behavior

When you run `cupertino fetch` without any options, it uses these defaults:

```bash
cupertino fetch \
  --type docs \
  --max-pages 1000000 \
  --max-depth 15 \
  --output-dir ~/.cupertino/docs
```

## Default Option Values

| Option | Default Value | Description |
|--------|---------------|-------------|
| `--type` | `docs` | Apple Developer Documentation |
| `--start-url` | (auto-detected from type) | Starting URL for crawl |
| `--max-pages` | `1000000` | Maximum pages to crawl (effectively uncapped) |
| `--max-depth` | `15` | Maximum depth from start URL |
| `--output-dir` | `~/.cupertino/docs` | Output directory |
| `--allowed-prefixes` | (auto-detected) | Allowed URL prefixes |
| `--force` | `false` | Don't re-fetch unchanged pages |
| `--start-clean` | `false` | Auto-resume any saved session |
| `--only-accepted` | `true` | Accepted/implemented proposals only (evolution only) |
| `--limit` | (unlimited) | No limit (packages/code) |

## Auto-Detection Features

### Start URL
Automatically set based on `--type`:
- `docs` → `https://developer.apple.com/documentation/`
- `swift` → `https://docs.swift.org/swift-book/...`
- `evolution` → (GitHub API)
- `packages` → (Swift Package Index API)
- `code` → (Apple Developer portal)

### Output Directory
Automatically set based on `--type`:
- `docs` → `~/.cupertino/docs`
- `swift` → `~/.cupertino/swift-book`
- `evolution` → `~/.cupertino/swift-evolution`
- `packages` → `~/.cupertino/packages`
- `code` → `~/.cupertino/sample-code`

### Allowed Prefixes
Auto-detected from start URL to prevent crawling external sites.

## Common Usage Patterns

### Minimal (All Defaults)
```bash
cupertino fetch
```

### With Type Only
```bash
cupertino fetch --type evolution
```

### Override Specific Options
```bash
# Change max pages, keep other defaults
cupertino fetch --max-pages 5000

# Use custom output directory
cupertino fetch --output-dir ./my-docs

# Force recrawl with defaults
cupertino fetch --force
```

### Multiple Options
```bash
cupertino fetch --type docs --max-pages 1000 --output-dir ./docs
```

## Resuming Behavior

`cupertino fetch` auto-resumes by default:
1. Checks for `metadata.json` in the output directory.
2. If `crawlState.isActive` is true and the start URL matches, restores the queue + visited set.
3. Continues from where the previous run stopped.

To override and start over:
```bash
# Discard saved queue/visited state, start from seed URL
cupertino fetch --start-clean

# Combine with --force to also re-fetch unchanged pages on disk
cupertino fetch --start-clean --force
```

## Notes

- Defaults chosen for typical use cases
- All defaults can be overridden
- Type-specific defaults optimize for each source
- Use `--help` to see all options
- Sensible defaults = less configuration needed
