# packages/ - Swift Package Documentation

Swift package metadata from the Swift Package Index + GitHub, plus extracted source archives for the priority-package set. Both produced by `cupertino fetch --type packages` after the [#217](https://github.com/mihaelamj/cupertino/issues/217) merge.

## Location

**Default**: `~/.cupertino/packages/`

## Created By

```bash
cupertino fetch --type packages                     # both stages
cupertino fetch --type packages --skip-archives     # stage 1 only (metadata)
cupertino fetch --type packages --skip-metadata     # stage 2 only (archives)
```

## Structure

```
~/.cupertino/packages/
├── checkpoint.json                       # Stage 1 progress tracking (resume capability)
├── swift-packages-with-stars.json        # Stage 1 PRIMARY OUTPUT (all packages, clean)
├── <owner>/<repo>/...                    # Stage 2 extracted source per priority package
│   ├── README.md, CHANGELOG.md, LICENSE
│   ├── Package.swift
│   ├── Sources/, Tests/
│   ├── *.docc/ articles + tutorials
│   ├── Examples/, Demo/
│   └── manifest.json                     # Per-package fetch manifest (owner, ref, fetched-at, …)
└── ...

# resolved-packages.json (stage 2 dependency closure cache) lives in the
# parent ~/.cupertino/ directory, not in packages/.
```

## Contents

### [swift-packages-with-stars.json](swift-packages-with-stars.json.md) - Primary Output

**This is the main output file** containing all successfully fetched packages.

Quick preview:

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

See the [swift-packages-with-stars.json documentation](./swift-packages-with-stars.json.md) for complete details.

### [checkpoint.json](checkpoint.json.md) - Progress Tracking

Used internally for resume capability. Contains all packages including those that failed to fetch (with error messages).

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

- **Two JSON files** (checkpoint + with-stars)
- **~10,000 packages** total
- **~3-5 MB** for swift-packages-with-stars.json
- **Similar size** for checkpoint.json

## Data Sources

1. **Swift Package Index** - Package listings
2. **GitHub API** - Repository metadata

## Usage

### Query Packages
```bash
# Top 20 packages by stars (already sorted in with-stars file)
jq '.packages[0:20] | .[] | {owner, repo, stars}' ~/.cupertino/packages/swift-packages-with-stars.json

# Find SwiftUI packages
jq '.packages[] | select(.description | contains("SwiftUI"))' ~/.cupertino/packages/swift-packages-with-stars.json

# Count by license
jq '.packages | group_by(.license) | map({license: .[0].license, count: length})' ~/.cupertino/packages/swift-packages-with-stars.json

# Check fetch statistics
jq '{total: .totalPackages, errors: .errors, errorRate: (.errors/.totalProcessed*100)}' ~/.cupertino/packages/swift-packages-with-stars.json
```

### Load Into Database
```bash
# Import to SQLite (use with-stars for clean data)
sqlite3 packages.db <<EOF
CREATE TABLE packages (...);
.mode json
.import swift-packages-with-stars.json packages
EOF
```

### Use in Code
```swift
// Swift - Load clean package data
let data = try Data(contentsOf: URL(fileURLWithPath: "swift-packages-with-stars.json"))
let output = try JSONDecoder().decode(PackageFetchOutput.self, from: data)
let packages = output.packages  // Clean, sorted packages
```

## Resuming Fetch

Resume is automatic. Just re-run the same command:

```bash
# Auto-resumes from checkpoint.json
cupertino fetch --type packages

# Discard checkpoint and start over
cupertino fetch --type packages --start-clean
```

## Customizing Location

```bash
# Use custom directory
cupertino fetch --type packages --output-dir ./my-packages
```

## Workflow: From Fetch to Embedded Catalog

This directory contains the **source data** for package curation:

### 1. Fetch Packages (Automatic)
```bash
cupertino fetch --type packages
# → Creates checkpoint.json (for resume)
# → Creates swift-packages-with-stars.json (clean output)
```

### 2. Manual Curation
- Review `swift-packages-with-stars.json`
- Select packages for README crawling
- Conservative selection (packages added almost manually)
- Prioritize:
  - Apple official packages
  - High star count packages
  - Swift ecosystem essentials
  - Packages mentioned in Swift.org docs

### 3. Source Archive Download (Stage 2 of `--type packages`)
- `PackageArchiveExtractor` pulls `https://codeload.github.com/<owner>/<repo>/tar.gz/<ref>` (HEAD → main → master fallback) for every package in the resolved closure of `PriorityPackagesCatalog`.
- Filtered extraction: README/CHANGELOG/LICENSE, `Package.swift`, full `Sources/` + `Tests/`, every `.docc` article and tutorial, `Examples/` / `Demo/` directories.
- Per-package `manifest.json` records owner, repo, branch, dependency parents, file count, byte totals.
- Slower than stage 1 (rate-limited tarball downloads), but still typically minutes for the priority closure.

### 4. Embed in Resources
- Transform curated data to catalog format
- Save as `Packages/Sources/Resources/Resources/swift-packages-catalog.json`
- Rebuild app with updated resource (regenerates `SwiftPackagesCatalogEmbedded.swift`)

## Notes

- **Two output files** - checkpoint (resume) + with-stars (final output)
- **No authentication required** for fetch
- **Public data** from Swift Package Index and GitHub
- **Clean data** - Errors filtered out, sorted by stars
- **Source for curation** - Not directly embedded in app
- **Can be regenerated** periodically to capture new packages
- **Large files** (~3-5 MB each) - version control with care
