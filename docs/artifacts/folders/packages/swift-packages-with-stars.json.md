# swift-packages-with-stars.json - Package Fetch Output

Complete Swift package metadata from Swift Package Index + GitHub API.

## Location

```
~/.cupertino/packages/swift-packages-with-stars.json
```

## Created By

```bash
cupertino fetch --type packages
```

## Purpose

- **Primary output** from package fetch operation
- **Complete package list** with GitHub metadata (9,000+ packages)
- **Source data** for curating packages to embed in resources
- **Filtered & sorted** - Errors removed, sorted by star count

## Structure

```json
{
  "totalPackages": 9699,
  "totalProcessed": 10000,
  "errors": 301,
  "generatedAt": "2025-11-19T10:30:00Z",
  "packages": [
    {
      "owner": "apple",
      "repo": "swift-nio",
      "url": "https://github.com/apple/swift-nio",
      "description": "Event-driven network application framework",
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

## Fields

### Top Level
- **totalPackages** - Number of successfully fetched packages
- **totalProcessed** - Total packages attempted (including errors)
- **errors** - Number of packages that failed to fetch
- **generatedAt** - Timestamp when fetch completed
- **packages** - Array of package metadata (filtered & sorted)

### Per Package
- **owner** - GitHub owner/organization
- **repo** - Repository name
- **url** - GitHub repository URL
- **description** - Package description from GitHub
- **stars** - GitHub star count (⭐)
- **language** - Primary programming language
- **license** - License type (MIT, Apache-2.0, etc.)
- **fork** - Is this a fork? (boolean)
- **archived** - Is this archived? (boolean)
- **updatedAt** - Last updated timestamp from GitHub

## Data Quality

### Filtering
- Packages with errors are **excluded** (unless they have stars)
- Archived and fork packages are **included** (can be filtered later)
- Filter: `.filter { $0.error == nil || $0.stars > 0 }`

### Sorting
- Packages are **sorted by star count** (descending)
- Most popular packages appear first
- Sort: `.sorted { $0.stars > $1.stars }`

## Size

- **~3-5 MB** for 9,000+ packages
- **JSON format** with pretty-printing
- **Human-readable** and machine-parsable

## Usage

### Query Packages
```bash
# Top 20 packages by stars
jq '.packages[0:20] | .[] | {owner, repo, stars}' swift-packages-with-stars.json

# Find packages by owner
jq '.packages[] | select(.owner == "apple")' swift-packages-with-stars.json

# Count by license
jq '.packages | group_by(.license) | map({license: .[0].license, count: length})' swift-packages-with-stars.json

# Find SwiftUI-related packages
jq '.packages[] | select(.description | contains("SwiftUI"))' swift-packages-with-stars.json
```

### Check Fetch Stats
```bash
# Summary
jq '{total: .totalPackages, processed: .totalProcessed, errors: .errors}' swift-packages-with-stars.json

# Error rate
jq '(.errors / .totalProcessed * 100)' swift-packages-with-stars.json
```

## Workflow: Curating Packages for Embedded Resources

This file serves as the **source data** for curating packages to embed in the app:

### 1. Fetch All Packages
```bash
cupertino fetch --type packages
# → Creates swift-packages-with-stars.json
```

### 2. Manually Curate Package List
- Review `swift-packages-with-stars.json`
- Select packages for README crawling
- Create curated list based on:
  - Popularity (star count)
  - Apple official packages
  - Swift ecosystem importance
  - Mentioned in Swift.org documentation

### 3. Crawl READMEs (Future Step)
- **Slow process** - Fetches README from GitHub for each package
- **Conservative selection** - Only crawl curated packages
- **Manual workflow** - Packages added almost manually to avoid rate limits

### 4. Embed in Resources
- Transform curated data to catalog format
- Save as `Packages/Sources/Resources/Resources/swift-packages-catalog.json`
- Rebuild app with updated embedded resource

## Relationship to Other Files

| File | Purpose | Contains |
|------|---------|----------|
| `swift-packages-with-stars.json` | **Fetch output** | All 9,699 packages (clean, sorted) |
| `checkpoint.json` | **Resume state** | Progress tracking (may include errors) |
| `priority-packages.json` (resources) | **Priority list** | Curated subset for processing first |
| `swift-packages-catalog.json` (resources) | **Embedded catalog** | Final curated packages with READMEs |

## Regeneration

This file should be regenerated periodically to capture new packages:

```bash
# Regenerate (takes ~1-2 hours with rate limiting)
cupertino fetch --type packages --limit 10000

# Check what's new
jq -r '.packages[0:50] | .[] | "\(.stars) ⭐ \(.owner)/\(.repo)"' swift-packages-with-stars.json
```

## Notes

- **Complete data source** - Contains all fetched packages, not just curated subset
- **Rate limited** - Respects GitHub API limits during fetch
- **Clean output** - Errors filtered out, ready for analysis
- **Sorted by popularity** - Top packages appear first
- **Not for runtime use** - Source data for curation, not loaded by app
- **Large file** - 3-5 MB, version control with care

## Data Sources

1. **Swift Package Index** - Package repository list
2. **GitHub API** - Repository metadata (stars, description, license, etc.)
3. **Rate limiting** - 1.2s delay between fetches to respect API limits

## See Also

- [checkpoint.json](checkpoint.json.md) - Progress tracking for resume
- [priority-packages.json](../../Resources/priority-packages.json.md) - Curated priority list (if documented)
- Package fetch command documentation
