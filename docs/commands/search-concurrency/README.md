# `cupertino search-concurrency`

CLI sibling of the `search_concurrency` MCP tool. Returns symbols that use a Swift concurrency pattern (`async`, `actor`, `sendable`, `mainactor`, `task`).

Added in: v1.2.x (#948 phase 3).

## Synopsis

```
cupertino search-concurrency --pattern <pattern>
                              [--framework <name>]
                              [--limit <n>]
                              [--format text|json|markdown|md]
                              [--base-dir <path>] [--source <id>]
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--pattern` | string | required | Concurrency pattern: `async`, `actor`, `sendable`, `mainactor`, `task`, `asyncsequence`. |
| `--framework` | string | none | Restrict to a single framework. |
| `--limit` | int | 20 | Maximum results. |
| `--format` | enum | `text` | Output format: `text`, `json`, `markdown`, `md`. |
| `--base-dir` | string | base directory | Directory holding the per-source DBs (the folder `save` / `setup` operate on; defaults to the configured base directory). |
| `--source` | string | apple-docs | Restrict to one source id. Only `apple-docs` indexes this signal today. |

## Examples

```sh
cupertino search-concurrency --pattern async
cupertino search-concurrency --pattern actor --framework swiftui
cupertino search-concurrency --pattern mainactor --format json | jq '.results[0]'
```

## See also

- [`cupertino search-property-wrappers`](../search-property-wrappers/README.md): related attribute-based search; `@MainActor` overlap.
- `search_concurrency` MCP tool (same parameter set, MCP-stdio surface).
