# --type swift

Crawl Swift.org Documentation

## Synopsis

```bash
cupertino crawl --type swift
```

## Description

Crawls Swift programming language documentation from swift.org, including The Swift Programming Language book and other official Swift resources.

## Default Settings

| Setting | Value |
|---------|-------|
| Start URL | `https://www.swift.org/documentation` |
| Output Directory | `~/.cupertino/swift-org` |
| URL Prefix | `https://www.swift.org/` |

## What Gets Crawled

- The Swift Programming Language book
- Swift language guides
- Swift evolution overview
- Getting started guides
- Swift.org blog posts

## Examples

### Basic Swift.org Crawl
```bash
cupertino crawl --type swift
```

### Crawl with Custom Output
```bash
cupertino crawl --type swift --output-dir ./swift-docs
```

### Limited Crawl
```bash
cupertino crawl --type swift --max-pages 500
```

## Output Structure

```
~/.cupertino/swift-org/
├── metadata.json
├── documentation/
│   ├── swift-book/
│   └── ...
└── ...
```

## Notes

- Focused on Swift language itself, not frameworks
- Smaller scope than Apple documentation
- Includes The Swift Programming Language book
- Good for language learning resources
