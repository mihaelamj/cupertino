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

### 5. Index command cannot resume after interruption
**Problem**: If you interrupt `cupertino index` while it's building the search database, you must start over from scratch.

**Why this matters**: Building the search index can take several minutes. If the process crashes or you press Ctrl+C, all progress is lost.

**Example scenario**:
```bash
$ cupertino index
Building search index...
Progress: 5000/10000 pages indexed
^C  # User presses Ctrl+C or process crashes
# All progress lost - must rebuild entire index from beginning
```

**What happens now**:
- Index command doesn't save checkpoints
- No way to resume from where it stopped
- Must delete and rebuild entire `search.db` every time

**What should happen**:
- Save progress checkpoints during indexing (like `fetch` command does)
- Allow `--resume` flag to continue from last checkpoint
- Or: Make index updates incremental (add/update only changed documents)

**Status**: Open
**Priority**: Medium
**Component**: Index command
**Location**: `Sources/CupertinoCLI/Commands.swift:405-504`
**Affected Command**: `cupertino index`
**Related**: TODO #6 (command atomicity)

### 6. metadata.json can be corrupted if process crashes during write
**Problem**: When `cupertino crawl` writes `metadata.json`, it doesn't use atomic writes. If the process crashes mid-write, the file can be left corrupted.

**Why this matters**: `metadata.json` is critical - the `index` command depends on it. A corrupted file breaks indexing.

**Example scenario**:
```bash
$ cupertino crawl --type docs
Crawling documentation...
Visited 1000 pages...
Writing metadata.json...  # ← Process crashes here
# metadata.json is now half-written and corrupted

$ cupertino index
Error: Failed to parse metadata.json (corrupted JSON)
```

**What happens now**:
- Direct write to `metadata.json` without atomic guarantee
- If write is interrupted, file contains incomplete JSON
- Next command that reads it will fail with parse error

**What should happen**:
- Write to temporary file first: `metadata.json.tmp`
- When write completes, rename to `metadata.json` (atomic operation)
- If crash happens, old `metadata.json` remains intact

**Technical details**:
- Current: `encoder.encode(metadata)` writes directly to target file
- Should use: Write to temp file + `FileManager.replaceItemAt()` (atomic rename)

**Status**: Open
**Priority**: Medium
**Component**: Crawl command
**Location**: `Sources/CupertinoCLI/Commands.swift` (crawl command metadata write)
**Affected Command**: `cupertino crawl`
**Related**: TODO #6 (command atomicity)

### 7. Crawl command has no transaction support for multi-file operations
**Problem**: When `cupertino crawl` runs, it creates hundreds of markdown files plus `metadata.json`. If the process crashes partway through, you're left with an inconsistent state - some files from the new crawl, some from the old crawl, and metadata that doesn't match.

**Why this matters**: You can't tell which files are current and which are stale. The `index` command might index a mix of old and new documentation.

**Example scenario**:
```bash
# Previous crawl created 500 files
$ ls ~/.cupertino/docs/ | wc -l
500

# New crawl starts
$ cupertino crawl --type docs --force
Crawling documentation...
Saved 300 new pages...  # ← Process crashes here

# Now you have inconsistent state:
$ ls ~/.cupertino/docs/ | wc -l
800  # Mix of 300 new files + 500 old files

# metadata.json might say 300 files, but you have 800
# Or metadata.json might list files that don't exist yet
```

**What happens now**:
- Files are written one at a time with no coordination
- No transaction log or rollback capability
- Crash leaves a partial mix of old and new files
- Hard to recover - must delete everything and start over

**What should happen** (pick one approach):

**Option A: Atomic directory swap**
- Write all files to temporary directory: `~/.cupertino/docs.new/`
- When crawl completes, rename: `docs.new` → `docs` (atomic)
- Old `docs` directory preserved as backup until success

**Option B: Transaction log**
- Keep a log file: `crawl-transaction.log`
- Record every file operation: "created file X", "updated file Y"
- On crash, use log to rollback partial changes
- On success, delete log

**Option C: Two-phase commit** (simplest for users)
- `--resume` flag already exists - just improve it
- Track which URLs were successfully crawled in checkpoint
- On resume, skip successfully crawled pages
- Only problem: doesn't clean up stale files from previous runs

**Status**: Open
**Priority**: Low (workaround exists: delete output dir and restart)
**Component**: Crawl command
**Location**: `Sources/CupertinoCore/Crawler.swift` (markdown file writes)
**Affected Command**: `cupertino crawl`
**Related**: TODO #6 (command atomicity)
**Note**: This is a complex problem - might defer until architecture refactor (TODO #8)
