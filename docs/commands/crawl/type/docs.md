# --type docs

Crawl Apple Documentation

## Synopsis

```bash
cupertino crawl --type docs
```

## Description

Crawls Apple's official developer documentation from developer.apple.com/documentation.

## Default Settings

| Setting | Value |
|---------|-------|
| Start URL | `https://developer.apple.com/documentation` |
| Output Directory | `~/.cupertino/docs` |
| URL Prefix | `https://developer.apple.com/documentation/` |

## What Gets Crawled

- All Apple framework documentation
- API references
- Guides and tutorials
- Code examples
- Conceptual articles

## Examples

### Basic Apple Documentation Crawl
```bash
cupertino crawl --type docs
```

### Crawl with Limits
```bash
cupertino crawl --type docs --max-pages 1000 --max-depth 10
```

### Crawl to Custom Directory
```bash
cupertino crawl --type docs --output-dir ./apple-docs
```

## Output Structure

```
~/.cupertino/docs/
├── metadata.json
├── swift/
├── swiftui/
├── uikit/
├── foundation/
└── ...
```

## Notes

- This is the default type
- Includes all public Apple frameworks
- Requires internet connection
- Large crawl (10,000+ pages possible)
- Use `--max-pages` to limit scope
