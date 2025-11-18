# --type

Type of documentation to crawl

## Synopsis

```bash
cupertino crawl --type <value>
```

## Description

Specifies which type of documentation to crawl. Each type has a default start URL and URL prefix configuration.

## Available Types

- [all](all.md) - All documentation types (crawls everything in parallel)
- [docs](docs.md) - Apple Documentation (default)
- [swift](swift.md) - Swift.org documentation
- [evolution](evolution.md) - Swift Evolution proposals
- [packages](packages.md) - Swift packages

## Default

`docs` (Apple Documentation)

## Quick Examples

```bash
# Crawl everything in parallel
cupertino crawl --type all

# Apple Documentation
cupertino crawl --type docs

# Swift.org
cupertino crawl --type swift

# Swift Evolution
cupertino crawl --type evolution

# Swift Packages
cupertino crawl --type packages
```

## Notes

- Can be overridden with `--start-url`
- Each type auto-configures appropriate URL prefixes
- Output directory can be customized with `--output-dir`
