# Default Options Behavior

When no options are specified for `search` command

## Synopsis

```bash
cupertino search <query>
```

## Default Behavior

`cupertino search <query>` with no other flags runs in **fan-out mode** — every available DB participates and the per-source candidate lists are merged with reciprocal-rank fusion (`k = 60`, source-weighted) into one chunked result list.

Equivalent to:

```bash
cupertino search "your query" \
  --source all \
  --search-db ~/.cupertino/search.db \
  --packages-db ~/.cupertino/packages.db \
  --sample-db ~/.cupertino/samples.db \
  --limit 20 \
  --per-source 10 \
  --format text
```

## Default Option Values

| Option | Default | Description |
|--------|---------|-------------|
| `--source` | (omitted → fan-out) | Source filter; omitted means fan-out across every available DB |
| `--limit` | `20` | Maximum results returned |
| `--per-source` | `10` | Per-source candidate cap before RRF (fan-out only) |
| `--format` | `text` | Output format (text / json / markdown) |
| `--search-db` | `~/.cupertino/search.db` | apple-docs / hig / archive / evolution / swift-org / swift-book |
| `--packages-db` | `~/.cupertino/packages.db` | packages source |
| `--sample-db` | `~/.cupertino/samples.db` | samples source |
| `--include-archive` | `false` | Apple Archive excluded from fan-out unless on |
| `--skip-docs` | `false` | Fan-out only |
| `--skip-packages` | `false` | Fan-out only |
| `--skip-samples` | `false` | Fan-out only |
| `--brief` | `false` | Trim each excerpt to its first few lines |
| `--framework` / `-f` | (none) | Optional framework filter |
| `--language` / `-l` | (none) | swift / objc filter |
| `--platform` | (none) | Filter packages + samples + apple-docs by platform compat |
| `--min-version` | (none) | Required companion to `--platform` |
| `--min-ios` / `--min-macos` / `--min-tvos` / `--min-watchos` / `--min-visionos` | (none) | Per-platform availability floors |

## Search Behavior

In fan-out mode the command will:

1. **Open every available DB** — search.db, packages.db, samples.db (skipped per `--skip-*`).
2. **Detect query intent** — symbol-shaped queries (`Task`, `View`) prune the fan-out to the symbol-bearing sources.
3. **Per-source query** — each source returns up to `--per-source` candidates with its own ranker (BM25F + heuristics on the docs side, FTS5 on packages / samples).
4. **RRF fusion** — `weight[source] / (k + rank)` with `k = 60`. apple-docs 3.0, evolution / packages 1.5, swift-book / swift-org 1.0, archive / hig 0.5.
5. **Render** — chunked excerpts in the configured `--format`, capped at `--limit`.

In single-source mode (`--source <name>` set), step 1 narrows to that DB and step 4 is skipped — the source's native ranking is the final order.

## Database Requirements

At least one of `search.db`, `packages.db`, or `samples.db` must exist for the command to produce results. Missing DBs are skipped with an info-level log; missing all three exits with an error message.

```bash
cupertino save           # populate search.db (apple-docs / evolution / archive / org / book / HIG)
cupertino save --packages   # populate packages.db
cupertino save --samples    # populate samples.db
```

## Example Output

### Default fan-out, text format
```bash
cupertino search "View"
```

Output (abbreviated):
```
🔍 cupertino search "View"

[apple-docs] View
   apple-docs://swiftui/documentation_swiftui_view
   A type that represents part of your app's user interface…
   ▶ Read full: cupertino read apple-docs://swiftui/documentation_swiftui_view

[swift-evolution] SE-0250 — Swift Package Manager Resources
   …
```

### No results
```bash
cupertino search "nonexistent_token_42"
```

Output:
```
No results.
```

## Common Usage Patterns

### Minimal (all defaults)
```bash
cupertino search "SwiftUI View"
```

### With framework filter
```bash
cupertino search "animation" --framework swiftui
```

### Pin to one source
```bash
cupertino search "async" --source swift-evolution
```

### JSON for AI agents
```bash
cupertino search "Observable" --format json --limit 5
```

### Brief mode for quick triage
```bash
cupertino search "URLSession" --brief
```

## Query Syntax

The search query supports:

- **Simple terms**: `View`, `Array`, `URLSession`
- **Multi-token**: `SwiftUI View animation`
- **Source prefix shortcut**: `cupertino search "swift-evolution actors"` is equivalent to `--source swift-evolution actors` (the prefix is stripped before FTS).

Symbol-shaped queries (single token, ≥2 chars, ASCII identifier, leading uppercase) skip the prose-ranker path and route to symbol-bearing sources only.

## Notes

- Query is required (first positional argument).
- Empty or whitespace-only queries return an error.
- Search is case-insensitive.
- In fan-out mode, results are RRF-fused, not BM25-ranked at the top level.
- Default `--limit 20` balances completeness and output size; raise it for exploration, lower for scripts.
- Database paths support tilde (`~`) expansion.
