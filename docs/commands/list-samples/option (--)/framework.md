# --framework / -f

Filter samples by framework

## Synopsis

```bash
cupertino list-samples --framework <framework>
cupertino list-samples -f <framework>
```

## Description

Restrict the listing to projects that use the named framework (e.g., `swiftui`, `uikit`, `appkit`). Match is case-insensitive against the framework names extracted from each project's `import` statements during `cupertino save --samples`.

## Examples

### List all SwiftUI samples
```bash
cupertino list-samples --framework swiftui
```

### List UIKit samples (short form)
```bash
cupertino list-samples -f uikit
```

### Combine with limit
```bash
cupertino list-samples -f swiftui --limit 10
```

## Notes

- Framework names are case-insensitive: `SwiftUI`, `swiftui`, `SWIFTUI` all match.
- A project with multiple frameworks shows up under each one it imports.
- Without `--framework`, the listing covers every indexed sample.
