# --save

Run the `cupertino save` preflight check only — read-only health summary

## Synopsis

```bash
cupertino doctor --save
```

## Description

Short-circuits the regular doctor health suite and prints the same per-scope summary `cupertino save` shows before any DB write — which source dirs are present, how many packages have `availability.json` sidecars, whether the docs corpus has been annotated by `fetch --type availability`. Read-only, no DB writes. ([#232](https://github.com/mihaelamj/cupertino/issues/232))

Use this to ask "is save ready?" without committing to a run.

## Default

`false` (runs the full health check)

## Example

```bash
cupertino doctor --save
```

Sample output:

```
🔍 `cupertino save` preflight check

  Docs (search.db)
    ✓  /Users/me/.cupertino/docs  (404969 entries)
    ✓  Availability annotation present

  Packages (packages.db)
    ✓  /Users/me/.cupertino/packages  (183 packages)
    ✓  availability.json sidecars  (183/183)

  Samples (samples.db)
    ✓  /Users/me/.cupertino/sample-code  (627 zips)
    (annotation runs inline during save — no preflight check needed)
```

## Notes

- Identical output to the preflight summary `cupertino save` prints before its confirmation prompt.
- Backed by `Indexer.Preflight.preflightLines(...)` (lifted to the `Indexer` package in #244).
- Doesn't open any DB; only inspects on-disk files.
