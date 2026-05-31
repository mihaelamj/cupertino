# --depth

Maximum walk depth from the start symbol.

## Synopsis

```bash
cupertino inheritance <symbol> --depth <n>
```

## Description

Bounds how many inheritance edges the walk follows away from the start symbol.
A depth of `1` returns only the immediate parents (or children) of the symbol.

## Default

`5`

## Example

```bash
cupertino inheritance UIView --direction both --depth 1
cupertino inheritance NSView --depth 10
```
