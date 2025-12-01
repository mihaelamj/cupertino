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
| `swift-evolution` | Swift Evolution proposals |
| `swift-org` | Swift.org documentation |
| `swift-book` | The Swift Programming Language book |
| `packages` | Swift package metadata |
| `apple-sample-code` | Apple sample code projects |

## Default

None (searches all sources)

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

## Value Details

- [apple-docs](source%20(=value)/apple-docs.md) - Apple Developer Documentation
- [swift-evolution](source%20(=value)/swift-evolution.md) - Swift Evolution proposals
- [swift-org](source%20(=value)/swift-org.md) - Swift.org documentation
- [swift-book](source%20(=value)/swift-book.md) - The Swift Programming Language book
- [packages](source%20(=value)/packages.md) - Swift package metadata
- [apple-sample-code](source%20(=value)/apple-sample-code.md) - Apple sample code projects

## Combining with Other Filters

```bash
cupertino search "animation" --source apple-docs --framework swiftui
cupertino search "Sendable" --source swift-evolution --limit 5
```

## Notes

- Source filtering happens at the database query level (efficient)
- Case-insensitive matching
- Invalid source values return no results
