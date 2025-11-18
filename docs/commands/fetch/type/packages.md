# --type packages

Fetch Swift Package Metadata

## Synopsis

```bash
cupertino fetch --type packages
```

## Description

Fetches metadata for all Swift packages from the Swift Package Index and GitHub APIs. This provides comprehensive information about available Swift packages.

## Data Sources

1. **Swift Package Index API** - Package listings
2. **GitHub API** - Repository metadata (stars, description, language, etc.)

## Output

Creates `checkpoint.json` containing:
- Package owner/repo names
- GitHub URLs
- Descriptions
- Star counts
- Programming language
- License information
- Fork/archived status
- Last update timestamps

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/packages` |
| Output File | `checkpoint.json` |
| Authentication | Not required |
| Estimated Count | ~10,000 packages |

## Examples

### Fetch All Packages
```bash
cupertino fetch --type packages
```

### Fetch Limited Number
```bash
cupertino fetch --type packages --limit 100
```

### Custom Output Directory
```bash
cupertino fetch --type packages --output-dir ./my-packages
```

### Resume Interrupted Fetch
```bash
cupertino fetch --type packages --resume
```

## Output File Structure

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

## Use Cases

- Build package catalogs
- Analyze Swift ecosystem
- Track popular packages
- Monitor package trends
- Research Swift libraries

## Notes

- No authentication required
- Uses public APIs
- Fetches complete ecosystem snapshot
- JSON output for easy parsing
- Can be imported into databases or analysis tools
