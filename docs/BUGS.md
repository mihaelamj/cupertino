# Cupertino Bugs

Known issues and bugs that need to be fixed.

## Bug Fixes

### ✅ 1. Index command --clear flag validation error (FIXED)
- Fixed `--clear` flag default value (was `true`, now `false`)
- Resolves ArgumentParser validation error: "Boolean flags with initial value of `true` result in flag always being `true`"

**Status**: Fixed
**Priority**: Medium
**Component**: Index command
**Affected Command**: `cupertino index --clear`

## Open Bugs

### 1. fetch authenticate does not work
- it never opens the safari browser, I opened it manually
- investigate how other terminal commands are doing it
- maybe search GitHub for code examples

**Status**: Open
**Priority**: High
**Component**: Fetch command authentication
**Affected Command**: `cupertino fetch --type code --authenticate`

### 2. index command requires crawl to run first (dependency violation)
- `index` command fails if `metadata.json` doesn't exist
- Error message: "Run 'cupertino crawl' first to download documentation"
- Creates hard dependency: crawl → index
- Violates atomicity requirement (TODO #6)

**Status**: Open
**Priority**: Medium
**Component**: Index command
**Location**: `Sources/CupertinoCLI/Commands.swift:437-440`
**Affected Command**: `cupertino index`
**Related**: TODO #6 (command atomicity)

### 3. MCP server requires index to run first (dependency violation)
- MCP server (`cupertino-mcp serve`) requires `search.db` from index command
- Warns but continues if database missing, but search tools are unavailable
- Creates dependency chain: crawl → index → MCP server
- Violates atomicity requirement (TODO #6)
- Note: This is MCP-specific, not a general command issue

**Status**: Open
**Priority**: Low (MCP-only feature)
**Component**: MCP server
**Location**: `Sources/CupertinoMCP/ServeCommand.swift:76-84`
**Affected Command**: `cupertino-mcp serve` (MCP server only)
**Related**: TODO #6 (command atomicity)

### 4. No automated catalog generation for sample code
- Sample code catalog must be manually created and copied
- No `update-catalogs` command exists
- Manual workflow: fetch → manual copy → rebuild
- Easy to forget updating embedded resources
- No validation of catalog structure

**Status**: Open
**Priority**: Low
**Component**: Resource management
**Affected**: `sample-code-catalog.json` updates
**Related**: TODO #7 (resource update commands)
