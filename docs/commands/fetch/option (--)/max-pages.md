# --max-pages

Cap on number of pages to crawl

## Synopsis

```bash
cupertino fetch --type docs --max-pages <n>
```

## Description

Hard cap on the crawler's queue pull. Once `n` pages have been visited, the crawl exits cleanly with whatever it has.

## Default

`1,000,000` (effectively uncapped — full Apple-corpus crawls are ~50–80k pages).

## Example

```bash
cupertino fetch --type docs --max-pages 5000
```

## Notes

- Pre-1.0 default was `15,000`, which silently truncated full crawls at ~15–30 % coverage; raised to 1M during the v1.0 cleanup.
- For a focused crawl of one framework, set both `--max-pages` and `--start-url`.
