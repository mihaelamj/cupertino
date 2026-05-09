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
| `text` | Raw file content, plain text (default) |
| `json` | Structured JSON object: project id, file path, language, byte length, content |
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

### Markdown for embedding
```bash
cupertino read-sample-file <project-id> ContentView.swift --format markdown
```

## Notes

- The `markdown` format guesses the fence language from the file extension (`.swift` → ```` ```swift ````, `.m` → ```` ```objc ````, etc.).
- For binary files the result is base64-encoded in JSON mode; text mode prints the raw bytes (terminal may garble).
