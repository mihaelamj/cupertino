# --format

Output format for the framework list

## Synopsis

```bash
cupertino list-frameworks --format <format>
```

## Description

Controls how the framework list is rendered. Different formats suit different consumers.

## Values

| Format | Description |
|--------|-------------|
| `text` | Human-readable list with framework names + document counts (default) |
| `json` | Structured JSON array, one object per framework |
| `markdown` | Markdown table with framework / count columns |

## Default

`text`

## Examples

### Default text output
```bash
cupertino list-frameworks
# SwiftUI    1234
# UIKit       890
# ...
```

### JSON for programmatic consumers
```bash
cupertino list-frameworks --format json | jq '.[] | select(.count > 100)'
```

### Markdown for embedding in docs
```bash
cupertino list-frameworks --format markdown
```

## Notes

- All three formats list the same frameworks in the same order (descending document count).
- JSON output is single-array for consistency with `cupertino search --format json`.
