# --max-depth

Maximum link depth to follow from the start URL

## Synopsis

```bash
cupertino fetch --type docs --max-depth <n>
```

## Description

Each newly enqueued URL is tagged with the depth at which it was discovered. The crawler stops following links from a page once `depth >= max-depth`.

## Default

`15`

## Example

```bash
# Shallow crawl: only the seed + direct children
cupertino fetch --type docs --max-depth 1

# Fetch only the URLs in --urls, no descent
cupertino fetch --type docs --urls my-urls.txt --max-depth 0
```

## Notes

- Combine with `--urls` and `--max-depth 0` to fetch a fixed list with no descent — useful for plugging coverage holes from another corpus.
- Depth is stamped on every saved page (`StructuredDocumentationPage.depth`) for later analysis.
