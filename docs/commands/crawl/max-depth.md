# --max-depth

Maximum depth to crawl from start URL

## Synopsis

```bash
cupertino crawl --max-depth <number>
```

## Description

Limits how many links away from the start URL the crawler will go. Depth 0 = start URL only, depth 1 = start URL + direct links, etc.

## Default

`15`

## Examples

### Shallow Crawl (Start URL + Direct Links Only)
```bash
cupertino crawl --max-depth 1
```

### Medium Depth
```bash
cupertino crawl --max-depth 5
```

### Deep Crawl (Default)
```bash
cupertino crawl --max-depth 15
```

## Depth Levels

| Depth | What Gets Crawled |
|-------|------------------|
| 0 | Only the start URL |
| 1 | Start URL + all pages it links to |
| 2 | Depth 1 + all pages those link to |
| 3+ | Continues outward from start URL |

## Notes

- Works in combination with `--max-pages`
- Useful for focused crawling of specific sections
- Prevents crawling the entire site when you only want a subsection
