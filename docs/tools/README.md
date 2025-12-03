# MCP Tools

Cupertino provides these MCP tools for AI agents to search and read documentation.

## Available Tools

### Documentation Tools (requires `cupertino save`)

| Tool | Description |
|------|-------------|
| [search_docs](search_docs/) | Full-text search across all indexed documentation |
| [list_frameworks](list_frameworks/) | List available frameworks with document counts |
| [read_document](read_document/) | Read a document by URI in JSON or Markdown format |

### Sample Code Tools (requires `cupertino index`)

| Tool | Description |
|------|-------------|
| [search_samples](search_samples/) | Search sample code projects and files |
| [list_samples](list_samples/) | List all indexed sample projects |
| [read_sample](read_sample/) | Read sample project README |
| [read_sample_file](read_sample_file/) | Read specific source file from a sample |

## How Tools Work

MCP tools are invoked by AI agents (like Claude) through the Model Context Protocol. When you use Cupertino with Claude Desktop, Claude can call these tools to search and retrieve documentation.

### Typical Workflow

1. **Search** - Use `search_docs` to find relevant documentation
2. **List** - Use `list_frameworks` to discover available frameworks
3. **Read** - Use `read_document` with a URI from search results to get full content

### Example Conversation

**User:** "How do actors work in Swift?"

**Claude:** *calls `search_docs` with query "Actors Swift concurrency"*

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
    "name": "search_docs",
    "arguments": {
      "query": "Actors Swift concurrency"
    }
  }
}
```

## See Also

- [serve command](../commands/serve/) - Start the MCP server
- [MCP Protocol](https://modelcontextprotocol.io) - Official MCP specification
