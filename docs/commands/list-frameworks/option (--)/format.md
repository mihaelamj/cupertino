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
| `text` | Human-readable list — `Available Frameworks (N total, M documents):` header followed by `  framework: count documents` rows (default) |
| `json` | Bare array `[ { "name": "...", "documentCount": N }, ... ]`, sorted by `documentCount` descending |
| `markdown` | Markdown table with `Framework | Documents` columns |

## Default

`text`

## Examples

### Default text output
```bash
cupertino list-frameworks
```

Output:
```
Available Frameworks (261 total, 405000 documents):

  swiftui: 6500 documents
  foundation: 4200 documents
  uikit: 3800 documents
  ...
```

### JSON for programmatic consumers
```bash
cupertino list-frameworks --format json | jq '.[] | select(.documentCount > 100)'
```

(Top-level is a bare array; per-entry key is `documentCount`, not `count`.)

### Markdown for embedding in docs
```bash
cupertino list-frameworks --format markdown
```

## Notes

- All three formats list the same frameworks in the same order (descending document count).
- JSON top-level is a bare array — iterate as `.[]`.
- Per-entry JSON fields: `name` (string), `documentCount` (int).
