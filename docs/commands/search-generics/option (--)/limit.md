# --limit

Maximum number of results to return.

## Synopsis

```bash
cupertino search-generics --constraint <type> --limit <n>
```

## Description

Caps the number of matched symbols printed. Results are returned in the command's
ranked order, so `--limit` keeps the top-ranked matches and drops the tail.

## Default

`20`

## Example

```bash
cupertino search-generics --constraint Hashable --limit 5
cupertino search-generics --constraint Hashable --limit 100
```
