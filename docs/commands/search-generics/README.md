# `cupertino search-generics`

CLI sibling of the `search_generics` MCP tool. Returns symbols whose generic-parameter list includes a queried constraint.

Added in: v1.2.x (#948 phase 5).

## Synopsis

```
cupertino search-generics --constraint <name>
                           [--framework <name>]
                           [--limit <n>]
                           [--format text|json|markdown|md]
                           [--base-dir <path>] [--source <id>]
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--constraint` | string | required | Generic-constraint type (e.g. `View`, `Hashable`, `Sendable`, `Codable`). |
| `--framework` | string | none | Restrict to a single framework. |
| `--limit` | int | 10 | Maximum results. |
| `--format` | enum | `text` | Output format: `text`, `json`, `markdown`, `md`. |
| `--base-dir` | string | base directory | Directory holding the per-source DBs (the folder `save` / `setup` operate on; defaults to the configured base directory). |
| `--source` | string | all symbol-bearing sources | Restrict to one source id (`apple-docs`, `swift-org`, `swift-book`). |

## Examples

```sh
cupertino search-generics --constraint View
cupertino search-generics --constraint Hashable --framework swift
cupertino search-generics --constraint Sendable --format json | jq '.results[0]'
```

## Matches

The `generic_constraints` column is populated at index time by the AST extractor (#755 / #759) and includes both inline `<T: Foo>` and where-clause `where T: Foo` forms.

## See also

- [`cupertino search-conformances`](../search-conformances/README.md): related; finds symbols that conform to a protocol (not the same as having it as a generic constraint).
- `search_generics` MCP tool (same parameter set, MCP-stdio surface).
