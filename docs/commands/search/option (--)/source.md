# --source, -s

Filter search results by documentation source

## Synopsis

```bash
cupertino search <query> --source <source>
cupertino search <query> -s <source>
```

## Description

Filters search results to only include documents from the specified documentation source. This allows targeting specific collections within the indexed documentation.

## Values

| Value | Description |
|-------|-------------|
| `apple-docs` | Apple Developer Documentation |
| `samples` | Sample code projects (samples.db, populated by `cupertino save --samples`) |
| `hig` | Human Interface Guidelines |
| `apple-archive` | Apple Archive legacy programming guides |
| `swift-evolution` | Swift Evolution proposals |
| `swift-org` | Swift.org documentation |
| `swift-book` | The Swift Programming Language book |
| `packages` | Swift package documentation (packages.db) |
| `all` | Explicit fan-out across every available source (equivalent to omitting `--source`) |

## Default

None — when `--source` is omitted, `cupertino search` runs in fan-out mode (chunked excerpts, RRF-fused across every available DB).

## Examples

### Search Apple Documentation Only
```bash
cupertino search "View" --source apple-docs
```

### Search Swift Evolution Proposals
```bash
cupertino search "async" --source swift-evolution
```

### Search Swift Book
```bash
cupertino search "closures" -s swift-book
```

### Search Human Interface Guidelines
```bash
cupertino search "buttons" --source hig
```

## Value Details

- [apple-docs](source%20(=value)/apple-docs.md) — Apple Developer Documentation
- [samples](source%20(=value)/samples.md) — Sample code projects (samples.db)
- [hig](source%20(=value)/hig.md) — Human Interface Guidelines
- [apple-archive](source%20(=value)/apple-archive.md) — Apple Archive legacy guides
- [swift-evolution](source%20(=value)/swift-evolution.md) — Swift Evolution proposals
- [swift-org](source%20(=value)/swift-org.md) — Swift.org documentation
- [swift-book](source%20(=value)/swift-book.md) — The Swift Programming Language book
- [packages](source%20(=value)/packages.md) — Swift package documentation
- [all](source%20(=value)/all.md) — Explicit fan-out across every source

## Combining with Other Filters

```bash
cupertino search "animation" --source apple-docs --framework swiftui
cupertino search "Sendable" --source swift-evolution --limit 5
```

## Notes

- Source filtering happens at the database query level (efficient)
- Case-insensitive matching
- Invalid source values return no results
