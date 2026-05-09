# --limit

Maximum number of chunks to return

## Synopsis

```bash
cupertino package-search <question> --limit <number>
```

## Description

Cap the number of result chunks emitted. `package-search` returns chunked excerpts ranked by smart-query scoring (intent classification + bm25 + RRF) — `--limit` controls the depth, not the breadth.

## Default

`3`

## Examples

### Default (3 chunks)
```bash
cupertino package-search "Vapor request middleware"
```

### Top 10 chunks
```bash
cupertino package-search "Vapor request middleware" --limit 10
```

### Single most-relevant chunk
```bash
cupertino package-search "Vapor request middleware" --limit 1
```

## Notes

- Chunks come from `package_files_fts` rows — typically a function or a few-line snippet of source / README.
- Each chunk includes the package, file path, and a `▶ Read full:` hint.
