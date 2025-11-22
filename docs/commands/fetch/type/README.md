# --type

Type of documentation to fetch **[default: docs]**

## Synopsis

```bash
cupertino fetch --type <value>
```

## Description

Specifies which type of resource to fetch. Different types use different fetching methods (web crawl vs. direct download) and have different output formats.

## Available Types

### Web Crawl Types (HTML → Markdown)
- [docs](docs.md) - Apple Developer Documentation **(default)**
- [swift](swift.md) - Swift.org Documentation (The Swift Programming Language)
- [evolution](evolution.md) - Swift Evolution Proposals

### Direct Fetch Types (API/Direct Download)
- [packages](packages.md) - Swift Package Index metadata
- [package-docs](package-docs.md) - Swift Package Documentation (READMEs)
- [code](code.md) - Apple Sample Code projects

### Special Type
- [all](all.md) - All types in parallel

## Quick Examples

```bash
# Fetch Apple Documentation (default)
cupertino fetch --type docs

# Fetch Swift.org Documentation
cupertino fetch --type swift

# Fetch Swift Evolution Proposals
cupertino fetch --type evolution

# Fetch Swift Packages
cupertino fetch --type packages

# Fetch Swift Package Documentation
cupertino fetch --type package-docs

# Fetch Apple Sample Code (requires auth)
cupertino fetch --type code --authenticate

# Fetch everything in parallel
cupertino fetch --type all
```

## Comparison

| Type | Source | Method | Output | Auth | Estimated Count |
|------|--------|--------|--------|------|-----------------|
| `docs` | developer.apple.com | Web crawl | Markdown | No | ~13,000 pages |
| `swift` | docs.swift.org | Web crawl | Markdown | No | ~200 pages |
| `evolution` | GitHub | Direct download | Markdown | No | ~400 proposals |
| `packages` | Swift Package Index | API | JSON | No | ~10,000 packages |
| `package-docs` | GitHub | Direct download | Markdown | No | 36 READMEs |
| `code` | Apple Developer | Direct download | ZIP | Yes | ~600 projects |
| `all` | All sources | Mixed | Mixed | Optional* | ~14,000+ items |

\* `all` type requires authentication only if you want to include sample code

## Default Behavior

When `--type` is omitted, it defaults to `docs`:

```bash
# These are equivalent
cupertino fetch
cupertino fetch --type docs
```

## Output Directories

Each type has a default output directory:

```
~/.cupertino/
├── docs/              # --type docs
├── swift-book/        # --type swift
├── swift-evolution/   # --type evolution
├── packages/          # --type packages & package-docs
└── sample-code/       # --type code
```

Override with `--output-dir`:
```bash
cupertino fetch --type docs --output-dir ./my-custom-dir
```

## Crawl Method Details

### Web Crawl Types (docs, swift, evolution)

Uses WKWebView to:
1. Load HTML pages
2. Extract content
3. Convert to Markdown
4. Save with metadata
5. Respect 0.5s delay between requests

**Features:**
- Change detection (content hashing)
- Session persistence (resume support)
- Auto-save every 100 pages
- Error recovery

### Direct Fetch Types (packages, code)

Downloads directly via:
- **packages** - GitHub API + Swift Package Index API
- **code** - Apple Developer portal with authentication

**Features:**
- Faster than web crawling
- Progress checkpoints
- Resume support
- API rate limiting handled

## Performance

### Web Crawl Types

| Type | Time | Pages | Storage |
|------|------|-------|---------|
| docs | 20-24h | ~13,000 | 200-300 MB |
| swift | 15-30m | ~200 | 10-20 MB |
| evolution | 5-15m | ~400 | 5-10 MB |

### Direct Fetch Types

| Type | Time | Items | Storage |
|------|------|-------|---------|
| packages | 10-30m | ~10,000 | 5-10 MB |
| code | 2-6h | ~600 | 500 MB - 1 GB |

### All Type

| Metric | Value |
|--------|-------|
| Total time | ~20-24h (parallel) |
| Total items | ~14,000+ |
| Total storage | 1-2 GB |

## Choosing a Type

### For API Documentation
- **docs** - Comprehensive Apple framework documentation
- **swift** - Swift language guide and reference

### For Language Evolution
- **evolution** - All Swift Evolution proposals (historical + current)

### For Package Discovery
- **packages** - Swift package ecosystem metadata

### For Code Examples
- **code** - Official Apple sample code projects

### For Everything
- **all** - Complete documentation corpus

## Common Workflows

### Initial Setup
```bash
# Fetch everything
cupertino fetch --type all --authenticate

# Build search index
cupertino save
```

### Daily Updates
```bash
# Update only Apple docs
cupertino fetch --type docs --resume
cupertino save
```

### Research Projects
```bash
# Fetch specific types
cupertino fetch --type evolution
cupertino fetch --type packages
```

## Notes

- **Default type is `docs`** - Most commonly used
- Each type can be fetched independently
- Types can be combined using `--type all`
- Web crawl types support `--resume` and `--force`
- Direct fetch types use APIs (faster but different format)
- Sample code requires Apple ID authentication
- All types compatible with `cupertino save` for search indexing
