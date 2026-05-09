# --format

Output format for the source file content

## Synopsis

```bash
cupertino read-sample-file <project-id> <file-path> --format <format>
```

## Description

Controls how the source-file content is rendered.

## Values

| Format | Description |
|--------|-------------|
| `text` | Raw content, plain text with a header (`// File:`, `// Project:`, `// Size:`) followed by the body (default) |
| `json` | Structured JSON object: `{ projectId, path, filename, content }` |
| `markdown` | Markdown rendering with a fenced code block typed by file extension |

## Default

`text`

## Examples

### Default text output
```bash
cupertino read-sample-file building-a-document-based-app-with-swiftui ContentView.swift
```

### JSON for programmatic consumers
```bash
cupertino read-sample-file <project-id> Package.swift --format json | jq '.content'
```

JSON fields:

- `projectId` (string) — sample slug
- `path` (string) — relative path within the project
- `filename` (string) — basename of `path`
- `content` (string) — full file body, plain text

### Markdown for embedding
```bash
cupertino read-sample-file <project-id> ContentView.swift --format markdown
```

## Notes

- The `markdown` format guesses the fence language from the file extension (`.swift` → ```` ```swift ````, `.m` → ```` ```objc ````, etc.).
- `content` is always emitted as a plain string; there is no base64 path for binary content. If the file contains non-UTF-8 bytes the JSON encoder will fail before output, so this command is intended for text source files.
