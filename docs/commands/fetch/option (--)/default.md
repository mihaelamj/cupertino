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
  --max-pages 13000 \
  --max-depth 15 \
  --output-dir ~/.cupertino/docs
```

## Default Option Values

| Option | Default Value | Description |
|--------|---------------|-------------|
| `--type` | `docs` | Apple Developer Documentation |
| `--start-url` | (auto-detected from type) | Starting URL for crawl |
| `--max-pages` | `13000` | Maximum pages to crawl |
| `--max-depth` | `15` | Maximum depth from start URL |
| `--output-dir` | `~/.cupertino/docs` | Output directory |
| `--allowed-prefixes` | (auto-detected) | Allowed URL prefixes |
| `--force` | `false` | Don't force recrawl |
| `--resume` | `false` | Don't auto-resume |
| `--only-accepted` | `false` | All proposals (evolution only) |
| `--limit` | (unlimited) | No limit (packages/code) |
| `--authenticate` | `false` | No authentication |

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

By default, `--resume` is `false`, but the fetch command will:
1. Check for existing session in output directory
2. Auto-detect if session exists
3. Resume automatically if found

To force a fresh start:
```bash
cupertino fetch --force
```

## Notes

- Defaults chosen for typical use cases
- All defaults can be overridden
- Type-specific defaults optimize for each source
- Use `--help` to see all options
- Sensible defaults = less configuration needed
