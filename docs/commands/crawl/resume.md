# --resume

Resume from saved session

## Synopsis

```bash
cupertino crawl --resume
```

## Description

Resumes a crawl from where it left off. Auto-detects the checkpoint from `metadata.json` and continues crawling.

## How It Works

1. Reads `metadata.json` from output directory
2. Identifies already-crawled pages
3. Continues from where the crawl stopped
4. Preserves all progress and content hashes

## Examples

### Resume Interrupted Crawl
```bash
cupertino crawl --resume
```

### Resume with Different Limits
```bash
cupertino crawl --resume --max-pages 20000
```

### Resume Specific Type
```bash
cupertino crawl --type swift --resume
```

## Use Cases

- Network interruption during crawl
- Process was killed or crashed
- Want to continue adding more pages
- Rate limiting caused early termination

## Requirements

- `metadata.json` must exist in output directory
- Must use same `--output-dir` as original crawl
- Works with same or increased `--max-pages` limit

## Notes

- Cannot be combined with `--force`
- Automatically skips already-crawled pages
- Updates metadata as it continues
- Safe to run multiple times
