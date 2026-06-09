# cupertino search

Search indexed documentation from the command line

## Synopsis

```bash
cupertino search <query> [options]
```

## Description

Searches the local indexes. By default fans the query out across every available source and merges the results with reciprocal-rank fusion (`k = 60`, source-weighted); with `--source <name>` it pins the query to one source and returns that source's native list view. BM25F is the per-source ranker inside `apple-docs`; the top-level user-facing rank in fan-out mode is RRF-fused, not BM25.

This command provides the same search functionality as the MCP `search` tool, allowing AI agents and users to search from the command line. (The pre-#239 per-source MCP tools `search_docs`, `search_hig`, `search_samples`, `search_all` were unified into the single `search` tool, `--source` here mirrors its `source` parameter.)

`search` operates in two modes:

- **Default (no `--source`)**: fans the question out across every available DB in parallel: Apple docs, samples, HIG, Apple Archive, Swift Evolution, swift.org, the Swift Book, and packages. It ranks the merged candidates via reciprocal-rank fusion (k=60). Output is chunked excerpts ready for LLM context. This used to be a separate `cupertino ask` command; it was absorbed into `search` in [#239](https://github.com/mihaelamj/cupertino/issues/239).
- **`--source <name>`**: queries one source and returns the source-specific list view (URI + summary). Use this when you know exactly which corpus you want.

A failing fetcher (e.g. missing DB) collapses to empty rather than failing the whole query, so partial coverage still returns useful results.

Results can be output in text, JSON, or markdown (`md` alias) format, making it easy to integrate with scripts and AI workflows.

## Arguments

### query

The search query string (required).

**Example:**
```bash
cupertino search "SwiftUI View"
cupertino search "async await"
cupertino search "Observable macro"
```

## Options

### -s, --source

Filter results to a single documentation source. Omit to search all sources.

**Type:** String
**Values:** `apple-docs`, `samples`, `hig`, `apple-archive`, `swift-evolution`, `swift-org`, `swift-book`, `packages`, `all`

**Example:**
```bash
cupertino search "concurrency" --source swift-evolution
cupertino search "View" --source apple-docs
cupertino search "@Observable" --source samples
cupertino search "CALayer" --source apple-archive
cupertino search "buttons" --source hig
```

### --include-archive

Legacy Apple Archive inclusion flag.

**Type:** Flag (boolean)
**Default:** false

Current fan-out already includes `apple-archive` as a normal low-weight source. The flag remains accepted for compatibility with older unified-DB workflows; for archive-only results, prefer `--source apple-archive`.

**Example:**
```bash
cupertino search "Core Animation" --source apple-archive
cupertino search "CALayer" --source apple-archive --framework quartzcore
```

### -f, --framework

Filter results by framework name.

**Type:** String
**Examples:** `swiftui`, `foundation`, `uikit`, `appkit`, `swift`

**Example:**
```bash
cupertino search "View" --framework swiftui
cupertino search "URL" --framework foundation
```

### -l, --language

Filter results by programming language.

**Type:** String
**Values:** `swift`, `objc`

**Example:**
```bash
cupertino search "URLSession" --language swift
cupertino search "NSURLSession" --language objc
```

### --limit

Maximum number of results to return.

**Type:** Integer
**Default:** 20

**Example:**
```bash
cupertino search "Array" --limit 5
cupertino search "SwiftUI" --limit 50
```

### --min-ios

Filter results to APIs available on a specific iOS version or earlier.

**Type:** String (version number, e.g., `13.0`, `15.0`, `17.0`)

Only returns documents that have availability data and were introduced at or before the specified version.

**Example:**
```bash
cupertino search "Combine" --min-ios 13.0
cupertino search "Observable" --min-ios 17.0 --framework swiftui
```

### --min-macos

Filter results to APIs available on a specific macOS version or earlier.

**Type:** String (version number, e.g., `10.15`, `12.0`, `14.0`)

Only returns documents that have availability data and were introduced at or before the specified version.

**Example:**
```bash
cupertino search "Combine" --min-macos 10.15
cupertino search "SwiftData" --min-macos 14.0
```

### --min-tvos

Filter results to APIs available on a specific tvOS version or earlier.

**Type:** String (version number, e.g., `13.0`, `15.0`, `17.0`)

Only returns documents that have availability data and were introduced at or before the specified version.

**Example:**
```bash
cupertino search "animation" --min-tvos 13.0
cupertino search "player" --min-tvos 15.0 --framework avfoundation
```

### --min-watchos

Filter results to APIs available on a specific watchOS version or earlier.

**Type:** String (version number, e.g., `6.0`, `8.0`, `10.0`)

Only returns documents that have availability data and were introduced at or before the specified version.

**Example:**
```bash
cupertino search "health" --min-watchos 6.0
cupertino search "workout" --min-watchos 8.0 --framework healthkit
```

### --min-visionos

Filter results to APIs available on a specific visionOS version or earlier.

**Type:** String (version number, e.g., `1.0`, `2.0`)

Only returns documents that have availability data and were introduced at or before the specified version.

**Example:**
```bash
cupertino search "immersive" --min-visionos 1.0
cupertino search "spatial" --min-visionos 1.0 --framework realitykit
```

### --swift

Maximum Swift toolchain version for `swift-evolution` rows. Filters proposals to those implemented at or below the requested Swift version; rows from other sources are filtered out when this is set.

**Type:** String (version number, e.g., `5.5`, `5.9`, `6.0`)

**Example:**
```bash
cupertino search "actors" --source swift-evolution --swift 5.5
cupertino search "macros" --source swift-evolution --swift 5.9
```

### --apple-imports

Restrict package results to packages whose indexed source imports the named Apple framework module. No-op outside the packages source.

**Type:** String (module name, e.g., `SwiftUI`, `Combine`, `AppKit`)

**Example:**
```bash
cupertino search "View" --source packages --apple-imports SwiftUI
cupertino search "Publisher" --source packages --apple-imports Combine
```

### --packages-db

Path to the packages database. Used in fan-out mode (and with `--source packages`).

**Type:** String
**Default:** `~/.cupertino/packages.db`

**Example:**
```bash
cupertino search "swift testing fixtures" --packages-db ~/custom/packages.db
```

### --sample-db

Path to the sample-code index database. Used when `--source samples` (or the default fan-out mode) needs to query sample-code.

**Type:** String
**Default:** `~/.cupertino/apple-sample-code.db`

**Example:**
```bash
cupertino search "@Observable" --source samples --sample-db ~/custom/apple-sample-code.db
```

### --per-source

Per-source candidate cap before reciprocal-rank fusion. Fan-out mode only. ([#239](https://github.com/mihaelamj/cupertino/issues/239))

**Type:** Integer
**Default:** 10

**Example:**
```bash
cupertino search "actor reentrancy" --per-source 5 --limit 3
```

### --skip-docs

Skip every apple-docs-backed source (apple-docs, apple-archive, hig, swift-evolution, swift-org, swift-book). Fan-out mode only.

**Type:** Flag
**Default:** false

**Example:**
```bash
cupertino search "swift-nio EventLoopGroup" --skip-docs
```

### --skip-packages

Skip the packages source. Fan-out mode only.

**Type:** Flag
**Default:** false

### --skip-samples

Skip the samples source. Fan-out mode only.

**Type:** Flag
**Default:** false

### --brief

Trim each result's excerpt to its first ~12 non-blank lines for triage. The `Read full:` hint, `See also` footer, and tips still print. Fan-out mode + text/markdown only, JSON keeps full chunks for programmatic consumers. ([#239](https://github.com/mihaelamj/cupertino/issues/239) follow-up)

**Type:** Flag
**Default:** false (full chunks)

**When to use**: skim a list of candidates without burning token budget on full READMEs/code excerpts. The full content is one `cupertino read <id>` away via the per-result hint.

**Example:**
```bash
cupertino search "swiftui list animation" --brief --limit 5
```

### --platform

Restrict packages, samples, and apple-docs results to the named platform's deployment target. Fan-out mode only. Requires `--min-version`. ([#220](https://github.com/mihaelamj/cupertino/issues/220), [#233](https://github.com/mihaelamj/cupertino/issues/233))

**Type:** String
**Values:** `iOS`, `macOS`, `tvOS`, `watchOS`, `visionOS` (case-insensitive)

Swift-language-version sources (`swift-evolution`, `swift-org`, `swift-book`) silently drop the filter, their pages don't carry `min_<platform>` columns at all.

**Example:**
```bash
cupertino search "structured concurrency" --platform iOS --min-version 16.0
```

### --min-version

Minimum version for `--platform`, e.g. `16.0` / `13.0` / `10.15`. Required when `--platform` is set. Lex compare in SQL; correct for current Apple platforms.

### --format

Output format for results.

**Type:** String
**Values:** `text` (default), `json`, `markdown`, `md`

**Example:**
```bash
cupertino search "Array" --format json
cupertino search "SwiftUI" --format markdown
```

## Prerequisites

Before searching, you need a populated database bundle. Most users should run:

```bash
cupertino setup
```

Maintainers rebuilding from raw sources can instead fetch sources and rebuild:

```bash
cupertino fetch --source apple-docs
cupertino fetch --source swift-evolution
cupertino save --all
```

## Examples

### Fan-out mode (default, replaces former `ask`)

```bash
cupertino search "how do I make a SwiftUI view observable"
```

**Output (chunked excerpts, RRF-ranked):**
```
Question: how do I make a SwiftUI view observable
Searched: apple-docs, swift-evolution, packages, samples

══════════════════════════════════════════════════════════════════════
[1] Observable | Apple Developer Documentation  •  source: apple-docs  •  score: 0.0328
    apple-docs://observation/documentation_observation_observable
──────────────────────────────────────────────────────────────────────
A type that emits notifications to observers when underlying data changes...
```

### Single-source list view

```bash
cupertino search "SwiftUI View" --source apple-docs
```

**Output:**
```
Found 20 result(s) for 'SwiftUI View':

[1] View | Apple Developer Documentation
    Source: apple-docs | Framework: swiftui
    URI: apple-docs://swiftui/view
...
```

### Filter by Source

```bash
cupertino search "Sendable" --source swift-evolution
```

**Output:**
```
Found 3 result(s) for 'Sendable':

[1] SE-0302: Sendable and @Sendable closures
    Source: swift-evolution | Framework: swift
    URI: swift-evolution://SE-0302
...
```

### Filter by Framework

```bash
cupertino search "animation" --framework swiftui --limit 5
```

### JSON Output for AI Agents

```bash
cupertino search "Observable" --format json --limit 3
```

**Output:**
```json
[
  {
    "filePath": "https://developer.apple.com/documentation/observation/observable",
    "framework": "observation",
    "score": 12.45,
    "source": "apple-docs",
    "summary": "A type that emits notifications to observers when underlying data changes.",
    "title": "Observable | Apple Developer Documentation",
    "uri": "apple-docs://observation/observable",
    "wordCount": 1234
  }
]
```

### Markdown Output

```bash
cupertino search "async" --format markdown
```

**Output:**
```markdown
# Search Results for 'async'

Found 20 result(s).

## 1. Concurrency | Apple Developer Documentation

- **Source:** apple-docs
- **Framework:** swift
- **URI:** `apple-docs://swift/concurrency`

> Perform asynchronous and parallel operations...
```

### Combined Filters

```bash
cupertino search "View" --source apple-docs --framework swiftui --limit 10 --format json
```

## Use Cases

### 1. Quick Documentation Lookup

```bash
cupertino search "how to use @State"
```

### 2. Find Swift Evolution Proposals

```bash
cupertino search "async" --source swift-evolution
```

### 3. Script Integration

```bash
# Get URIs for further processing
cupertino search "View" --format json | jq '.[].uri'
```

### 4. AI Agent Workflow

```bash
# AI agent searches and parses JSON results
result=$(cupertino search "Observable macro" --format json --limit 5)
```

### 5. Framework-Specific Research

```bash
# Find all SwiftUI animation APIs
cupertino search "animation" --framework swiftui --limit 50
```

## Output Formats

### Text (Default)

Human-readable format with numbered results. Best for interactive use.

### JSON

Machine-readable format with full result data. Best for:
- AI agent integration
- Script automation
- Piping to other tools (jq, etc.)

### Markdown

Formatted markdown output. Best for:
- Documentation generation
- Copy-paste into notes
- Report generation

## Error Handling

### Database Not Found

```
Error: Search database not found at /Users/user/.cupertino/apple-documentation.db
Run 'cupertino setup' or 'cupertino save --all' to build the search index first.
```

**Solution:** Build the search index:
```bash
cupertino save --all
```

### No Results

```
No results found for 'nonexistent query'
```

**Solutions:**
- Try broader search terms
- Remove framework/source filters
- Check spelling

## See Also

- [read](../read/) - Read full document by URI (when search results are truncated)
- [source/](source/) - Documentation sources (apple-docs, swift-evolution, etc.)
- [serve](../serve/) - Start MCP server with search tools
- [save](../save/) - Build search index
- [fetch](../fetch/) - Download documentation
- [doctor](../doctor/) - Check server health

## History

- [#239](https://github.com/mihaelamj/cupertino/issues/239): default fan-out path absorbed from the removed `cupertino ask` subcommand. Pre-1.0 clean break, no alias.
