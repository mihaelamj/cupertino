# --limit

Maximum number of results to return.

## Synopsis

```bash
cupertino search-property-wrappers --wrapper <name> --limit <n>
```

## Description

Caps the number of matched symbols printed. Results are returned in the command's
ranked order, so `--limit` keeps the top-ranked matches and drops the tail.

## Default

`20`

## Example

```bash
cupertino search-property-wrappers --wrapper State --limit 5
cupertino search-property-wrappers --wrapper State --limit 100
```
