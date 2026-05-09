# --format

Output format for the sample list

## Synopsis

```bash
cupertino list-samples --format <format>
```

## Description

Controls how the indexed-samples list is rendered.

## Values

| Format | Description |
|--------|-------------|
| `text` | Human-readable list (default) |
| `json` | Structured JSON array, one object per sample |
| `markdown` | Markdown table with project / framework / file count |

## Default

`text`

## Examples

### Default text output
```bash
cupertino list-samples
```

### JSON for programmatic consumers
```bash
cupertino list-samples --format json | jq '.[] | select(.framework == "SwiftUI")'
```

### Filter + markdown
```bash
cupertino list-samples --framework swiftui --format markdown
```

## Notes

- Output is sorted by project name.
- All three formats include the same fields per project: id, title, framework, file count, deployment targets.
