# --is-async

Only match symbols marked `async`.

## Synopsis

```bash
cupertino search-symbols --is-async
```

## Description

A boolean flag. When present, restricts results to symbols whose declaration is
`async`. Combine with `--kind`, `--framework`, or `--query` to narrow further.

## Default

`false` (do not filter on `async`).

## Example

```bash
cupertino search-symbols --is-async --limit 20
cupertino search-symbols --is-async --kind method --framework foundation
```
