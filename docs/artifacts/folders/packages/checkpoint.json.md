# checkpoint.json - Fetch Progress Tracking

Tracks progress for fetch operations (packages and sample code).

## Location

Created in the output directory of fetch operations:
- `~/.cupertino/packages/checkpoint.json`
- `~/.cupertino/sample-code/checkpoint.json`

## Created By

```bash
# For packages
cupertino fetch --type packages

# For sample code
cupertino fetch --type code --authenticate
```

## Purpose

- **Progress Tracking** - Know what's been fetched
- **Resume Capability** - Continue interrupted downloads
- **Data Storage** - For packages, this IS the data file

## Format: Packages

For `--type packages`, checkpoint.json contains ALL package data:

```json
{
  "version": "1.0",
  "lastCrawled": "2025-11-17",
  "source": "Swift Package Index + GitHub API",
  "count": 9699,
  "packages": [
    {
      "owner": "apple",
      "repo": "swift-nio",
      "url": "https://github.com/apple/swift-nio",
      "description": "Event-driven network framework",
      "stars": 7500,
      "language": "Swift",
      "license": "Apache-2.0",
      "fork": false,
      "archived": false,
      "updatedAt": "2025-11-15T10:30:00Z"
    }
  ]
}
```

See [packages/](packages/) for detailed structure.

## Format: Sample Code

For `--type code`, checkpoint.json tracks download progress:

```json
{
  "version": "1.0",
  "timestamp": "2025-11-17T10:30:00Z",
  "totalCount": 606,
  "downloadedCount": 350,
  "downloaded": [
    {
      "title": "Building Lists and Navigation",
      "filename": "swiftui-building-lists-and-navigation.zip",
      "url": "https://developer.apple.com/...",
      "downloadedAt": "2025-11-17T10:31:00Z",
      "size": 1234567
    }
  ]
}
```

## Usage

### Check Progress
```bash
# Packages: Count total
jq '.count' ~/.cupertino/packages/checkpoint.json

# Sample Code: Check progress
jq '{total: .totalCount, downloaded: .downloadedCount}' ~/.cupertino/sample-code/checkpoint.json
```

### Resume Download
```bash
# Automatically uses checkpoint.json
cupertino fetch --type packages --resume
cupertino fetch --type code --authenticate --resume
```

### Query Package Data
```bash
# Find packages by owner
jq '.packages[] | select(.owner == "apple")' ~/.cupertino/packages/checkpoint.json

# Top 10 by stars
jq '.packages | sort_by(-.stars) | .[0:10]' ~/.cupertino/packages/checkpoint.json
```

## Resume Logic

When using `--resume`:
1. Reads checkpoint.json
2. Identifies what's already been fetched
3. Skips those items
4. Continues from where it left off
5. Updates checkpoint as it progresses

## Differences by Type

| Aspect | Packages | Sample Code |
|--------|----------|-------------|
| **Purpose** | Data storage + progress | Progress tracking only |
| **Contains** | Complete package metadata | List of downloaded files |
| **Size** | ~3-5 MB | ~50-100 KB |
| **Updated** | Each item added | Each download completes |

## Used By

- `cupertino fetch --resume` - Resume functionality
- Data analysis tools (for packages)
- Progress monitoring

## Notes

- JSON format for easy parsing
- Safe to delete to start fresh fetch
- For packages: This is your data file
- For sample code: Just progress tracking
- One checkpoint file per fetch operation
