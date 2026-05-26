# `cupertino search-concurrency`

CLI sibling of the `search_concurrency` MCP tool. Returns symbols that use a Swift concurrency pattern (`async`, `actor`, `sendable`, `mainactor`, `task`).

Added in: v1.2.x (#948 phase 3).

## Synopsis

```
cupertino search-concurrency --pattern <pattern>
                              [--framework <name>]
                              [--limit <n>]
                              [--format text|json|markdown]
                              [--search-db <path>]
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--pattern` | string | required | Concurrency pattern: `async`, `actor`, `sendable`, `mainactor`, `task`, `asyncsequence`. |
| `--framework` | string | none | Restrict to a single framework. |
| `--limit` | int | 10 | Maximum results. |
| `--format` | enum | `text` | Output format: `text`, `json`, `markdown`. |
`~/.cupertino/apple-documentation.db` | Override the apple-docs database (post-#1037 per-source DB split). Default resolves through the production source registry. |

## Examples

```sh
cupertino search-concurrency --pattern async
cupertino search-concurrency --pattern actor --framework swiftui
cupertino search-concurrency --pattern mainactor --format json | jq '.results[0]'
```

## See also

- [`cupertino search-property-wrappers`](../search-property-wrappers/README.md): related attribute-based search; `@MainActor` overlap.
- `search_concurrency` MCP tool (same parameter set, MCP-stdio surface).
