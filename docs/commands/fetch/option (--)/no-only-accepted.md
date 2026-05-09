# --no-only-accepted

Include withdrawn / rejected proposals in the evolution fetch (negation of `--only-accepted`)

## Synopsis

```bash
cupertino fetch --type evolution --no-only-accepted
```

## Description

The default behavior of `cupertino fetch --type evolution` is `--only-accepted` — only proposals in `Accepted`, `Implemented`, `Active review`, or `Awaiting implementation` status are downloaded. `--no-only-accepted` flips that off, including proposals in `Withdrawn`, `Rejected`, `Returned for revision`, and any other status.

Generated automatically by ArgumentParser as the negation of `--only-accepted` (long-form Bool flag pair).

## Default

`--only-accepted` (most users want only the proposals that ship).

## Examples

### Crawl every Swift Evolution proposal regardless of status
```bash
cupertino fetch --type evolution --no-only-accepted
```

### Default (skip withdrawn/rejected)
```bash
cupertino fetch --type evolution
# equivalent to: --only-accepted
```

## Notes

- Only meaningful with `--type evolution`. Ignored otherwise.
- Including non-accepted proposals roughly doubles the corpus size.
- Useful when researching proposal history or building evolution-search tools.
