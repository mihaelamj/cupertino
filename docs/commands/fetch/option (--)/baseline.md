# --baseline

Path to a known-good baseline corpus directory; prepend missing URLs

## Synopsis

```bash
cupertino fetch --type docs --baseline <path>
```

## Description

Path to a prior corpus directory (e.g. `cupertino-docs/docs` snapshot). On startup, URLs present in the baseline but missing from the current crawl's known set (queue ∪ visited ∪ pages) are prepended to the queue at `--max-depth`, so the resumed crawl recovers gaps without re-crawling the whole corpus. Comparison is case-insensitive on the path.

## Default

None (no baseline injection)

## Example

```bash
cupertino fetch --type docs \
  --baseline ~/Developer/cupertino-docs/docs
```

## Notes

- Lifted to `Ingest.Session.requeueFromBaseline` in #247 sub-PR 4a.
- Walks the baseline directory's `.json` files, reads each `url` field, builds a candidate set.
- URLs are queued at `--max-depth` (not 0) so the crawler doesn't re-discover children the baseline already crawled.
- Logs `🩹 --baseline: prepended N missing URL(s) from M-URL baseline at depth D`.
