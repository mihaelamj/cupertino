# --limit, -l

Maximum number of search results to return

## Synopsis

```bash
cupertino search <query> --limit <number>
cupertino search <query> -l <number>
```

## Description

Controls the maximum number of search results returned. Results are ranked by BM25 relevance score, so limiting returns the most relevant matches.

## Default

`20`

## Examples

### Get Top 5 Results
```bash
cupertino search "View" --limit 5
```

### Get More Results
```bash
cupertino search "SwiftUI" --limit 50
```

### Single Best Match
```bash
cupertino search "URLSession" -l 1
```

### Large Result Set
```bash
cupertino search "documentation" --limit 100
```

## Combining with Other Options

### Limit + Framework
```bash
cupertino search "animation" --framework swiftui --limit 10
```

### Limit + JSON Output
```bash
cupertino search "Observable" --limit 3 --format json
```

### Limit + Verbose
```bash
cupertino search "async" --limit 5 --verbose
```

## Use Cases

- **Quick lookup**: Use `--limit 1` for best match only
- **Exploration**: Use higher limits to discover related APIs
- **Performance**: Lower limits for faster output in scripts
- **AI agents**: JSON output with appropriate limit for context windows

## Notes

- Results are always sorted by relevance (highest first)
- Higher limits may impact output size, especially with `--verbose`
- The search engine processes all matches but only returns up to the limit
- Combine with filters (`--source`, `--framework`) for more targeted results
