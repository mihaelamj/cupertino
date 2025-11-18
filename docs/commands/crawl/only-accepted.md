# --only-accepted

Only download accepted/implemented proposals (evolution type only)

## Synopsis

```bash
cupertino crawl --type evolution --only-accepted
```

## Description

When crawling Swift Evolution proposals (`--type evolution`), only downloads proposals with status "Accepted" or "Implemented". Skips all other statuses.

## Applies To

Only works with `--type evolution`. Ignored for other types.

## Proposal Statuses

### Downloaded with --only-accepted
- ✅ Accepted
- ✅ Implemented

### Skipped with --only-accepted
- ❌ Rejected
- ❌ Withdrawn
- ❌ Under Review
- ❌ Awaiting Review
- ❌ Returned for Revision

## Examples

### Download Only Accepted Proposals
```bash
cupertino crawl --type evolution --only-accepted
```

### Download All Proposals (Default)
```bash
cupertino crawl --type evolution
```

### Accepted Proposals with Limit
```bash
cupertino crawl --type evolution --only-accepted --max-pages 100
```

## Use Cases

- Focus on finalized language features
- Reduce crawl time and storage
- Study only implemented proposals
- Ignore rejected or pending proposals

## Notes

- Significantly reduces number of downloaded proposals
- Speeds up crawl time
- Status is determined from proposal metadata
- Can be combined with other options like `--max-pages`
