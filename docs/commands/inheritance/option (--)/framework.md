# --framework

Disambiguate to a specific framework when the symbol exists in more than one.

## Synopsis

```bash
cupertino inheritance <symbol> --framework <name>
```

## Description

Some class names appear in multiple frameworks. When the start symbol is ambiguous,
the command prints a disambiguation list; pass `--framework` to pin the walk to one
framework (case-insensitive), e.g. `uikit`, `appkit`, `foundation`.

## Default

None (when the symbol is ambiguous and no framework is given, a disambiguation
list is printed instead of a walk).

## Example

```bash
cupertino inheritance Color --framework swiftui
cupertino inheritance UIButton --framework uikit
```
