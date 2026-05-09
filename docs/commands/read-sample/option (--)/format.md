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
| `text` | Human-readable plain text — title underline, project facts, README body, file listing (default) |
| `json` | Structured JSON object: `{ id, title, description, frameworks, readme, webURL, fileCount, totalSize, files }` |
| `markdown` | Markdown rendering with H1 title, `## Description`, `## Metadata` bullet block, `## README`, `## Files` |

## Default

`text`

## Examples

### Default text output
```bash
cupertino read-sample building-a-document-based-app-with-swiftui
```

### JSON for programmatic consumers
```bash
cupertino read-sample building-a-document-based-app-with-swiftui --format json | jq '.frameworks'
```

(Per-project JSON fields: `id`, `title`, `description`, `frameworks` (string array), `readme` (string?), `webURL` (string), `fileCount` (int), `totalSize` (bytes int), `files` (array of relative paths). There is no `deploymentTargets` field.)

### Markdown to a file
```bash
cupertino read-sample building-a-document-based-app-with-swiftui --format markdown > sample.md
```

## Notes

- Markdown uses an H1 title plus `## Metadata` bullet list (frameworks / files / size / Apple Developer URL); not YAML front matter.
- `--format` controls only the rendering; the data is the same in all three formats.
- Use `cupertino list-samples` to find valid `<project-id>` values.
