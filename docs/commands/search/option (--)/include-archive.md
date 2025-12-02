# --include-archive

Include Apple Archive legacy programming guides in search results

## Synopsis

```bash
cupertino search <query> --include-archive
```

## Description

By default, Apple Archive legacy programming guides are excluded from search results to prioritize modern documentation. Use this flag to include them in mixed results alongside other documentation sources.

## Default

`false` (archive excluded)

## Examples

### Include Archive in Search
```bash
cupertino search "Core Animation" --include-archive
```

### Search All Sources Including Archive
```bash
cupertino search "layer" --include-archive --limit 20
```

### Framework-Specific with Archive
```bash
cupertino search "CALayer" --include-archive --framework quartzcore
```

## Combining with Other Options

### With Framework Filter
```bash
cupertino search "bezier" --include-archive --framework coregraphics
```

### With JSON Output
```bash
cupertino search "animation timing" --include-archive --format json
```

### With Limit
```bash
cupertino search "graphics context" --include-archive --limit 10
```

## Comparison

| Approach | Behavior |
|----------|----------|
| No flag | Archive excluded, modern docs only |
| `--include-archive` | Archive included in mixed results |
| `--source apple-archive` | Archive only, no other sources |

## Use Cases

- **Foundational concepts**: Archive guides explain "why" not just "what"
- **Legacy API research**: Understanding older APIs still in use
- **Deep dives**: When modern docs lack conceptual depth
- **Historical context**: Understanding API evolution

## Archive Content

Includes these programming guides:
- Core Animation Programming Guide
- Quartz 2D Programming Guide
- Core Text Programming Guide
- Core Image Programming Guide
- Core Audio Overview
- Cocoa Fundamentals Guide

## Search Ranking

When included, archive results have a slight ranking penalty to ensure modern documentation appears first. Use `--source apple-archive` if you specifically want archive results prioritized.

## Notes

- Archive docs are crawled separately via `cupertino fetch --type archive`
- Framework synonyms help discover archive content (QuartzCore = CoreAnimation)
- Great for understanding foundational concepts not covered in modern docs
