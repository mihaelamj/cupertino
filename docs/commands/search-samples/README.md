# search-samples

Search Apple sample code projects and files.

## Synopsis

```bash
cupertino search-samples <query> [--framework <name>] [--search-files] [--limit <n>] [--format <format>] [--sample-db <path>]
```

## Description

Searches sample code projects by keyword. Can search project metadata (title, description, README) and optionally file contents.

## Arguments

### query (required)

Search query string.

## Options

### --framework, -f

Filter by framework (e.g., swiftui, uikit, appkit).

### --search-files

Search file contents in addition to project metadata.

### --limit

Maximum number of results to return. Defaults to 20.

### --format

Output format: `text` (default), `json`, or `markdown`.

### --sample-db

Path to sample index database. Defaults to `~/.cupertino/sample-index.sqlite`.

## Examples

```bash
# Search projects
cupertino search-samples "SwiftUI"

# Filter by framework
cupertino search-samples "animation" --framework swiftui

# Include file content search
cupertino search-samples "MainActor" --search-files

# Limit results
cupertino search-samples "camera" --limit 5
```

## Sample Output

```
Search Results for 'SwiftUI'

Projects (3 found):

[1] Building a great Mac app with SwiftUI
    ID: swiftui-building-a-great-mac-app-with-swiftui
    Frameworks: swiftui
    Files: 111
    Create engaging SwiftUI Mac apps...

[2] Building custom views in SwiftUI
    ID: swiftui-building_custom_views_in_swiftui
    Frameworks: swiftui
    Files: 11
```

## See Also

- [list-samples](../list-samples/) - List all projects
- [read-sample](../read-sample/) - Read project README
- [read-sample-file](../read-sample-file/) - Read source file
