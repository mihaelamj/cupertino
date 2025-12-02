# apple-archive

Apple Archive legacy programming guides source

## Synopsis

```bash
cupertino search <query> --source apple-archive
```

## Description

Filters search results to only include Apple Archive legacy programming guides. These are pre-2016 guides from developer.apple.com/library/archive that contain foundational knowledge not available in modern documentation.

## Content

- **Core Animation Programming Guide** (QuartzCore framework)
- **Quartz 2D Programming Guide** (CoreGraphics framework)
- **Core Text Programming Guide** (CoreText framework)
- **Core Image Programming Guide** (CoreImage framework)
- **Core Audio Overview** (CoreAudio framework)
- **Cocoa Fundamentals Guide** (Cocoa framework)

## Typical Size

- **~75 pages** across 8 guides
- **~5-10 MB** on disk

## Examples

### Search Archive Only
```bash
cupertino search "CALayer" --source apple-archive
```

### Search Core Animation Concepts
```bash
cupertino search "layer tree" --source apple-archive
```

### JSON Output
```bash
cupertino search "bezier path" --source apple-archive --format json
```

## URI Format

Results use the `apple-archive://` URI scheme:

```
apple-archive://{guide_id}/{chapter}
```

Examples:
- `apple-archive://TP40004514/CoreAnimationBasics`
- `apple-archive://TP30001066/dq_context`

## Framework Synonyms

Archive docs are indexed with framework synonyms for better discoverability:
- `QuartzCore` also matches `CoreAnimation`
- `CoreGraphics` also matches `Quartz2D`

## How to Populate

```bash
# Fetch archive guides (~5-10 minutes)
cupertino fetch --type archive

# Build index
cupertino save
```

## Search Ranking

Archive documentation has a slight ranking penalty compared to modern documentation. This ensures modern APIs appear first, while archive content remains discoverable for foundational concepts.

## Notes

- Excluded from default search results
- Use `--source apple-archive` to search archive only
- Use `--include-archive` to include in mixed results
- Contains deep conceptual knowledge often missing from modern docs
- Great for understanding the "why" behind Apple frameworks
