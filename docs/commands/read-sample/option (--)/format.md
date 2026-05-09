# --format

Output format for the sample-project README + metadata

## Synopsis

```bash
cupertino read-sample <project-id> --format <format>
```

## Description

Controls how the project README and metadata block are rendered.

## Values

| Format | Description |
|--------|-------------|
| `text` | Human-readable plain text — README body + a footer of project facts (default) |
| `json` | Structured JSON object: id, title, framework, deployment targets, README, file count |
| `markdown` | Markdown rendering of the README with a YAML front-matter block of metadata |

## Default

`text`

## Examples

### Default text output
```bash
cupertino read-sample building-a-document-based-app-with-swiftui
```

### JSON for programmatic consumers
```bash
cupertino read-sample building-a-document-based-app-with-swiftui --format json | jq '.deploymentTargets'
```

### Markdown to a file
```bash
cupertino read-sample building-a-document-based-app-with-swiftui --format markdown > sample.md
```

## Notes

- `--format` controls only the output rendering; the data is the same in all three formats.
- Use `cupertino list-samples` first to find valid `<project-id>` values.
