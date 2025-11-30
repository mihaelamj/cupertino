# cupertino read

Read full document content by URI

## Synopsis

```bash
cupertino read <uri> [options]
```

## Description

Reads the full content of a document from the search index by its URI. This command provides the same functionality as the MCP `read_document` tool, allowing users and AI agents to retrieve complete document content from the command line.

Use this command to get full content when search results are truncated.

## Arguments

### uri

The document URI (required).

**Format:** `<source>://<framework>/<path>`

**Examples:**
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view"
cupertino read "swift-evolution://SE-0302"
cupertino read "swift-book://swift-book_documentation_the-swift-programming-language_concurrency"
```

## Options

### --format

Output format for the document.

**Type:** String
**Values:** `json` (default), `markdown`

**Example:**
```bash
cupertino read "apple-docs://swift/documentation_swift_array" --format json
cupertino read "apple-docs://swift/documentation_swift_array" --format markdown
```

### --search-db

Path to the search database file.

**Type:** String
**Default:** `~/.cupertino/search.db`

**Example:**
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --search-db ~/custom/search.db
```

## Prerequisites

Before reading documents, you need a populated search index:

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

### Read in Markdown Format

```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown
```

**Output:**
```markdown
---
source: https://developer.apple.com/documentation/SwiftUI/View
crawled: 2025-11-30T21:23:10Z
---

# View

**Protocol**

A type that represents part of your app's user interface...
```

### Read in JSON Format

```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format json
```

**Output:**
```json
{
  "title": "View",
  "kind": "Protocol",
  "module": "SwiftUI",
  "declaration": "protocol View",
  "abstract": "A type that represents part of your app's user interface...",
  ...
}
```

### Workflow: Search then Read

```bash
# 1. Search for documentation
cupertino search "MainActor" --limit 1

# Output shows:
#   [truncated at ~150 words] Full document: apple-docs://swift/documentation_swift_mainactor

# 2. Read full document
cupertino read "apple-docs://swift/documentation_swift_mainactor" --format markdown
```

### Pipe to Other Tools

```bash
# Read and extract specific fields with jq
cupertino read "apple-docs://swift/documentation_swift_array" --format json | jq '.declaration'

# Read and save to file
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --format markdown > view.md
```

## Output Formats

### JSON (Default)

Returns structured document data including:
- title, kind, module, declaration
- abstract, overview, discussion
- code examples with language tags
- parameters, return values, conformance info
- platform availability, deprecation notices

Best for:
- AI agent integration
- Programmatic processing
- Extracting specific fields

### Markdown

Returns rendered markdown content with:
- YAML front matter (source URL, crawl date)
- Full document content
- Code blocks with syntax highlighting
- Cross-references as doc:// links

Best for:
- Human reading
- Documentation export
- Copy-paste workflows

## URI Formats

### Apple Documentation
```
apple-docs://<framework>/<path>
```
Example: `apple-docs://swiftui/documentation_swiftui_view`

### Swift Evolution
```
swift-evolution://<proposal-id>
```
Example: `swift-evolution://SE-0302`

### Swift Book
```
swift-book://<path>
```
Example: `swift-book://swift-book_documentation_the-swift-programming-language_concurrency`

### Swift.org
```
swift-org://<path>
```
Example: `swift-org://swift-org_documentation_articles_value-and-reference-types`

## Error Handling

### Document Not Found

```
Error: Document not found: apple-docs://invalid/path
```

**Solutions:**
- Check the URI spelling
- Run `cupertino search` to find valid URIs
- Ensure the document is indexed (`cupertino save`)

### Database Not Found

```
Error: Search database not found at /Users/user/.cupertino/search.db
Run 'cupertino save' to build the search index first.
```

**Solution:** Build the search index:
```bash
cupertino save
```

## See Also

- [search](../search/) - Search documentation (returns truncated summaries)
- [serve](../serve/) - Start MCP server with read_document tool
- [save](../save/) - Build search index
- [fetch](../fetch/) - Download documentation
