# --query

Substring to match against the symbol name (case-insensitive).

## Synopsis

```bash
cupertino search-symbols --query <substring>
```

## Description

Matches symbols whose name contains the given substring, case-insensitively. Omit
`--query` to run a kind-only or `--is-async`-only query.

## Default

None (when omitted, results are filtered by `--kind` / `--is-async` alone).

## Example

```bash
cupertino search-symbols --query Task
cupertino search-symbols --query View --kind protocol
```
