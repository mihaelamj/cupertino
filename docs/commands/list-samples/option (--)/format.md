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
| `json` | Top-level object: `{ totalProjects, totalFiles, framework, projects: [...] }` |
| `markdown` | Markdown table with `Project | Frameworks | Files` columns |

## Default

`text`

## Examples

### Default text output
```bash
cupertino list-samples
```

### JSON for programmatic consumers
```bash
cupertino list-samples --format json | jq '.projects[] | select(.frameworks | index("swiftui"))'
```

(Top-level is an object — iterate `.projects[]`. Per-project field is `frameworks` (array, lowercase values), not `framework` singular.)

### Filter + markdown
```bash
cupertino list-samples --framework swiftui --format markdown
```

## Notes

- JSON shape (top-level keys; `framework` only appears when you passed `--framework`):
  ```json
  {
    "totalProjects": 619,
    "totalFiles": 18928,
    "framework": "swiftui",
    "projects": [
      {
        "id": "swiftui-foo",
        "title": "Some SwiftUI Sample",
        "description": "…",
        "frameworks": ["swiftui", "widgetkit"],
        "fileCount": 42
      }
    ]
  }
  ```
- Without `--framework`, the top-level `framework` key is omitted (the encoder drops nil optionals).
- `framework` (top-level, singular) echoes back the `--framework` filter you passed.
- `frameworks` (per-project, plural array) is the sample's actual import set, lowercase.
- Output is sorted by project name.
