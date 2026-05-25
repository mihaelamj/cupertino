# --source availability

Fetch platform availability data for Apple documentation

## Synopsis

```bash
cupertino fetch --source availability
```

## Description

Fetches platform availability information (minimum iOS, macOS, tvOS, watchOS, visionOS versions) for all Apple documentation. This data is used to enable filtering search results by OS version.

**Important:** Run this before `cupertino save` to ensure sample-code and apple-archive get availability data (they derive it from framework docs).

## Data Source

**Apple Tutorials API** - `https://developer.apple.com/tutorials/data/documentation/{path}.json`

Returns platform metadata for each documentation page including:
- Minimum supported version per platform
- Deprecation status
- Beta status

## Output

Updates existing JSON files in `~/.cupertino/docs/` with an `availability` array:

```json
{
  "title": "View",
  "url": "...",
  "availability": [
    {"name": "iOS", "introducedAt": "13.0", "deprecated": false, "beta": false},
    {"name": "macOS", "introducedAt": "10.15", "deprecated": false, "beta": false},
    {"name": "tvOS", "introducedAt": "13.0", "deprecated": false, "beta": false},
    {"name": "watchOS", "introducedAt": "6.0", "deprecated": false, "beta": false},
    {"name": "visionOS", "introducedAt": "1.0", "deprecated": false, "beta": false}
  ]
}
```

## Default Settings

| Setting | Value |
|---------|-------|
| Input Directory | `~/.cupertino/docs` |
| Concurrent Requests | 50 |
| Request Timeout | 1 second |
| Method | Direct API fetch |
| Authentication | Not required |

## Options

### --force

Re-fetch availability for all documents, even those that already have data.

```bash
cupertino fetch --source availability --force
```

### --fast

Use aggressive settings for faster fetching:
- 100 concurrent requests
- 0.5 second timeout
- Skips documents that already have availability

```bash
cupertino fetch --source availability --fast
```

### Combined

```bash
cupertino fetch --source availability --force --fast
```

## Fallback Strategy

When the API returns 404 or times out, availability is derived using fallbacks:

1. **Parent Document** - Inherit from parent documentation page
2. **Framework** - Use framework's root availability
3. **Referenced APIs** - For articles, derive from APIs mentioned in content
4. **Empty Marker** - Mark as checked but no availability found

## Examples

### Initial Fetch

```bash
# First, fetch docs
cupertino fetch --source apple-docs

# Then, fetch availability
cupertino fetch --source availability

# Finally, build index with availability
cupertino save
```

### Update Availability Only

```bash
cupertino fetch --source availability --force
cupertino save
```

### Fast Mode for Large Datasets

```bash
cupertino fetch --source availability --fast
```

## Performance

| Metric | Default | Fast Mode |
|--------|---------|-----------|
| Concurrent requests | 50 | 100 |
| Timeout | 1s | 0.5s |
| Estimated time | 30-60 min | 15-30 min |
| Success rate | ~92% | ~85% |

## Statistics

After fetching, shows statistics:

```
Availability fetch complete:
   Total documents: 233,462
   Updated: 145,312
   Successful fetches: 140,000
   Failed fetches: 5,312
   Inherited from parent: 50,000
   Derived from references: 30,000
   Frameworks processed: 250
   Duration: 45:23
   Success rate: 92.5%
```

## Availability Sources

When availability is indexed, the source is tracked:

| Source | Description |
|--------|-------------|
| `api` | Direct from Apple's API |
| `parent` | Inherited from parent document |
| `framework` | Inherited from framework root |
| `references` | Derived from referenced APIs (articles) |
| `empty` | Checked but none found |

## Dependencies

**Requires docs to be fetched first:**

```bash
cupertino fetch --source apple-docs   # Must run first
cupertino fetch --source availability
```

**Other sources derive availability during indexing:**

| Source | Derives From |
|--------|--------------|
| sample-code | Framework docs |
| apple-archive | Framework docs |
| swift-evolution | Swift version in status |
| swift-book | Universal (all platforms) |
| hig | Universal (all platforms) |

## Use Cases

- Filter search results by minimum iOS/macOS version
- Identify deprecated APIs
- Find beta APIs
- Target specific OS versions for development
- Track API availability across platforms

## Notes

- Only updates `~/.cupertino/docs/` (apple-docs source)
- Other sources get availability during `cupertino save`
- ~5% of URLs return 404 (internal/deprecated APIs)
- Collection pages have no platforms (expected)
- Run before `save` for best results
