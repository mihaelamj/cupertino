# cupertino fetch

Fetch Apple documentation, Swift Evolution proposals, Swift packages, and sample code

## Synopsis

```bash
cupertino fetch [--source <id>] [options]
```

## Description

The `fetch` command is the unified fetching command that handles both web crawling and direct downloads:

- **Web Crawling** (apple-docs, swift-org, swift-book, swift-evolution): Uses WKWebView to render and crawl JavaScript-heavy documentation sites
- **Direct Fetching** (packages, apple-sample-code, samples): Downloads resources directly from APIs without web crawling
- **Parallel Fetching** (all): Fetches all sources concurrently for maximum efficiency

## Options

### Core Options

- [--source](source.md) - Source to fetch (canonical id from the per-source registry) **[default: apple-docs]**
  - `apple-docs` - Apple Developer Documentation (web crawl)
  - `swift-org` - Swift.org Documentation (web crawl)
  - `swift-book` - The Swift Programming Language book (independent Swift Book web crawl)
  - `swift-evolution` - Swift Evolution Proposals (web crawl)
  - `packages` - Swift package source archives (#217). Stage 2 by default; pass `--refresh-metadata` to also pull the SPI metadata + stars (#1108).
  - `apple-sample-code` - Apple Sample Code (direct download from Apple, legacy bundle path, requires auth)
  - `samples` - Apple Sample Code (git clone from GitHub, recommended)
  - `apple-archive` - Apple Archive guides (legacy programming guides)
  - `hig` - Human Interface Guidelines (web crawl)
  - `availability` - API version info for existing docs (annotates already-crawled pages)
  - `all` - All sources in parallel

### Web Crawl Options

- `--start-url` - Start URL to crawl from (overrides --source default)
- `--max-pages` - Maximum number of pages to crawl (default: 1,000,000)
- `--max-depth` - Maximum crawl depth (default: 15)
- [--request-delay](option%20%28--%29/request-delay.md) - Delay in seconds between crawler requests (default: 0.05)
- `--allowed-prefixes` - Comma-separated URL prefixes to allow (auto-detected if not specified)
- [--force](force.md) - Force recrawl of all pages (ignore change detection)
- [--start-clean](start-clean.md) - Ignore any saved session and start fresh from the seed URL
- `--retry-errors` - Re-queue URLs that errored before save (visited but missing from the pages dict). Use after a filename or save bug is fixed to retry the affected pages without re-crawling the whole corpus.
- `--baseline <path>` - Path to a known-good baseline corpus directory (e.g. a prior `cupertino-docs/docs` snapshot). On startup, URLs present in the baseline but missing from the current crawl's known set are prepended to the queue so the resumed crawl recovers gaps without a full recrawl. Path comparison is case-insensitive.
- `--urls <path>` - Path to a text file containing one URL per line. Each URL is enqueued at depth 0; the crawler follows links from each up to `--max-depth`. Set `--max-depth 0` to fetch only the listed URLs with no descent. Useful for fetching a fixed list of URLs another corpus has but this one is missing, without re-spidering. Lines starting with `#` and blank lines are ignored. ([#210](https://github.com/mihaelamj/cupertino/issues/210))
- `--discovery-mode <mode>` - Discovery mode for the docs crawler. Values: `auto` (default; JSON API primary, WKWebView fallback when JSON returns 404), `json-only` (JSON API only, no fallback. Fastest, narrowest), `webview-only` (WKWebView for everything. Slowest, broadest discovery, matches pre-2025-11-30 behavior). ([#208](https://github.com/mihaelamj/cupertino/issues/208))
- `--only-accepted` / `--no-only-accepted` - Only download accepted/implemented proposals (`swift-evolution` source only). On by default; use `--no-only-accepted` to include drafts and rejected proposals.

#### HTML link augmentation in `--discovery-mode auto` (v1.0.2+)

In `auto` mode, after a successful JSON API fetch, the crawler additionally fetches the rendered HTML and unions its `<a href>` links with the JSON `references`-walker output. Catches URL patterns Apple's DocC JSON omits, operator overloads (`Int.&` slugified as `int_amp_<hash>`), legacy numeric-ID symbols (`1418511-iskindofclass`), `data.dictionary` REST sub-paths, and entire framework dirs Apple serves only as HTML (`apple_pay_on_the_web`, `applepencil`, `docc`, `samplecode`, `sign_in_with_apple`). ([#203](https://github.com/mihaelamj/cupertino/issues/203))

A sparse-references skip heuristic keeps the per-page cost bounded: augmentation only runs when the JSON-extracted link count is below `htmlLinkAugmentationMaxRefs`. Pages with rich JSON references already cover the URL graph; HTML adds nothing for them. Roughly the sparse third of Apple's corpus runs through augmentation in practice, matching the issue's stated performance budget.

Two `CrawlerConfiguration` fields control the behavior, there are no CLI flags. Set them in your config JSON:

| field | type | default | meaning |
|---|---|---|---|
| `htmlLinkAugmentation` | `Bool` | `true` | master switch; `false` skips augmentation entirely |
| `htmlLinkAugmentationMaxRefs` | `Int` | `10` | run augmentation only when JSON link count `<` this; set to `Int.max` to disable the heuristic and augment every page |

Backwards-compatible: legacy JSON configs without these fields decode with the defaults above. When augmentation runs and adds at least one link, the crawler logs:

```
🔗 HTML augmentation: +N links (page had M JSON refs)
```

No-op in `--discovery-mode json-only` and `--discovery-mode webview-only`.

> **Resume is automatic.** If a previous `fetch` was interrupted, just re-run the same command, the crawler picks up its `metadata.json` and continues from where it left off. No flag needed. Use `--start-clean` to override and start over.

### Direct Fetch Options

- [--output-dir](output-dir.md) - Output directory for downloaded resources
- [--limit](limit.md) - Maximum number of items to fetch (packages / apple-sample-code sources only)
- [--refresh-metadata](option%20%28--%29/refresh-metadata.md) - Opt into the SPI metadata + star-count refresh stage of `--source packages` (off by default post-[#1108](https://github.com/mihaelamj/cupertino/issues/1108))
- [--skip-archives](option%20%28--%29/skip-archives.md) - Skip the archive-download stage of `--source packages` ([#217](https://github.com/mihaelamj/cupertino/issues/217))
- `--annotate-availability` - Opt-in stage 3: walk the on-disk packages corpus and write per-package `availability.json` (deployment targets + `@available` attrs) ([#219](https://github.com/mihaelamj/cupertino/issues/219))
- `--fast` - Use higher concurrency and shorter timeouts for `--source availability` (faster but more aggressive)

## Examples

### Fetch Apple Documentation (Default)
```bash
cupertino fetch
# or explicitly:
cupertino fetch --source apple-docs
```

### Fetch Swift Evolution Proposals
```bash
cupertino fetch --source swift-evolution
```

### Fetch All Sources in Parallel
```bash
cupertino fetch --source all
```

### Fetch Swift Packages (Limited)
```bash
cupertino fetch --source packages --limit 100
```

### Fetch Apple Sample Code from GitHub (Recommended)
```bash
cupertino fetch --source samples
# Clones https://github.com/mihaelamj/cupertino-sample-code
# 619 projects, ~10GB with Git LFS, ~4 minutes
```

### Fetch Apple Sample Code from Apple

```bash
cupertino fetch --source apple-sample-code
# Reuses Apple Developer cookies from your Safari session.
# Sign in to https://developer.apple.com/ via Safari first; the
# fetcher detects the `myacinfo` cookie automatically.
```

### Fetch Apple Archive Guides (Legacy Documentation)
```bash
cupertino fetch --source apple-archive
# Fetches: Core Animation, Core Graphics, Core Text, etc.
```

### Fetch Human Interface Guidelines
```bash
cupertino fetch --source hig
# Fetches: Design guidelines for iOS, macOS, watchOS, visionOS, tvOS
```

### Custom Web Crawl
```bash
cupertino fetch --start-url https://developer.apple.com/documentation/swiftui \
                --max-pages 500 \
                --output-dir ./my-docs
```

### Resume Interrupted Crawl (automatic)
```bash
# Just re-run the same command, fetch auto-resumes from metadata.json
cupertino fetch --source apple-docs
```

### Force a Truly Fresh Start
```bash
# Clear the saved session AND re-fetch every page
cupertino fetch --source apple-docs --start-clean --force
```

### Force Recrawl Without Resetting the Queue
```bash
cupertino fetch --source apple-docs --force
```

## Output

### Web Crawl Sources (apple-docs, swift-org, swift-evolution, apple-archive, hig, swift-book)

Default locations:
- **apple-docs**: `~/.cupertino/docs/`
- **swift-org**: `~/.cupertino/swift-org/`
- **swift-evolution**: `~/.cupertino/swift-evolution/`
- **apple-archive**: `~/.cupertino/archive/`
- **hig**: `~/.cupertino/hig/`
- **swift-book**: `~/.cupertino/swift-book/`

Output files:

- **Source-specific page files**, DocC render JSON for Apple docs / Swift Book and Markdown for Markdown-backed sources
- **metadata.json**, crawl metadata for change detection and resume
- **session.json**, session state for resuming interrupted crawls

### Direct Fetch Sources (packages, apple-sample-code, samples)

Default locations:
- **packages**: `~/.cupertino/packages/`
- **apple-sample-code**: `~/.cupertino/sample-code/` (legacy Apple ZIP bundle)
- **samples**: `~/.cupertino/sample-code/cupertino-sample-code/` (extracted folders from GitHub clone)

Output files:
- **packages-with-stars.json**, package metadata with GitHub information
- **checkpoint.json**, progress tracking for resume capability
- **ZIP files**, downloaded sample code projects (apple-sample-code path)
- **Project folders**, extracted Xcode projects (samples path)

## Features

### Smart Change Detection

Web crawl types use content hashing to detect changes:
- Only re-downloads modified pages
- Compares content hash, not timestamps
- Significantly reduces crawl time on updates

### Session Resume

All types resume interrupted operations automatically, just re-run the same command:
- **Web crawls**: `metadata.json` is saved every 30 seconds with the queue + visited set, written atomically (`.atomic`) so a kill mid-save can never corrupt it.
- **Direct fetches**: `checkpoint.json` is updated after each item.
- Use `--start-clean` to override auto-resume and start fresh from the seed URL.

### Parallel Fetching

The `all` type fetches everything concurrently:
```bash
cupertino fetch --source all
# Runs: apple-docs, swift-org, swift-evolution, packages, apple-sample-code, samples, apple-archive, hig, availability in parallel
```

### Rate Limiting

- **Web crawls**: Respects politeness delays between requests
- **GitHub API**: Automatic rate limiting (60/hour without token, 5000/hour with token)
- **Apple Downloads**: Throttled to prevent server overload

## Notes

### Authentication

**Sample Code (`--source apple-sample-code`)** requires Apple ID authentication, but the in-process auth window is currently broken (#6 partial; full replacement #193). The supported path is:

- Sign in to `https://developer.apple.com/` in Safari
- Run `cupertino fetch --source apple-sample-code` (no extra flags)
- The fetcher reuses Safari's `myacinfo` cookie from the system cookie store
- No authentication is needed for `docs`, `swift`, `evolution`, `packages`, `samples` (GitHub mirror), `archive`, `hig`, `availability`

### GitHub Token (Optional)

For faster package fetching, set GITHUB_TOKEN:
```bash
export GITHUB_TOKEN=ghp_your_token_here
cupertino fetch --source packages
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
cupertino save --all
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
