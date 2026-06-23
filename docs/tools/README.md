# MCP Tools

Cupertino provides these MCP tools for AI agents to search and read documentation.

For desktop/native clients, these MCP tools are the backend contract. UI layers consume typed tool responses or CupertinoDataKit-style backend interfaces; they must not read the SQLite databases directly.

## Available Tools

### Documentation Tools (requires `cupertino save`)

| Tool | Description |
|------|-------------|
| [search](search/) | Unified full-text search across every indexed source (apple-docs, samples, HIG, apple-archive, swift-evolution, swift-org, swift-book, packages). Use the `source` parameter to scope to one source. Replaces the pre-#239 per-source `search_docs` / `search_hig` / `search_samples` tools, which were collapsed into this one. See the [search command docs](../commands/search/) for the same fan-out behavior on the CLI side. |
| [list](list/) | Source-aware hierarchy navigation. `list(source)` describes the source's shape (depth, per-level kind, leaf content type); `list(source, level:N, parent:…)` walks it. The canonical browse tool; the three `list_*` tools below are kept as aliases. |
| [list_frameworks](list_frameworks/) | List a source's frameworks with document counts. Alias for `list(source, level:1)`. |
| [list_documents](list_documents/) | List paged documents in a framework. Alias for `list(source, level:2, parent:<framework>)`. |
| [list_children](list_children/) | List direct children of a document or topic group. Alias for `list(source, level:3, parent:<uri>)`. |
| [list_sources](list_sources/) | List the installed per-source databases (presence + schema version); reports the canonical source set even when databases are missing, so clients can guide setup |
| [read_document](read_document/) | Read a document by URI in JSON or Markdown format |

### Sample Code Tools (requires `cupertino save --source samples`)

| Tool | Description |
|------|-------------|
| [list_samples](list_samples/) | List all indexed sample projects; `format=json` returns typed project metadata |
| [read_sample](read_sample/) | Read sample project README, metadata, and file list; `format=json` returns typed project data |
| [read_sample_file](read_sample_file/) | Read specific source file from a sample; `format=json` returns typed file content |

(For sample-code search, use the unified `search` tool above with `source: samples`.)

### Semantic Search Tools (AST-powered)

These tools query SwiftSyntax-extracted symbol data for semantic code search.

| Tool | Description |
|------|-------------|
| [search_symbols](search_symbols/) | Search by symbol type (class, struct, actor, function) and name |
| [search_property_wrappers](search_property_wrappers/) | Find @State, @Observable, @MainActor usage patterns |
| [search_concurrency](search_concurrency/) | Find async/await, actor, Sendable patterns |
| [search_conformances](search_conformances/) | Find types by protocol conformance (View, Codable, etc.) |
| [search_generics](search_generics/) | Find generic-parameter constraints across docs, samples, and packages |
| [get_inheritance](get_inheritance/) | Walk class inheritance chains with title-bearing tree nodes |

## How Tools Work

MCP tools are invoked by AI agents (like Claude) through the Model Context Protocol. When you use Cupertino with Claude Desktop, Claude can call these tools to search and retrieve documentation.

### Typical Workflow

1. **Search** - Use `search` to find relevant documentation (optionally pass `source` to narrow the fan-out to one corpus)
2. **List** - Use `list_frameworks` to discover available frameworks, then `list_documents` or `list_children` to browse
3. **Read** - Use `read_document` with a URI from search results to get full content

### Example Conversation

**User:** "How do actors work in Swift?"

**Claude:** *calls `search` with query "Actors Swift concurrency"*

**Claude:** "I found several results. Let me read the main documentation..."

**Claude:** *calls `read_document` with URI from search results*

**Claude:** "Here's what I found about Swift actors..."

## Tool Invocation

Tools are called via JSON-RPC over stdio. Example request:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "search",
    "arguments": {
      "query": "Actors Swift concurrency"
    }
  }
}
```

## See Also

- [serve command](../commands/serve/) - Start the MCP server
- [MCP Protocol](https://modelcontextprotocol.io) - Official MCP specification
