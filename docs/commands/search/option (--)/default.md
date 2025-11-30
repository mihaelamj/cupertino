# Default Options Behavior

When no options are specified for `search` command

## Synopsis

```bash
cupertino search <query>
```

## Default Behavior

When you run `cupertino search` with just a query and no options, it uses these defaults:

```bash
cupertino search "your query" \
  --search-db ~/.cupertino/search.db \
  --limit 20 \
  --format text
```

## Default Option Values

| Option | Default Value | Description |
|--------|---------------|-------------|
| `--search-db` | `~/.cupertino/search.db` | Search database path |
| `--source` | (all) | Search all sources |
| `--framework` | (all) | Search all frameworks |
| `--limit` | `20` | Maximum results returned |
| `--format` | `text` | Output format |
| `--verbose` | `false` | Compact output |

## Search Behavior

The search command will:

1. **Load database** - Connect to SQLite FTS5 database
2. **Parse query** - Prepare full-text search query
3. **Execute search** - Run BM25-ranked search
4. **Apply filters** - Filter by source/framework if specified
5. **Format output** - Display results in chosen format

## Database Requirements

The search database must exist at the specified path. Create it with:

```bash
cupertino save
```

If the database doesn't exist:
```
Error: Search database not found at /Users/user/.cupertino/search.db
Run 'cupertino save' to build the search index first.
```

## Example Output

### Default Text Output
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

[3] UIView | Apple Developer Documentation
    Source: apple-docs | Framework: uikit
    URI: apple-docs://uikit/documentation_uikit_uiview
...
```

### No Results
```bash
cupertino search "nonexistent"
```

Output:
```
No results found for 'nonexistent'
```

## Common Usage Patterns

### Minimal (All Defaults)
```bash
cupertino search "SwiftUI View"
```

### With Framework Filter
```bash
cupertino search "animation" --framework swiftui
```

### With Source Filter
```bash
cupertino search "async" --source swift-evolution
```

### JSON for AI Agents
```bash
cupertino search "Observable" --format json --limit 5
```

### Full Details
```bash
cupertino search "URLSession" --verbose
```

## Query Syntax

The search query supports:

- **Simple terms**: `View`, `Array`, `URLSession`
- **Multiple terms**: `SwiftUI View animation`
- **Phrases**: Search for related concepts

Examples:
```bash
cupertino search "View"
cupertino search "async await"
cupertino search "Observable macro"
cupertino search "Swift Evolution proposal"
```

## Result Ranking

Results are ranked by BM25 relevance:

1. **Title matches** rank higher than content matches
2. **Multiple occurrences** increase score
3. **Shorter documents** with matches rank higher
4. **Exact matches** rank higher than partial

Use `--verbose` to see relevance scores.

## Notes

- Query is required (first positional argument)
- Empty or whitespace-only queries return an error
- Search is case-insensitive
- Results are always sorted by relevance (highest first)
- Default limit of 20 balances completeness and performance
- Use `--format json` for programmatic processing
- Database path supports tilde (`~`) expansion
