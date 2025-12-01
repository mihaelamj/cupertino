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

### Search Packages
```bash
cupertino search "networking" --source packages
```

## Combining with Other Filters

### Source + Framework
```bash
cupertino search "animation" --source apple-docs --framework swiftui
```

### Source + Limit
```bash
cupertino search "Sendable" --source swift-evolution --limit 5
```

### Source + JSON Output
```bash
cupertino search "Observable" --source apple-docs --format json
```

## Use Cases

- **Research proposals**: Find Swift Evolution proposals on a topic
- **Official docs only**: Exclude community packages from results
- **Package discovery**: Search only Swift packages
- **Learning**: Focus on Swift book content for fundamentals

## Notes

- Source filtering happens at the database query level (efficient)
- Case-insensitive matching
- Invalid source values return no results
- Corresponds to the `source` field in search results
