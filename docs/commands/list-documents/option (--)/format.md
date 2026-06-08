# --format

Output format for the document page.

## Synopsis

```bash
cupertino list-documents --framework swiftui --format json
```

## Values

| Format | Description |
|--------|-------------|
| `json` | Structured page object with `source`, `framework`, `offset`, `limit`, `total`, and `documents` (default) |
| `text` | Human-readable list |
| `markdown`, `md` | Markdown table |

## Default

`json`
