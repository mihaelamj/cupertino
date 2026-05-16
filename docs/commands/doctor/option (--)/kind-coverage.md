# --kind-coverage

Print a per-source kind distribution audit for `search.db`.

## Synopsis

```bash
cupertino doctor --kind-coverage
```

## Description

Walks `docs_metadata` joined with `docs_structured.kind` and prints a per-source histogram ordered by source name, then by row count descending. Highlights the `unknown` rate per source plus the rate of rows that have no `docs_structured` entry at all (rendered as `(missing)`).

The release-time metric for verifying that indexer-side kind-extraction improvements landed on a bundle. Pre-#633 the apple-docs source carried 57% `kind=unknown`; post-#633 + #664 the rate dropped to single digits.

## Default

`false` — kind-coverage audit not run by default. The default doctor surface is binary health (server + DBs + MCP).

## Examples

### Verify a fresh reindex landed kind improvements

```bash
$ cupertino doctor --kind-coverage
🧩 Kind distribution audit (#626)
   apple-docs — 351495 rows, unknown/missing: 14252 (4.1%)
     property        102456  ( 29.1%)
     method           76368  ( 21.7%)
     article          63158  ( 18.0%)
     enum             24358  (  6.9%)
     function         17002  (  4.8%)
     … and 9 more
   apple-archive — 368 rows, unknown/missing: 368 (100.0%)
     (missing)          368  (100.0%)
   …
```

A `(missing)` rate of 100% indicates the source doesn't emit `docs_structured` data at all (architectural gap, not an extraction bug). A high `unknown` rate inside a populated source indicates the kind extractor missed a roleHeading / symbolKind value worth adding to the cascade.

### Combine with other doctor flags

`--kind-coverage` is independent of `--save`. Both can be set simultaneously:

```bash
cupertino doctor --save --kind-coverage
```

## Output shape

For each source (sorted alphabetically):

1. Header line: `<source> — <total> rows, unknown/missing: <count> (<percent>%)`
2. Up to 5 dominant kinds with count + percent, indented.
3. `… and N more` line when the long tail exceeds 5 kinds.

## Notes

- Read-only; no DB writes.
- Doesn't gate the doctor verdict — purely informational signal.
- Skipped silently when `search.db` is missing or schema-mismatched (the regular `checkSearchDatabase` already surfaced that).
- `(missing)` rows come from sources that don't write a `docs_structured` entry at all (separate problem from `kind=unknown`).

## See also

- `#626` — issue tracking the `kind=unknown` reduction work
- `#615` / `#633` / `#664` — indexer-side fixes whose effect this probe verifies
- `--save` — different doctor surface (maintenance health check)
