# --framework

Restrict results to a single framework.

## Synopsis

```bash
cupertino search-generics --constraint <type> --framework <name>
```

## Description

Limits the search to symbols whose owning framework matches the given name
(case-insensitive), e.g. `swiftui`, `uikit`, `foundation`, `combine`.

## Default

None (search every framework in the selected sources).

## Example

```bash
cupertino search-generics --constraint Hashable --framework swift
```
