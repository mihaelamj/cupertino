# Cupertino Artifacts

Documentation for all folders and files created by Cupertino operations.

## Overview

Cupertino creates various artifacts during crawling, fetching, and indexing operations. This documentation describes where to find these artifacts and what they contain.

## Default Base Directory

All Cupertino artifacts are stored under:
```
~/.cupertino/
```

## Artifact Types

| Artifact | Description | Documentation |
|----------|-------------|---------------|
| [docs/](folders/docs/) | Crawled Apple documentation | [README](folders/docs/) + [metadata.json](folders/docs/metadata.json.md) |
| [swift-org/](folders/swift-org/) | Crawled Swift.org documentation | [README](folders/swift-org/) + [metadata.json](folders/docs/metadata.json.md) |
| [swift-evolution/](folders/swift-evolution/) | Swift Evolution proposals | [README](folders/swift-evolution/) + [metadata.json](folders/docs/metadata.json.md) |
| [archive/](folders/archive/) | Apple Archive programming guides | [README](folders/archive/) |
| [sample-code/](folders/sample-code/) | Apple sample code ZIP files | [README](folders/sample-code/) + [.auth-cookies.json](folders/sample-code/.auth-cookies.json.md) |
| [packages/](folders/packages/) | Swift package metadata | [README](folders/packages/) + [swift-packages-with-stars.json](folders/packages/swift-packages-with-stars.json.md) + [checkpoint.json](folders/packages/checkpoint.json.md) |
| [search.db](folders/search.db.md) | FTS5 search index for documentation | File documentation |
| [samples.db](folders/samples.db.md) | FTS5 search index for sample code | File documentation |
| [config.json](folders/config.json.md) | Application configuration | File documentation |

## Quick Reference

### Crawl Artifacts
```
~/.cupertino/
├── docs/                    # Apple Documentation
│   ├── metadata.json
│   └── [framework folders]/
├── swift-org/              # Swift.org Documentation
│   ├── metadata.json
│   └── [content folders]/
├── swift-evolution/        # Swift Evolution Proposals
│   ├── metadata.json
│   └── proposals/
└── archive/                # Apple Archive Guides (legacy)
    └── [guide folders]/    # TP30001066/, TP40004514/, etc.
```

### Fetch Artifacts
```
~/.cupertino/
├── sample-code/            # Apple Sample Code
│   ├── checkpoint.json
│   └── *.zip              # 600+ ZIP files
└── packages/              # Swift Packages
    ├── checkpoint.json                    # Progress tracking
    └── swift-packages-with-stars.json    # Final output (9,699 packages)
```

### Index Artifacts
```
~/.cupertino/
├── search.db              # FTS5 Search Database (documentation)
└── samples.db             # FTS5 Search Database (sample code)
```

## Finding Artifacts

### By Operation

| Operation | Creates | Location |
|-----------|---------|----------|
| `cupertino fetch --type docs` | Markdown files + metadata | `~/.cupertino/docs/` |
| `cupertino fetch --type swift` | Markdown files + metadata | `~/.cupertino/swift-org/` |
| `cupertino fetch --type evolution` | Proposal files + metadata | `~/.cupertino/swift-evolution/` |
| `cupertino fetch --type archive` | Markdown files | `~/.cupertino/archive/` |
| `cupertino fetch --type code` | ZIP files + checkpoint | `~/.cupertino/sample-code/` |
| `cupertino fetch --type samples` | Git clone (606 projects) | `~/.cupertino/sample-code/cupertino-sample-code/` |
| `cupertino fetch --type packages` | Package data + checkpoint | `~/.cupertino/packages/` |
| `cupertino save` | Documentation search database | `~/.cupertino/search.db` |
| `cupertino index` | Sample code search database | `~/.cupertino/samples.db` |

## Customizing Locations

All default locations can be customized:
- Use `--output-dir` for crawl/fetch operations
- Use `--search-db` for index operations
- Use `--metadata-file` to specify custom metadata location

## See Also

- [Commands Documentation](../commands/) - How to create these artifacts
- Individual artifact documentation in this folder
