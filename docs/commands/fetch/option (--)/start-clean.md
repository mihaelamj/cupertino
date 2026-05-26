# --start-clean

Ignore any saved session and start the fetch fresh from the seed URL.

## Synopsis

```bash
cupertino fetch --source <id> --start-clean
```

## Description

`cupertino fetch` auto-resumes by default. If `metadata.json` (or `checkpoint.json`, for packages) records an active session matching the start URL, the next run picks up from where the previous one left off.

`--start-clean` overrides that: the saved queue + visited-URL state is wiped before the crawl begins, so the run starts from the seed URL with an empty queue. Page files already on disk are **kept**, change detection still skips pages whose content hasn't changed. Combine with `--force` if you also want to re-fetch unchanged pages.

## How It Works

For web crawls (`docs`, `swift`, `evolution`, `archive`, `hig`):

1. Reads `metadata.json` from the output directory.
2. Sets `crawlState = nil` (drops the queue + visited set), preserves everything else (frameworks, stats, page hashes).
3. Atomically writes `metadata.json` back.
4. Crawler boots with no resumable session → starts fresh from the seed URL.

For direct fetches (`packages`, `code`):

1. Disables resume mode in `PackageFetcher` (equivalent to `resume: false`).
2. Re-walks the catalog from the start.

## Examples

### Restart a Botched Apple Docs Crawl
```bash
cupertino fetch --source apple-docs --start-clean
```

### Restart and Re-fetch Every Page
```bash
cupertino fetch --source apple-docs --start-clean --force
```

### Re-walk the Package Catalog from Scratch
```bash
cupertino fetch --source packages --start-clean
```

## When to Use It

- Saved session is corrupt or stale (rare since metadata.json is now atomically written).
- You changed the seed URL or `--allowed-prefixes` and want a clean baseline.
- Debugging crawl coverage and want a deterministic re-run.

## Notes

- Auto-resume is the default. Don't pass `--start-clean` unless you actually want to discard progress.
- Compatible with `--force`. `--start-clean` clears the queue; `--force` re-fetches pages on disk. They address different layers.
- Safe to run on a non-existent metadata.json, logs a no-op message and proceeds.
