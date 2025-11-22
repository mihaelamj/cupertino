# Default Options Behavior

When no options are specified for `save` command

## Synopsis

```bash
cupertino save
```

## Default Behavior

When you run `cupertino save` without any options, it uses these defaults:

```bash
cupertino save \
  --docs-dir ~/.cupertino/docs \
  --evolution-dir ~/.cupertino/swift-evolution \
  --metadata-file ~/.cupertino/docs/metadata.json \
  --search-db ~/.cupertino/search.db
```

## Default Option Values

| Option | Default Value | Description |
|--------|---------------|-------------|
| `--docs-dir` | `~/.cupertino/docs` | Apple documentation directory |
| `--evolution-dir` | `~/.cupertino/swift-evolution` | Swift Evolution proposals directory |
| `--metadata-file` | `~/.cupertino/docs/metadata.json` | Metadata file path |
| `--search-db` | `~/.cupertino/search.db` | Search database output path |
| `--clear` | `false` | Don't clear existing index |

## Build Behavior

The save command will:

1. **Check for docs directory** - If not found, shows error
2. **Load metadata** - Reads `metadata.json` from docs directory
3. **Initialize database** - Creates or opens `search.db`
4. **Check for evolution directory** - Optional, warns if missing
5. **Build FTS5 index** - Indexes all `.md` files
6. **Incremental by default** - Only indexes new/changed documents (unless `--clear`)

## Directory Requirements

### Required
- `--docs-dir` must exist OR
- `--evolution-dir` must exist

At least one source directory is required.

### Optional
- `--metadata-file` is optional (but recommended for change detection)
- `--evolution-dir` is optional (can index docs only)

## Expected Directory Structure

```
~/.cupertino/
├── docs/                          # --docs-dir
│   ├── metadata.json              # --metadata-file
│   ├── Foundation/
│   └── SwiftUI/
├── swift-evolution/               # --evolution-dir
│   ├── SE-0001.md
│   └── SE-0296.md
└── search.db                      # --search-db (output)
```

## Incremental vs. Full Build

### Default (Incremental)
```bash
cupertino save
```
- Uses content hashing to detect changes
- Only re-indexes modified documents
- Fast for updates (seconds to minutes)

### Full Rebuild
```bash
cupertino save --clear
```
- Clears existing index
- Re-indexes everything
- Slower but ensures clean state (2-5 minutes)

## Common Usage Patterns

### Minimal (All Defaults)
```bash
cupertino save
```

### Custom Directories
```bash
cupertino save --docs-dir ./my-docs --search-db ./my-search.db
```

### Evolution Only
```bash
cupertino save \
  --docs-dir /nonexistent \
  --evolution-dir ~/.cupertino/swift-evolution \
  --search-db ~/.cupertino/evolution-search.db
```

### Force Full Rebuild
```bash
cupertino save --clear
```

## Output

Default output location: `~/.cupertino/search.db`

Database contains:
- `docs_fts` - FTS5 full-text search table
- `docs_metadata` - Document metadata
- Indexes for frameworks, sources, URIs

## Error Handling

### No Documentation Found
```
❌ Metadata file not found: ~/.cupertino/docs/metadata.json
   Run 'cupertino fetch' first to download documentation.
```

### Evolution Directory Missing
```
ℹ️  Swift Evolution directory not found, skipping proposals
   Run 'cupertino fetch --type evolution' to download proposals
```

Still proceeds with docs only.

## Notes

- Defaults match `cupertino fetch` output locations
- Minimal configuration needed for typical use
- Evolution directory is optional
- All paths support tilde (`~`) expansion
- Use `--help` to see all options
