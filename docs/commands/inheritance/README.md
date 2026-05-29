# `cupertino inheritance`

Walk class inheritance chains for Apple class-based APIs. Mirrors the `get_inheritance` MCP tool.

Walks the `inheritance` edge table populated at index time from Apple's DocC `relationshipsSections`. Useful for UIKit / AppKit / Foundation class hierarchies. SwiftUI structs / enums / protocols have no inheritance edges and return "no inheritance data" (value types do not inherit in Swift).

## Synopsis

```
cupertino inheritance <symbol> [--direction up|down|both] [--depth <n>]
                      [--framework <name>] [--format text|json|markdown]
                      [--search-db <path>]
```

## Arguments

| Argument | Description |
|---|---|
| `<symbol>` | Symbol name to walk from (e.g. `UIButton`, `NSView`). |

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `--direction` | enum | `up` | Walk direction: `up` (ancestors), `down` (descendants), `both`. |
| `--depth` | int | 5 | Maximum walk depth. |
| `--framework` | string | none | Disambiguate to a specific framework when the symbol exists in multiple. |
| `--format` | enum | `text` | Output format: `text`, `json`, `markdown`. |
| `--search-db` | path | registry default | Override the apple-docs database path (post-#1037 per-source DB split). |

## Directions

- `up`: ancestors only (`UIButton` to `UIControl` to `UIView` to ...).
- `down`: descendants only (`UIControl` to `UIButton` / `UISwitch` / ...).
- `both`: both directions from the start node.

## Examples

```sh
cupertino inheritance UIButton                      # walk up by default
cupertino inheritance UIControl --direction down    # walk down
cupertino inheritance UIView --direction both --depth 1
cupertino inheritance Color                         # ambiguous: prints a disambiguation list
```
