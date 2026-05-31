# `cupertino search-conformances`

CLI sibling of the `search_conformances` MCP tool. Returns symbols that conform to a given protocol.

Added in: v1.2.x (#948 phase 4).

## Synopsis

```
cupertino search-conformances --protocol <name>
                               [--framework <name>]
                               [--limit <n>]
                               [--format text|json|markdown|md]
                               [--base-dir <path>] [--source <id>]
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--protocol` | string | required | Protocol name to find conformers of (e.g. `View`, `Codable`, `Hashable`, `Sendable`). |
| `--framework` | string | none | Restrict to a single framework. |
| `--limit` | int | 20 | Maximum results. |
| `--format` | enum | `text` | Output format: `text`, `json`, `markdown`, `md`. |
| `--base-dir` | string | base directory | Directory holding the per-source DBs (the folder `save` / `setup` operate on; defaults to the configured base directory). |
| `--source` | string | apple-docs | Restrict to one source id. Only `apple-docs` indexes this signal today. |

## Examples

```sh
cupertino search-conformances --protocol View
cupertino search-conformances --protocol Codable --framework foundation
cupertino search-conformances --protocol Sendable --format json | jq '.results[0]'
```

## See also

- [`cupertino search-generics`](../search-generics/README.md): related; finds symbols whose generic-parameter list includes a constraint.
- `search_conformances` MCP tool (same parameter set, MCP-stdio surface).
