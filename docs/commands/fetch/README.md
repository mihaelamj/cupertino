# cupertino fetch

Fetch Apple documentation, Swift Evolution proposals, Swift packages, and sample code

## Synopsis

```bash
cupertino fetch [--type <type>] [options]
```

## Description

The `fetch` command is the unified fetching command that handles both web crawling and direct downloads:

- **Web Crawling** (docs, swift, evolution): Uses WKWebView to render and crawl JavaScript-heavy documentation sites
- **Direct Fetching** (packages, code): Downloads resources directly from APIs without web crawling
- **Parallel Fetching** (all): Fetches all types concurrently for maximum efficiency

## Options

### Core Options

- [--type](type/) - Type of documentation to fetch **[default: docs]**
  - `docs` - Apple Developer Documentation (web crawl)
  - `swift` - Swift.org Documentation (web crawl)
  - `evolution` - Swift Evolution Proposals (web crawl)
  - `packages` - Swift Package Index metadata (direct download)
  - `package-docs` - Swift Package READMEs (direct download)
  - `code` - Apple Sample Code (direct download from Apple, requires auth)
  - `samples` - Apple Sample Code (git clone from GitHub, recommended)
  - `archive` - Apple Archive guides (legacy programming guides)
  - `all` - All types in parallel

### Web Crawl Options

- `--start-url` - Start URL to crawl from (overrides --type default)
- `--max-pages` - Maximum number of pages to crawl (default: 100000)
- `--max-depth` - Maximum crawl depth (default: 15)
- `--allowed-prefixes` - Comma-separated URL prefixes to allow (auto-detected if not specified)
- [--force](force.md) - Force recrawl of all pages (ignore change detection)
- [--resume](resume.md) - Resume from saved session (auto-detects and continues)
- `--only-accepted` - Only download accepted/implemented proposals (evolution type only)

### Direct Fetch Options

- [--output-dir](output-dir.md) - Output directory for downloaded resources
- [--limit](limit.md) - Maximum number of items to fetch (packages/code types only)
- [--authenticate](authenticate.md) - Launch visible browser for authentication (code type only)

## Examples

### Fetch Apple Documentation (Default)
```bash
cupertino fetch
# or explicitly:
cupertino fetch --type docs
```

### Fetch Swift Evolution Proposals
```bash
cupertino fetch --type evolution
```

### Fetch All Types in Parallel
```bash
cupertino fetch --type all
```

### Fetch Swift Packages (Limited)
```bash
cupertino fetch --type packages --limit 100
```

### Fetch Apple Sample Code from GitHub (Recommended)
```bash
cupertino fetch --type samples
# Clones https://github.com/mihaelamj/cupertino-sample-code
# 606 projects, ~10GB with Git LFS, ~4 minutes
```

### Fetch Apple Sample Code from Apple (with Authentication)
```bash
cupertino fetch --type code --authenticate
# Slower, requires Apple ID login
```

### Fetch Apple Archive Guides (Legacy Documentation)
```bash
cupertino fetch --type archive
# Fetches: Core Animation, Core Graphics, Core Text, etc.
```

### Custom Web Crawl
```bash
cupertino fetch --start-url https://developer.apple.com/documentation/swiftui \
                --max-pages 500 \
                --output-dir ./my-docs
```

### Resume Interrupted Crawl
```bash
cupertino fetch --type docs --resume
```

### Force Recrawl
```bash
cupertino fetch --type docs --force
```

## Output

### Web Crawl Types (docs, swift, evolution)

Default locations:
- **docs**: `~/.cupertino/docs/`
- **swift**: `~/.cupertino/swift-org/`
- **evolution**: `~/.cupertino/swift-evolution/`
- **archive**: `~/.cupertino/archive/`

Output files:
- **Markdown files** - Converted documentation pages
- **metadata.json** - Crawl metadata for change detection and resume
- **session.json** - Session state for resuming interrupted crawls

### Direct Fetch Types (packages, code, samples)

Default locations:
- **packages**: `~/.cupertino/packages/`
- **code**: `~/.cupertino/sample-code/` (ZIP files)
- **samples**: `~/.cupertino/sample-code/cupertino-sample-code/` (extracted folders)

Output files:
- **packages-with-stars.json** - Package metadata with GitHub information
- **checkpoint.json** - Progress tracking for resume capability
- **ZIP files** - Downloaded sample code projects (code type)
- **Project folders** - Extracted Xcode projects (samples type)

## Features

### Smart Change Detection

Web crawl types use content hashing to detect changes:
- Only re-downloads modified pages
- Compares content hash, not timestamps
- Significantly reduces crawl time on updates

### Session Resume

All types support resuming interrupted operations:
- **Web crawls**: Saves session state every 100 pages
- **Direct fetches**: Checkpoints after each item
- Use `--resume` flag to continue from last checkpoint

### Parallel Fetching

The `all` type fetches everything concurrently:
```bash
cupertino fetch --type all
# Runs: docs, swift, evolution, packages, code in parallel
```

### Rate Limiting

- **Web crawls**: Respects politeness delays between requests
- **GitHub API**: Automatic rate limiting (60/hour without token, 5000/hour with token)
- **Apple Downloads**: Throttled to prevent server overload

## Notes

### Authentication

**Sample Code (`--type code`)** requires Apple ID authentication:
- Use `--authenticate` to launch visible browser
- Sign in with your Apple Developer account
- Cookies are saved for future runs
- No authentication needed for docs, swift, evolution, or packages

### GitHub Token (Optional)

For faster package fetching, set GITHUB_TOKEN:
```bash
export GITHUB_TOKEN=ghp_your_token_here
cupertino fetch --type packages
```

This increases rate limit from 60/hour to 5000/hour.

### Performance

Typical crawl times:
- **Single page**: ~5-6 seconds (includes JS rendering)
- **Apple docs** (~10,000 pages): 10-30 minutes with change detection
- **Swift Evolution** (~500 proposals): 5-10 minutes
- **Packages** (full index): 2-4 hours (due to GitHub API rate limiting)
- **Sample Code** (~200 projects): 20-40 minutes

## Next Steps

After fetching documentation, build the search index:

```bash
cupertino save
```

Then start the MCP server:

```bash
cupertino serve
# or simply:
cupertino
```

## See Also

- [save](../save/) - Build search index from fetched documentation
- [search](../search/) - Search documentation from CLI
- [serve](../serve/) - Start MCP server
- [doctor](../doctor/) - Check server health
