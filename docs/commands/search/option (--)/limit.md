# --limit

Maximum number of search results to return

## Synopsis

```bash
cupertino search <query> --limit <number>
```

## Description

Controls the maximum number of search results returned. In fan-out mode (no `--source`) the cap applies to the post-RRF fused list; in single-source mode it caps the underlying source's result list directly.

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
cupertino search "URLSession" --limit 1
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

### Limit + Per-Source Cap
```bash
cupertino search "async" --limit 5 --per-source 3
```

## Use Cases

- **Quick lookup**: Use `--limit 1` for best match only
- **Exploration**: Use higher limits to discover related APIs
- **Performance**: Lower limits for faster output in scripts
- **AI agents**: JSON output with appropriate limit for context windows

## Notes

- Results are sorted by relevance (highest first).
- The search engine processes all matches but only returns up to the limit.
- In fan-out mode, also see `--per-source` (caps each source's contribution before RRF) — `--limit` is the final cap, `--per-source` is the per-source cap.
- Combine with filters (`--source`, `--framework`) for more targeted results.
- `--limit` has no short alias. (`-l` is the short alias for `--language`.)
