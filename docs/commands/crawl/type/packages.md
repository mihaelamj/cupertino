# --type packages

Crawl Swift Package Index

## Synopsis

```bash
cupertino crawl --type packages
```

## Description

Crawls Swift Package Index to discover and document available Swift packages.

## Default Settings

| Setting | Value |
|---------|-------|
| Start URL | Swift Package Index |
| Output Directory | `~/.cupertino/packages` |
| URL Prefix | Auto-configured |

## What Gets Crawled

- Swift Package Index listings
- Package metadata
- Package descriptions
- Links to package repositories

## Note

For actually **downloading** package data and metadata, use `cupertino fetch --type packages` instead. The crawl command focuses on documentation pages, while fetch gets the actual package information from APIs.

## Examples

### Crawl Package Index Pages
```bash
cupertino crawl --type packages
```

### Better Alternative: Fetch Package Data
```bash
cupertino fetch --type packages
```

## Comparison

| Command | Purpose |
|---------|---------|
| `crawl --type packages` | Crawls package index web pages |
| `fetch --type packages` | Fetches package metadata from APIs |

## Recommendation

**Use `fetch` instead** for package data:
- Faster (API vs web crawling)
- More complete data
- Structured JSON output
- Direct from Swift Package Index + GitHub APIs

```bash
# Recommended
cupertino fetch --type packages
```

## Notes

- Crawling package pages is less efficient than fetching
- See `cupertino fetch --type packages` for better option
- This type exists for completeness
- Fetch command provides better package data
