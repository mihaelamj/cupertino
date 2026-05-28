# `cupertino search-symbols`

Search the AST symbol index built into the cupertino bundle. Mirrors the `search_symbols` MCP tool with the same parameter set + an explicit `--format` flag for shell pipelines.

Added in: v1.2.x (#948).

## Synopsis

```
cupertino search-symbols [--query <substring>] [--kind <kind>]
                         [--is-async] [--framework <name>]
                         [--limit <n>] [--format text|json|markdown|md]
                         [--search-db <path>]
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--query` | string | none | Substring to match against the symbol name (case-insensitive). Omit for kind-only / async-only queries. |
| `--kind` | string | none | Restrict to a single kind: `class`, `struct`, `enum`, `protocol`, `actor`, `typealias`, `macro`, `method`, `function`, `property`, `initializer`, `subscript`, `case`, `operator`. |
| `--is-async` | flag | false | Only match symbols marked `async`. |
| `--framework` | string | none | Restrict to a single framework (e.g. `swiftui`, `uikit`, `foundation`). |
| `--limit` | int | 10 | Maximum results. |
| `--format` | enum | `text` | Output format: `text`, `json`, `markdown`, `md`. |
`~/.cupertino/apple-documentation.db` | Override the apple-docs database (post-#1037 per-source DB split). Default resolves through the production source registry. |

## Examples

```sh
cupertino search-symbols --query Task --kind struct
cupertino search-symbols --kind protocol --framework swiftui
cupertino search-symbols --is-async --limit 20
cupertino search-symbols --query View --kind protocol --format json | jq '.results[0]'
```

## Ranking

Inherits the shared AST `signalRankOrderClause` (#177) plus the `#670` exact-name boost:

1. Operator-overload + auto-synthesised symbol names ranked last.
2. Canonical kinds (class / struct / enum / protocol / actor) ranked above type-shape sub-kinds (typealias / macro), member-shape (method / property / initializer), and `kind=operator`.
3. Rows whose `LOWER(name) = LOWER(query)` win their kind tier when a `--query` was passed (e.g. `Task` struct beats `AVAggregateAssetDownloadTask` class).
4. Alphabetic `name` resolves remaining ties.

## See also

- [`cupertino search`](../search/README.md): full-text search across all 8 sources, returns documents (not symbols).
- `search_symbols` MCP tool (same parameter set, MCP-stdio surface).
- [`docs/audits/eval-harness-standard-v1.0.md`](../../audits/eval-harness-standard-v1.0.md): Phase 2 query battery covering all 5 AST tools.
