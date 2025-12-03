# list-samples

List indexed Apple sample code projects.

## Synopsis

```bash
cupertino list-samples [--framework <name>] [--limit <n>] [--format <format>] [--sample-db <path>]
```

## Description

Lists all sample code projects that have been indexed. Shows project titles, IDs, frameworks, and file counts.

## Options

### --framework, -f

Filter by framework (e.g., swiftui, uikit, appkit).

### --limit

Maximum number of results to return. Defaults to 50.

### --format

Output format: `text` (default), `json`, or `markdown`.

### --sample-db

Path to sample index database. Defaults to `~/.cupertino/sample-index.sqlite`.

## Examples

```bash
# List all projects
cupertino list-samples

# Filter by framework
cupertino list-samples --framework swiftui

# Limit results
cupertino list-samples --limit 10

# Output as JSON
cupertino list-samples --format json
```

## Sample Output

```
Sample Code Projects
Total: 606 projects, 18497 files

[1] Building a great Mac app with SwiftUI
    ID: swiftui-building-a-great-mac-app-with-swiftui
    Frameworks: swiftui
    Files: 111

[2] Fruta: Building a Feature-Rich App with SwiftUI
    ID: fruta-building-a-feature-rich-app-with-swiftui
    Frameworks: swiftui, widgetkit
    Files: 45
```

## See Also

- [search-samples](../search-samples/) - Search sample code
- [read-sample](../read-sample/) - Read project README
- [index](../index/) - Index sample code
