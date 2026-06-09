# --include-archive

Legacy Apple Archive inclusion flag

## Synopsis

```bash
cupertino search <query> --include-archive
```

## Description

In the current v1.3.0 per-source bundle, default fan-out already opens `apple-archive.db` and includes Apple Archive legacy programming guides as a low-weight source. This flag remains accepted for compatibility with older unified-DB workflows and scripts, but it is no longer required for the normal `cupertino search <query>` fan-out.

## Default

`false`

## Examples

### Include Archive in Search
```bash
cupertino search "Core Animation" --include-archive
```

### Search Archive Only
```bash
cupertino search "layer" --source apple-archive --limit 20
```

### Framework-Specific with Archive
```bash
cupertino search "CALayer" --source apple-archive --framework quartzcore
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
| No flag | Fan-out includes archive as a low-weight source |
| `--include-archive` | Accepted for compatibility; not needed for current fan-out |
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

Archive results have a slight ranking penalty in fan-out to ensure modern documentation appears first. Use `--source apple-archive` if you specifically want archive results prioritized.

## Notes

- Archive docs are crawled separately via `cupertino fetch --source apple-archive`
- Framework synonyms help discover archive content (QuartzCore = CoreAnimation)
- Great for understanding foundational concepts not covered in modern docs
