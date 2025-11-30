# cupertino search

Search indexed documentation from the command line

## Synopsis

```bash
cupertino search <query> [options]
```

## Description

Searches the local documentation index using full-text search with BM25 ranking. This command provides the same search functionality as the MCP `search_docs` tool, allowing AI agents and users to search from the command line.

Results can be output in text, JSON, or markdown format, making it easy to integrate with scripts and AI workflows.

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

Filter results by documentation source.

**Type:** String
**Values:** `apple-docs`, `swift-evolution`, `swift-org`, `swift-book`, `packages`, `apple-sample-code`

**Example:**
```bash
cupertino search "concurrency" --source swift-evolution
cupertino search "View" --source apple-docs
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

### -l, --limit

Maximum number of results to return.

**Type:** Integer
**Default:** 20

**Example:**
```bash
cupertino search "Array" --limit 5
cupertino search "SwiftUI" --limit 50
```

### --search-db

Path to the search database file.

**Type:** String
**Default:** `~/.cupertino/search.db`

**Example:**
```bash
cupertino search "View" --search-db ~/custom/search.db
```

### --format

Output format for results.

**Type:** String
**Values:** `text` (default), `json`, `markdown`

**Example:**
```bash
cupertino search "Array" --format json
cupertino search "SwiftUI" --format markdown
```

## Prerequisites

Before searching, you need a populated search index:

1. **Download documentation:**
   ```bash
   cupertino fetch --type docs
   cupertino fetch --type evolution
   ```

2. **Build search index:**
   ```bash
   cupertino save
   ```

## Examples

### Basic Search

```bash
cupertino search "SwiftUI View"
```

**Output:**
```
Found 20 result(s) for 'SwiftUI View':

[1] View | Apple Developer Documentation
    Source: apple-docs | Framework: swiftui
    URI: apple-docs://swiftui/documentation_swiftui_view

[2] ViewBuilder | Apple Developer Documentation
    Source: apple-docs | Framework: swiftui
    URI: apple-docs://swiftui/documentation_swiftui_viewbuilder
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
    "filePath": "/Users/user/.cupertino/docs/swiftui/documentation_observation_observable.md",
    "framework": "observation",
    "score": 12.45,
    "source": "apple-docs",
    "summary": "A type that emits notifications to observers when underlying data changes.",
    "title": "Observable | Apple Developer Documentation",
    "uri": "apple-docs://observation/documentation_observation_observable",
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
- **URI:** `apple-docs://swift/documentation_swift_concurrency`

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
Error: Search database not found at /Users/user/.cupertino/search.db
Run 'cupertino save' to build the search index first.
```

**Solution:** Build the search index:
```bash
cupertino save
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
