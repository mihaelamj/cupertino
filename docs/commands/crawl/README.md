# cupertino crawl

Crawl documentation using WKWebView

## Synopsis

```bash
cupertino crawl [options]
```

## Description

The `crawl` command downloads and converts documentation to Markdown using WebKit's WKWebView. This is the most powerful crawling method as it can handle JavaScript-rendered content.

## Options

- [--type](type/) - Type of documentation to crawl (docs, swift, evolution, packages)
- [--start-url](start-url.md) - Start URL to crawl from
- [--max-pages](max-pages.md) - Maximum number of pages to crawl
- [--max-depth](max-depth.md) - Maximum depth to crawl
- [--output-dir](output-dir.md) - Output directory for documentation
- [--allowed-prefixes](allowed-prefixes.md) - Allowed URL prefixes
- [--force](force.md) - Force recrawl of all pages
- [--resume](resume.md) - Resume from saved session
- [--only-accepted](only-accepted.md) - Only download accepted proposals (evolution only)

## Examples

### Crawl Apple Documentation (default)
```bash
cupertino crawl
```

### Crawl Swift.org Documentation
```bash
cupertino crawl --type swift
```

### Crawl Swift Evolution Proposals (Accepted Only)
```bash
cupertino crawl --type evolution --only-accepted
```

### Crawl Specific Framework with Limits
```bash
cupertino crawl --start-url https://developer.apple.com/documentation/swiftui --max-pages 500 --max-depth 10
```

### Resume Interrupted Crawl
```bash
cupertino crawl --resume
```

## Output

The crawler creates:
- **Markdown files** - One `.md` file per documentation page
- **Metadata** - `metadata.json` tracking crawl progress and content hashes
- **Directory structure** - Mirrors the URL path structure

## Notes

- Uses WKWebView for JavaScript-heavy pages
- Supports change detection via content hashing
- Auto-saves progress for resume capability
- Respects URL prefixes to stay within documentation boundaries

## Next Steps

After crawling documentation:

1. **Build a search index** (recommended):
   ```bash
   cupertino index
   ```

2. **Start the MCP server**:
   ```bash
   cupertino
   ```

The MCP server will serve the crawled documentation to AI assistants like Claude.

## See Also

- [../index/](../index/) - Build search index
- [../mcp/](../mcp/) - MCP server commands
