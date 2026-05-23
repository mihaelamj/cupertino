# `cupertino search-property-wrappers`

CLI sibling of the `search_property_wrappers` MCP tool. Returns symbols whose declaration uses the queried property wrapper (`@State`, `@Binding`, `@Observable`, `@MainActor`, `@Published`, etc.).

Added in: v1.2.x (#948 phase 2).

## Synopsis

```
cupertino search-property-wrappers --wrapper <name>
                                    [--framework <name>]
                                    [--limit <n>]
                                    [--format text|json|markdown]
                                    [--search-db <path>]
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--wrapper` | string | required | Property wrapper name, with or without `@` (e.g. `State`, `@MainActor`). |
| `--framework` | string | none | Restrict to a single framework (e.g. `swiftui`, `uikit`, `combine`). |
| `--limit` | int | 10 | Maximum results. |
| `--format` | enum | `text` | Output format: `text`, `json`, `markdown`. |
| `--search-db` | path | `~/.cupertino/search.db` | Override the indexed search database. |

## Examples

```sh
cupertino search-property-wrappers --wrapper State
cupertino search-property-wrappers --wrapper "@Observable" --limit 5
cupertino search-property-wrappers --wrapper MainActor --framework uikit
cupertino search-property-wrappers --wrapper Published --format json | jq '.results[0]'
```

## Ranking

Inherits the #952 canonical-framework boost: rows in the wrapper's canonical-usage framework set rank above all others. Examples:

- `@State` / `@Binding` / `@StateObject` / `@ObservedObject` / `@EnvironmentObject` / `@AppStorage` / `@FocusState` / `@GestureState` / `@Namespace` → `[swiftui]`
- `@Observable` → `[swiftui]` (usage-density: 11 SwiftUI vs 1 Observation in v1.2.x corpus)
- `@MainActor` → `[uikit, swiftui, appkit, realitykit]` (declared in Swift std-lib, used across UI frameworks)
- `@Published` → `[swiftui]` (Combine-declared but predominantly used by SwiftUI ViewModels)
- `@Model` / `@Query` → `[swiftui]` (SwiftData-declared but SwiftUI is the predominant integration site)
- `@TaskLocal` / `@GlobalActor` → `[swift]`

Wrappers not in the canonical-framework lookup fall through to the operator-demote + kind-shape tiers of the shared `signalRankOrderClause`.

## See also

- [`cupertino search-symbols`](../search-symbols/README.md): search by name + kind, the most general AST query.
- `search_property_wrappers` MCP tool (same parameter set, MCP-stdio surface).
- [`docs/audits/eval-harness-standard-v1.0.md`](../../audits/eval-harness-standard-v1.0.md): Phase 2 query battery.
