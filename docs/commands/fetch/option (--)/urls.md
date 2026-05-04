# --urls

Path to a text file containing one URL per line; enqueue each at depth 0

## Synopsis

```bash
cupertino fetch --type docs --urls <path>
```

## Description

Each URL in the file is enqueued at depth 0; the crawler then follows links from each up to `--max-depth`. Combine with `--max-depth 0` to fetch the listed URLs with no descent. Useful for fetching a fixed list (URLs another corpus has but this one is missing) without re-spidering everything. Lines starting with `#` and blank lines are ignored. ([#210](https://github.com/mihaelamj/cupertino/issues/210))

## Default

None

## Example

```bash
# Fetch only the listed URLs, no descent:
cupertino fetch --type docs --urls missing-urls.txt --max-depth 0

# Fetch + follow up to 3 levels:
cupertino fetch --type docs --urls seeds.txt --max-depth 3
```

## File format

```
# Comments and blank lines are ignored.
https://developer.apple.com/documentation/swiftui/view
https://developer.apple.com/documentation/swiftui/text

https://developer.apple.com/documentation/foundation/url
```

## Notes

- Lifted to `Ingest.Session.enqueueURLsFromFile` in #247 sub-PR 4a.
- Each line is validated against `URL(string:)` + scheme presence; bad lines fail the run with `Ingest.FetchURLsError.invalidURL`.
- Initialises `crawlState` if missing — works against a fresh corpus too.
