# --docs-dir

Directory containing crawled Apple documentation to serve

## Synopsis

```bash
cupertino serve --docs-dir <path>
```

## Description

Specifies the directory containing Apple Developer Documentation that the MCP server will serve to AI assistants. The server provides documentation access via the `apple-docs://` URI scheme.

## Default

`~/.cupertino/docs`

## Examples

### Serve Default Documentation
```bash
cupertino serve
```

### Serve Custom Directory
```bash
cupertino serve --docs-dir ./my-docs
```

### Serve Swift.org Documentation
```bash
cupertino serve --docs-dir ~/.cupertino/swift-book
```

### Absolute Path
```bash
cupertino serve --docs-dir /Users/username/Documents/apple-docs
```

## Server Behavior

When serving:
1. Server loads documentation from specified directory
2. Registers `DocsResourceProvider`
3. Makes docs available via `apple-docs://{framework}/{page}` URIs
4. AI assistants can read individual documentation pages
5. Supports framework listing and discovery

Example server output:
```
🚀 Cupertino MCP Server starting...
   Apple docs: ~/.cupertino/docs
   Evolution: ~/.cupertino/swift-evolution
   Search DB: ~/.cupertino/search.db
   Waiting for client connection...
```

## Resource URIs

Documents are accessible via:
```
apple-docs://Foundation/NSString
apple-docs://SwiftUI/View
apple-docs://UIKit/UIViewController
```

## Expected Structure

```
docs-dir/
├── metadata.json           # Optional but recommended
├── Foundation/
│   ├── NSString.md
│   └── NSArray.md
├── SwiftUI/
│   ├── View.md
│   └── Text.md
└── ... (framework directories)
```

## Server Startup Requirements

The serve command requires at least ONE of:
- Apple documentation (`--docs-dir`)
- Swift Evolution proposals (`--evolution-dir`)
- Search database (`--search-db`)

If none exist, server shows getting started guide:
```
👋 Welcome to Cupertino MCP Server!

No documentation found to serve. Let's get you started!

📚 STEP 1: Crawl Documentation
  $ cupertino fetch --type docs

🔍 STEP 2: Build Search Index
  $ cupertino save

🚀 STEP 3: Start the Server
  $ cupertino serve
```

## Notes

- Tilde (`~`) expansion is supported
- Directory must exist and contain `.md` files
- Created by `cupertino fetch --type docs`
- Server reads files on-demand (not loaded into memory)
- Changes to files require server restart
- Used by `DocsResourceProvider` for resource access
- Compatible with Claude Desktop and other MCP clients
