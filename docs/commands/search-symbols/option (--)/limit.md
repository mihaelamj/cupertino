# --limit

Maximum number of results to return.

## Synopsis

```bash
cupertino search-symbols --query <substring> --kind <kind> --limit <n>
```

## Description

Caps the number of matched symbols printed. Results are returned in the command's
ranked order, so `--limit` keeps the top-ranked matches and drops the tail.

## Default

`20`

## Example

```bash
cupertino search-symbols --query Task --kind struct --limit 5
cupertino search-symbols --query Task --kind struct --limit 100
```
