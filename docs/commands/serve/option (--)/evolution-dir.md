# --evolution-dir

Directory containing Swift Evolution proposals to serve

## Synopsis

```bash
cupertino serve --evolution-dir <path>
```

## Description

Specifies the directory containing Swift Evolution proposals that the MCP server will serve to AI assistants. The server provides proposal access via the `swift-evolution://` URI scheme.

## Default

`~/.cupertino/swift-evolution`

## Examples

### Serve Default Evolution Directory
```bash
cupertino serve
```

### Serve Custom Directory
```bash
cupertino serve --evolution-dir ./my-evolution
```

### Absolute Path
```bash
cupertino serve --evolution-dir /Users/username/Documents/swift-evolution
```

## Server Behavior

When serving:
1. Server loads proposals from specified directory
2. Registers evolution resource provider
3. Makes proposals available via `swift-evolution://{proposal-id}` URIs
4. AI assistants can read individual proposals
5. Supports proposal listing and discovery

Example server output:
```
🚀 Cupertino MCP Server starting...
   Apple docs: ~/.cupertino/docs
   Evolution: ~/.cupertino/swift-evolution
   Search DB: ~/.cupertino/search.db
   Waiting for client connection...
```

## Resource URIs

Proposals are accessible via:
```
swift-evolution://SE-0001
swift-evolution://SE-0296
swift-evolution://SE-0297
```

## Expected Structure

```
evolution-dir/
├── metadata.json           # Optional
├── SE-0001.md
├── SE-0002.md
├── SE-0296.md              # Async/await
├── SE-0297.md              # Concurrency
└── ... (~400 proposals)
```

## Server Startup Requirements

The serve command requires at least ONE of:
- Apple documentation (`--docs-dir`)
- Swift Evolution proposals (`--evolution-dir`)
- Search database (`--search-db`)

Swift Evolution is **optional** - server will run without it.

## Notes

- Tilde (`~`) expansion is supported
- Directory must exist and contain `.md` files
- Created by `cupertino fetch --type evolution`
- Server reads files on-demand (not loaded into memory)
- Changes to files require server restart
- Used by evolution resource provider
- Compatible with Claude Desktop and other MCP clients
- Optional but recommended for Swift language evolution context
