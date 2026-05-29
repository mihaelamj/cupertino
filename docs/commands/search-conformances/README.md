# `cupertino search-conformances`

CLI sibling of the `search_conformances` MCP tool. Returns symbols that conform to a given protocol.

Added in: v1.2.x (#948 phase 4).

## Synopsis

```
cupertino search-conformances --protocol <name>
                               [--framework <name>]
                               [--limit <n>]
                               [--format text|json|markdown|md]
                               [--search-db <path>]
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--protocol` | string | required | Protocol name to find conformers of (e.g. `View`, `Codable`, `Hashable`, `Sendable`). |
| `--framework` | string | none | Restrict to a single framework. |
| `--limit` | int | 10 | Maximum results. |
| `--format` | enum | `text` | Output format: `text`, `json`, `markdown`, `md`. |
`~/.cupertino/apple-documentation.db` | Override the apple-docs database (post-#1037 per-source DB split). Default resolves through the production source registry. |

## Examples

```sh
cupertino search-conformances --protocol View
cupertino search-conformances --protocol Codable --framework foundation
cupertino search-conformances --protocol Sendable --format json | jq '.results[0]'
```

## See also

- [`cupertino search-generics`](../search-generics/README.md): related; finds symbols whose generic-parameter list includes a constraint.
- `search_conformances` MCP tool (same parameter set, MCP-stdio surface).
