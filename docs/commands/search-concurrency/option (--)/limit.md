# --limit

Maximum number of results to return.

## Synopsis

```bash
cupertino search-concurrency --pattern <pattern> --limit <n>
```

## Description

Caps the number of matched symbols printed. Results are returned in the command's
ranked order, so `--limit` keeps the top-ranked matches and drops the tail.

## Default

`20`

## Example

```bash
cupertino search-concurrency --pattern actor --limit 5
cupertino search-concurrency --pattern actor --limit 100
```
