command# --framework, -f

Filter search results by Apple framework

## Synopsis

```bash
cupertino search <query> --framework <framework>
cupertino search <query> -f <framework>
```

## Description

Filters search results to only include documents from the specified Apple framework. This is useful when searching for APIs within a specific framework.

## Common Values

| Framework | Description |
|-----------|-------------|
| `swiftui` | SwiftUI framework |
| `swift` | Swift standard library |
| `foundation` | Foundation framework |
| `uikit` | UIKit framework |
| `appkit` | AppKit framework |
| `combine` | Combine framework |
| `coredata` | Core Data framework |
| `coregraphics` | Core Graphics framework |
| `avfoundation` | AVFoundation framework |

## Default

None (searches all frameworks)

## Examples

### Search SwiftUI
```bash
cupertino search "View" --framework swiftui
```

### Search Foundation
```bash
cupertino search "URL" --framework foundation
```

### Search UIKit
```bash
cupertino search "UIViewController" -f uikit
```

### Search Swift Standard Library
```bash
cupertino search "Array" --framework swift
```

## Combining with Other Filters

### Framework + Source
```bash
cupertino search "animation" --framework swiftui --source apple-docs
```

### Framework + Limit
```bash
cupertino search "View" --framework swiftui --limit 10
```

### Framework + Verbose
```bash
cupertino search "Text" --framework swiftui --verbose
```

## Use Cases

- **API discovery**: Find all APIs in a specific framework
- **Learning**: Focus on one framework at a time
- **Migration**: Search for APIs when migrating between frameworks
- **Documentation**: Find specific framework documentation

## Notes

- Framework names are lowercase
- Matches the `framework` field in indexed documents
- Case-insensitive matching
- Invalid framework values return no results
- Some documents may have `nil` framework (e.g., Swift Evolution proposals)
