# packages/ - Swift Package Metadata

Swift package metadata from Swift Package Index and GitHub.

## Location

**Default**: `~/.cupertino/packages/`

## Created By

```bash
cupertino fetch --type packages
```

## Structure

```
~/.cupertino/packages/
└── checkpoint.json    # All package metadata
```

## Contents

### [checkpoint.json](checkpoint.json.md)

See [checkpoint.json documentation](checkpoint.json.md) for complete structure details.

Quick preview:

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

## Package Information

Each package entry includes:
- **owner** - GitHub owner/organization
- **repo** - Repository name
- **url** - GitHub URL
- **description** - Package description
- **stars** - GitHub star count
- **language** - Primary language
- **license** - License type
- **fork** - Is it a fork?
- **archived** - Is it archived?
- **updatedAt** - Last update timestamp

## Size

- **Single JSON file**
- **~10,000 packages**
- **~3-5 MB file size**

## Data Sources

1. **Swift Package Index** - Package listings
2. **GitHub API** - Repository metadata

## Usage

### Query Packages
```bash
# Find SwiftUI packages
jq '.packages[] | select(.repo | contains("SwiftUI"))' ~/.cupertino/packages/checkpoint.json

# Top packages by stars
jq '.packages | sort_by(-.stars) | .[0:10]' ~/.cupertino/packages/checkpoint.json

# Count by license
jq '.packages | group_by(.license) | map({license: .[0].license, count: length})' ~/.cupertino/packages/checkpoint.json
```

### Load Into Database
```bash
# Import to SQLite
sqlite3 packages.db <<EOF
CREATE TABLE packages (...);
.mode json
.import checkpoint.json packages
EOF
```

### Use in Code
```swift
// Swift
let data = try Data(contentsOf: URL(fileURLWithPath: "checkpoint.json"))
let packages = try JSONDecoder().decode(PackageList.self, from: data)
```

## Resuming Fetch

```bash
# Resume if interrupted
cupertino fetch --type packages --resume
```

## Customizing Location

```bash
# Use custom directory
cupertino fetch --type packages --output-dir ./my-packages
```

## Notes

- All data in one JSON file for easy processing
- No authentication required
- Public data from Swift Package Index and GitHub
- Updated snapshot of Swift ecosystem
- Can be re-fetched anytime to get latest data
