# --direction

Which way to walk the inheritance chain.

## Synopsis

```bash
cupertino inheritance <symbol> --direction <up|down|both>
```

## Description

Selects the walk direction from the start symbol over the `inheritance` edge table
(populated at index time from Apple's DocC `relationshipsSections`).

## Values

| Value | Walk |
|---|---|
| `up` | Ancestors only (`UIButton` to `UIControl` to `UIView` to ...). Default. |
| `down` | Descendants only (`UIControl` to `UIButton` / `UISwitch` / ...). |
| `both` | Both directions from the start node. |

## Default

`up`

## Example

```bash
cupertino inheritance UIButton                    # ancestors (default)
cupertino inheritance UIControl --direction down  # descendants
cupertino inheritance UIView --direction both --depth 1
```
