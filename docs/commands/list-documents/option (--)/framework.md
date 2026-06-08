# --framework

Framework to browse.

## Synopsis

```bash
cupertino list-documents --framework <framework>
```

## Description

Required. Accepts the canonical framework slug (`swiftui`), import name (`SwiftUI`), or display name when aliases are present in the index. The response echoes the resolved framework slug.

## Examples

```bash
cupertino list-documents --framework swiftui
cupertino list-documents --framework SwiftUI
```
