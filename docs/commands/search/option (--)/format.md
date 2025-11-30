# --format

Output format for search results

## Synopsis

```bash
cupertino search <query> --format <format>
```

## Description

Controls how search results are formatted in the output. Different formats are suited for different use cases.

## Values

| Format | Description |
|--------|-------------|
| `text` | Human-readable text output (default) |
| `json` | Machine-readable JSON array |
| `markdown` | Formatted markdown |

## Default

`text`

## Examples

### Text Output (Default)
```bash
cupertino search "View"
```

Output:
```
Found 20 result(s) for 'View':

[1] View | Apple Developer Documentation
    Source: apple-docs | Framework: swiftui
    URI: apple-docs://swiftui/documentation_swiftui_view

[2] ViewBuilder | Apple Developer Documentation
    Source: apple-docs | Framework: swiftui
    URI: apple-docs://swiftui/documentation_swiftui_viewbuilder
```

### JSON Output
```bash
cupertino search "View" --format json --limit 2
```

Output:
```json
[
  {
    "filePath": "/Users/user/.cupertino/docs/swiftui/documentation_swiftui_view.md",
    "framework": "swiftui",
    "score": 15.23,
    "source": "apple-docs",
    "summary": "A type that represents part of your app's user interface.",
    "title": "View | Apple Developer Documentation",
    "uri": "apple-docs://swiftui/documentation_swiftui_view",
    "wordCount": 2345
  }
]
```

### Markdown Output
```bash
cupertino search "View" --format markdown --limit 2
```

Output:
```markdown
# Search Results for 'View'

Found 2 result(s).

## 1. View | Apple Developer Documentation

- **Source:** apple-docs
- **Framework:** swiftui
- **URI:** `apple-docs://swiftui/documentation_swiftui_view`
```

## Use Cases

### Text Format
- Interactive terminal use
- Quick lookups
- Human reading

### JSON Format
- AI agent integration
- Script automation
- Piping to `jq` or other tools
- Programmatic processing

### Markdown Format
- Documentation generation
- Copy-paste to notes
- Report creation
- README updates

## Combining with Verbose

The `--verbose` flag adds extra fields to all formats:

```bash
cupertino search "View" --format json --verbose
```

Adds: `summary`, `score`, `wordCount` to output.

## Notes

- JSON output is always valid JSON (array of objects)
- Markdown uses GitHub-flavored markdown
- Text format includes color on supported terminals
- All formats respect `--limit` option
