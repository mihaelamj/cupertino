# --framework

Restrict results to a single framework.

## Synopsis

```bash
cupertino search-concurrency --pattern <pattern> --framework <name>
```

## Description

Limits the search to symbols whose owning framework matches the given name
(case-insensitive), e.g. `swiftui`, `uikit`, `foundation`, `combine`.

## Default

None (search every framework in the selected sources).

## Example

```bash
cupertino search-concurrency --pattern actor --framework foundation
```
