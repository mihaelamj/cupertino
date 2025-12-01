# --type package-docs

Fetch Swift Package Documentation

## Synopsis

```bash
cupertino fetch --type package-docs
```

## Description

Downloads actual documentation content (README files and documentation sites) for priority Swift packages. This complements `--type packages` which only fetches metadata - this command downloads the actual documentation you can read and search.

## Data Sources

1. **GitHub Raw Content** - README.md files from package repositories
2. **Documentation Sites** - Hosted documentation (docs.vapor.codes, docs.hummingbird.codes, etc.)
3. **Package List** - Uses hardcoded priority packages from Constants

## Output

Creates a directory structure with README files for each package:

```
~/.cupertino/packages/
├── apple/
│   ├── swift-argument-parser/
│   │   └── README.md
│   ├── swift-nio/
│   │   └── README.md
│   ├── swift-collections/
│   │   └── README.md
│   └── ... (28 more Apple packages)
├── vapor/
│   ├── vapor/
│   │   └── README.md
│   └── swift-getting-started-web-server/
│       └── README.md
└── pointfreeco/
    ├── swift-composable-architecture/
    │   └── README.md
    ├── swift-custom-dump/
    │   └── README.md
    └── swift-dependencies/
        └── README.md
```

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/packages` |
| Priority Packages | 36 packages (31 Apple + 5 ecosystem) |
| Request Delay | 0.5 seconds between downloads |
| Authentication | Not required |
| Estimated Time | 1-2 minutes |

## Priority Packages

Downloads documentation for packages defined in:
1. `~/.cupertino/packages/priority-packages.json` (if exists)
2. Fallback to hardcoded priority packages in `Shared.Constants`

### Apple Official (31 packages)
- swift-argument-parser
- swift-nio (+ nio-http2, nio-ssl, nio-transport-services)
- swift-collections
- swift-algorithms
- swift-async-algorithms
- swift-atomics
- swift-crypto
- swift-log
- swift-metrics
- swift-testing
- swift-docc
- swift-format
- swift-package-manager
- swift-protobuf
- ... and 17 more

### Ecosystem Packages (5 packages)
- vapor/vapor
- vapor/swift-getting-started-web-server
- pointfreeco/swift-composable-architecture
- pointfreeco/swift-custom-dump
- pointfreeco/swift-dependencies

**Note:** If no priority packages are found, the command will report an error and exit.

## Examples

### Fetch All Priority Package Documentation
```bash
cupertino fetch --type package-docs
```

### Custom Output Directory
```bash
cupertino fetch --type package-docs --output-dir ./my-package-docs
```

### Resume Interrupted Download
```bash
cupertino fetch --type package-docs --resume
```

### Force Re-download
```bash
cupertino fetch --type package-docs --force
```

## Output File Structure

Each package gets its own directory with README:

```
~/.cupertino/packages/
├── owner/
│   └── repo/
│       └── README.md          # Downloaded from GitHub
```

The README files contain:
- Usage examples
- API documentation
- Installation instructions
- Feature descriptions
- Code samples

## Documentation Site Detection

The downloader detects but doesn't yet download full documentation sites:

| Package | Detected Site | Status |
|---------|--------------|--------|
| vapor/vapor | docs.vapor.codes | Detected only |
| hummingbird-project/hummingbird | docs.hummingbird.codes | Detected only |
| apple/swift-nio | SwiftPackageIndex | Detected only |

**Future Enhancement:** Full site crawling will be added to download these complete documentation sites.

## Use Cases

- **MCP Server Content** - Provide package documentation to AI assistants
- **Offline Reference** - Read package docs without internet
- **Search Indexing** - Index package documentation with `cupertino save`
- **Documentation Analysis** - Analyze how popular packages document their APIs
- **Learning Resources** - Study well-documented Swift packages

## Statistics Reported

After completion, displays:
- Total packages attempted
- Successful README downloads
- Documentation sites detected
- Errors encountered
- Total duration

Example output:
```
✅ Download completed!
   Total packages: 36
   Successful READMEs: 36
   Doc sites detected: 2
   Errors: 0
   Duration: 45s
```

## README File Variants Attempted

For each package, tries multiple filename variations:
1. `README.md` (main branch)
2. `README.MD` (main branch)
3. `readme.md` (main branch)
4. `Readme.md` (main branch)
5. Falls back to `master` branch if `main` not found

This ensures maximum compatibility with different repository conventions.

## Error Handling

### No Priority Packages Found
If neither `priority-packages.json` nor hardcoded constants contain packages:
```
❌ Error: No priority packages found
   Searched:
   - ~/.cupertino/packages/priority-packages.json
   - Shared.Constants.CriticalApplePackages
   - Shared.Constants.KnownEcosystemPackages

   Please ensure at least one package source is configured.
```

### Individual Package Failures
If specific packages fail to download:
- Error is logged but doesn't stop the entire operation
- Statistics show error count at completion
- Failed packages can be retried with `--resume`

### Network Errors
```
❌ Error: README not found for apple/nonexistent-repo
   Attempted:
   - main/README.md
   - main/readme.md
   - master/README.md
   Status: 404 Not Found
```

### GitHub Rate Limiting
```
⚠️  Warning: GitHub rate limit approaching (55/60 requests used)
   Consider setting GITHUB_TOKEN environment variable:
   export GITHUB_TOKEN=ghp_your_token_here
```

## Notes

- **No authentication required** - Uses GitHub's public raw content API
- **Priority-based** - Processes Apple packages first, then ecosystem packages
- **Rate-limited** - 0.5s delay between requests to respect GitHub servers
- **Change detection** - Future enhancement will skip unchanged READMEs
- **Complements `--type packages`** - Use both for complete package information
  - `packages` = metadata (stars, descriptions)
  - `package-docs` = actual documentation content
- **Searchable** - Run `cupertino save` after fetching to index in search database
- **Future expansion** - Will support full documentation site crawling
- **Graceful degradation** - Individual package failures don't stop entire operation
- **Requires priority packages** - Will error if no packages configured

## Comparison with Other Types

| Feature | package-docs | packages | docs |
|---------|-------------|----------|------|
| Content | READMEs | Metadata only | Apple frameworks |
| Source | GitHub raw | GitHub API | developer.apple.com |
| Method | Direct download | API fetch | Web crawl |
| Format | Markdown | JSON | Markdown |
| Count | 36 packages | ~10,000 packages | ~13,000 pages |
| Time | 1-2 minutes | 10-30 minutes | 20-24 hours |

## Integration with Search

After fetching package documentation, build the search index:

```bash
cupertino fetch --type package-docs
cupertino save
```

This makes package documentation searchable via the MCP server:
```bash
cupertino serve
# Now package docs are searchable alongside Apple docs
```

## See Also

- [packages](packages.md) - Fetch Swift Package metadata (complements this command)
- [docs](docs.md) - Fetch Apple Developer Documentation
- [all](all.md) - Fetch all types including package-docs
