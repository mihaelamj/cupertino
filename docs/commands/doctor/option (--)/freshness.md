# --freshness

Print a per-source freshness / drift report for `search.db` based on `docs_metadata.last_crawled` timestamps.

## Synopsis

```bash
cupertino doctor --freshness
```

## Description

Answers "how stale is my local index?" for users without a `cupertino-docs-private` checkout (which would otherwise let them `git log` the corpus repo to see when Apple's pages last changed). Reads `docs_metadata.last_crawled` (Unix epoch seconds, stamped at indexer save time) and reports per-source quantiles + row count.

Per the [#275](https://github.com/mihaelamj/cupertino/issues/275) design discussion, this flag emits the distribution (oldest / p50 / p90 / newest) rather than a single snapshot timestamp: a long crawl can span days, so a single "bundle was built at X" hides per-page age. p50 + p90 surfaces both typical age and the long-tail.

## Default

`false` — freshness report not run by default. The default doctor surface is binary health (server + DBs + MCP).

## Examples

### Check bundle freshness after `cupertino setup`

```bash
$ cupertino doctor --freshness
📅 Freshness / drift signal (#275)
   source              rows    oldest                p50                   p90                   newest
   apple-docs         285735  2025-11-15    2026-04-22    2026-05-11    2026-05-14
   apple-archive         368  2025-12-01    2025-12-01    2025-12-01    2025-12-01
   hig                   173  2025-12-02    2025-12-02    2025-12-02    2025-12-02
   swift-evolution       483  2025-09-15    2026-02-14    2026-04-30    2026-05-12
   swift-org             115  2026-01-10    2026-03-22    2026-05-08    2026-05-12
```

Read the report as: "for source X, I have N rows; the oldest one was crawled on `oldest`, half are at least as old as `p50`, the slowest 10% are at least as old as `p90`, the newest was crawled on `newest`".

### Combine with other doctor flags

`--freshness` is independent of `--save` and `--kind-coverage`. Any combination is valid:

```bash
cupertino doctor --freshness --kind-coverage --save
```

## Output shape

Header row:

```
   source              rows    oldest                p50                   p90                   newest
```

One row per source, sorted alphabetically by source name:

```
   <source-padded-18>  <count-padded-8>  <YYYY-MM-DD>    <YYYY-MM-DD>    <YYYY-MM-DD>    <YYYY-MM-DD>
```

Quantile rule: nearest-rank (no interpolation) — `p50` and `p90` are always real observations, not synthetic averages. Avoids the `percentile_cont` vs `percentile_disc` ambiguity that bites SQL-side percentile work.

## Notes

- **Read-only**; no DB writes.
- **Doesn't gate the doctor verdict** — purely informational signal.
- Skipped silently when `search.db` is missing or schema-mismatched (the regular `checkSearchDatabase` already surfaced that).
- Rows where `last_crawled == 0` (never stamped) are excluded from the quantile computation so they don't pull the oldest down to epoch 0.
- **No thresholds** — raw ages only. Per [#275](https://github.com/mihaelamj/cupertino/issues/275)'s design discussion, "fresh / aging / stale" labels are deferred so users can set their own thresholds (a v1.2 bundle may be perfectly current for one user and ancient for another, depending on how often they reset).

## See also

- [#275](https://github.com/mihaelamj/cupertino/issues/275) — issue tracking the freshness/drift surface
- [#78](https://github.com/mihaelamj/cupertino/issues/78) — parent ticket (`cupertino stats` content inventory)
- `--kind-coverage` — sibling informational flag (kind distribution audit)
- `--save` — different doctor surface (maintenance health check)
