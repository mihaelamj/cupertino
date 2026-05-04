# --retry-errors

Re-queue URLs visited but never saved (post-bug retry)

## Synopsis

```bash
cupertino fetch --type docs --retry-errors
```

## Description

Re-queues URLs that the crawler visited but never wrote to the `pages` dict — typically pages whose save failed (filename too long, write errors, etc.). They get removed from the visited set and prepended to the queue at `--max-depth`, so the resumed crawl retries them without re-discovering their children. Use after a save-bug fix to retry only the affected pages without recrawling the whole corpus.

## Default

`false`

## Example

```bash
# After fixing a save bug:
cupertino fetch --type docs --retry-errors
```

## Notes

- Lifted to `Ingest.Session.requeueErroredURLs` in #247 sub-PR 4a.
- Logs `🔁 --retry-errors: re-queued N errored URL(s) at depth M (front of queue)` so you can see what got retried.
- No-op when no metadata.json or no errored URLs.
