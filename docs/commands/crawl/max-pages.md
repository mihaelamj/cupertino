# --max-pages

Maximum number of pages to crawl

## Synopsis

```bash
cupertino crawl --max-pages <number>
```

## Description

Limits the total number of pages to crawl. Useful for testing or crawling specific sections.

## Default

`15000`

## Examples

### Limit to 100 Pages
```bash
cupertino crawl --max-pages 100
```

### Crawl Only 10 Pages for Testing
```bash
cupertino crawl --max-pages 10 --start-url https://developer.apple.com/documentation/swift
```

### Full Crawl (Default)
```bash
cupertino crawl --max-pages 15000
```

## Notes

- Crawler stops when limit is reached
- Does not guarantee which pages are crawled (depends on link discovery order)
- Use with `--max-depth` for more predictable results
