# --resume

Resume from checkpoint if interrupted

## Synopsis

```bash
cupertino fetch --type <type> --resume
```

## Description

Resumes a fetch operation from where it left off using the checkpoint file.

## How It Works

1. Reads `checkpoint.json` from output directory
2. Identifies already-fetched items
3. Continues from where fetch stopped
4. Updates checkpoint as it progresses

## Examples

### Resume Package Fetch
```bash
cupertino fetch --type packages --resume
```

### Resume Sample Code Download
```bash
cupertino fetch --type code --authenticate --resume
```

### Resume with Increased Limit
```bash
cupertino fetch --type packages --resume --limit 500
```

## Use Cases

- Network interruption during fetch
- Process was killed or crashed
- Want to fetch more items (increase `--limit`)
- Rate limiting caused early termination

## Requirements

- `checkpoint.json` must exist in output directory
- Must use same `--output-dir` as original fetch
- Works with same or increased `--limit`

## Notes

- Cannot be combined with `--force`
- Automatically skips already-fetched items
- Safe to run multiple times
- Preserves all previous progress
