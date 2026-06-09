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
| [docs/](folders/docs/) | Crawled Apple documentation | [README](folders/docs/) + [metadata.json](folders/docs/metadata.json.md) (the per-corpus crawl state, same format used by every per-source `metadata.json`) |
| [swift-org/](folders/swift-org/) | Crawled Swift.org documentation | [README](folders/swift-org/) |
| [swift-evolution/](folders/swift-evolution/) | Swift Evolution proposals | [README](folders/swift-evolution/) |
| [archive/](folders/archive/) | Apple Archive programming guides | [README](folders/archive/) |
| [hig/](folders/hig/) | Human Interface Guidelines | [README](folders/hig/) |
| [sample-code/](folders/sample-code/) | Apple sample code ZIP files | [README](folders/sample-code/) + [.auth-cookies.json](folders/sample-code/.auth-cookies.json.md) |
| [packages/](folders/packages/) | Swift package metadata + extracted source archives | [README](folders/packages/) + [swift-packages-with-stars.json](folders/packages/swift-packages-with-stars.json.md) + [checkpoint.json](folders/packages/checkpoint.json.md) + per-package `<owner>/<repo>/` source trees |
| [apple-documentation.db](folders/apple-documentation.db.md) | FTS5 search index for Apple Developer Documentation | File documentation |
| [hig.db](folders/hig.db.md) | FTS5 search index for the Human Interface Guidelines | File documentation |
| [apple-archive.db](folders/apple-archive.db.md) | FTS5 search index for Apple Archive guides | File documentation |
| [swift-evolution.db](folders/swift-evolution.db.md) | FTS5 search index for Swift Evolution proposals | File documentation |
| [swift-org.db](folders/swift-org.db.md) | FTS5 search index for Swift.org documentation | File documentation |
| [swift-book.db](folders/swift-book.db.md) | FTS5 search index for The Swift Programming Language | File documentation |
| [apple-sample-code.db](folders/apple-sample-code.db.md) | FTS5 search index for Apple sample code | File documentation |
| [packages.db](folders/packages.db.md) | FTS5 search index for Swift packages | File documentation |
| [config.json](folders/config.json.md) | Application configuration | File documentation |

The eight databases above are the v1.3.0 per-source split of the former unified `search.db` ([#1036](https://github.com/mihaelamj/cupertino/issues/1036)); all ship in rollback (read-only) mode.

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
├── archive/                # Apple Archive Guides (legacy)
│   └── [guide folders]/    # TP30001066/, TP40004514/, etc.
└── hig/                    # Human Interface Guidelines
    └── [category folders]/ # foundations/, patterns/, etc.
```

### Fetch Artifacts
```
~/.cupertino/
├── sample-code/            # Apple Sample Code
│   ├── checkpoint.json
│   └── *.zip              # 600+ ZIP files
└── packages/              # Swift Packages
    ├── checkpoint.json                    # Progress tracking
    └── swift-packages-with-stars.json    # Final output (~9,700 packages)
```

### Index Artifacts
```
~/.cupertino/
├── apple-documentation.db # Apple Developer Documentation (per-source split, v1.3.0)
├── hig.db                 # Human Interface Guidelines
├── apple-archive.db       # Apple Archive guides
├── swift-evolution.db     # Swift Evolution proposals
├── swift-org.db           # Swift.org documentation
├── swift-book.db          # The Swift Programming Language
├── apple-sample-code.db   # Apple sample code
└── packages.db            # Swift packages
```

## Finding Artifacts

### By Operation

| Operation | Creates | Location |
|-----------|---------|----------|
| `cupertino fetch --source apple-docs` | DocC JSON pages + metadata | `~/.cupertino/docs/` |
| `cupertino fetch --source swift-org` | Markdown/HTML-derived pages + metadata | `~/.cupertino/swift-org/` |
| `cupertino fetch --source swift-evolution` | Proposal files + metadata | `~/.cupertino/swift-evolution/` |
| `cupertino fetch --source apple-archive` | Markdown files | `~/.cupertino/archive/` |
| `cupertino fetch --source hig` | Markdown files | `~/.cupertino/hig/` |
| `cupertino fetch --source apple-sample-code` | ZIP files + checkpoint | `~/.cupertino/sample-code/` |
| `cupertino fetch --source samples` | Git clone (619 projects) | `~/.cupertino/sample-code/cupertino-sample-code/` |
| `cupertino fetch --source packages` | Package data + checkpoint | `~/.cupertino/packages/` |
| `cupertino fetch --source availability` | Updates JSON with availability | `~/.cupertino/docs/*.json` |
| `cupertino save --source <id>` | The selected per-source database | `~/.cupertino/<source>.db` |
| `cupertino save --all` | All eight databases | `~/.cupertino/*.db` |
| `cupertino save --source samples` | Sample code search database | `~/.cupertino/apple-sample-code.db` |

## Customizing Locations

All default locations can be customized:
- Use `--output-dir` for crawl/fetch operations
- Use `--base-dir` / `--source <id>` for index operations
- Use `--metadata-file` to specify custom metadata location

## See Also

- [Commands Documentation](../commands/) - How to create these artifacts
- Individual artifact documentation in this folder
