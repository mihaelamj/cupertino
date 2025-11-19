# --type all

Fetch All Documentation Types

## Synopsis

```bash
cupertino fetch --type all
```

## Description

Fetches all documentation types in parallel: Apple docs, Swift.org docs, Swift Evolution proposals, Swift packages metadata, and sample code. This is the most comprehensive fetch option that downloads the entire Cupertino corpus.

## Fetched Types

Runs these fetch types **in parallel**:

1. **docs** - Apple Developer Documentation
2. **swift** - Swift.org Documentation
3. **evolution** - Swift Evolution Proposals
4. **packages** - Swift Package Metadata
5. **code** - Apple Sample Code (requires `--authenticate`)

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/` (base directory) |
| Execution Mode | Parallel (all types simultaneously) |
| Authentication | Required for sample code only |
| Estimated Total Pages | ~14,000+ items |

## Examples

### Fetch Everything
```bash
cupertino fetch --type all
```

### Fetch Everything Including Sample Code
```bash
cupertino fetch --type all --authenticate
```

### Fetch Everything with Custom Settings
```bash
cupertino fetch --type all --max-pages 5000 --limit 100
```

## Output Structure

```
~/.cupertino/
├── docs/                     # Apple Documentation
│   ├── metadata.json
│   ├── Foundation/
│   ├── SwiftUI/
│   └── ... (~13,000 pages)
│
├── swift-book/               # Swift.org Documentation
│   ├── metadata.json
│   └── ... (~200 pages)
│
├── swift-evolution/          # Swift Evolution Proposals
│   ├── metadata.json
│   └── SE-*.md (~400 files)
│
├── packages/                 # Swift Packages Metadata
│   ├── checkpoint.json
│   └── packages-with-stars.json
│
└── sample-code/              # Apple Sample Code
    ├── checkpoint.json
    └── *.zip (~600 projects)
```

## Parallel Execution

All fetch types run **simultaneously** in separate tasks:

```
[10:30:00] 🚀 Starting Apple Documentation...
[10:30:00] 🚀 Starting Swift.org Documentation...
[10:30:00] 🚀 Starting Swift Evolution Proposals...
[10:30:00] 🚀 Starting Package Metadata...
[10:30:01] 🚀 Starting Sample Code...

[10:45:23] ✅ Completed Swift Evolution Proposals
[10:52:15] ✅ Completed Package Metadata
[11:34:28] ✅ Completed Swift.org Documentation
[14:23:45] ✅ Completed Sample Code
[22:18:32] ✅ Completed Apple Documentation

✅ All documentation types fetched successfully!
```

## Performance

| Metric | Value |
|--------|-------|
| Total download time | ~20-24 hours (parallel) |
| Total storage | ~1-2 GB |
| Total items | ~14,000+ |
| Network bandwidth | ~50-100 MB/hour average |

### Individual Type Timing

| Type | Estimated Time | Item Count |
|------|----------------|------------|
| docs | 20-24 hours | ~13,000 pages |
| swift | 15-30 minutes | ~200 pages |
| evolution | 5-15 minutes | ~400 proposals |
| packages | 10-30 minutes | ~10,000 packages |
| code | 2-6 hours | ~600 projects |

## Error Handling

If any fetch type fails:
- Other types continue running
- Final summary shows which types succeeded/failed
- Failed types can be re-run individually
- Exit code indicates partial failure

Example output with failures:
```
✅ Completed Apple Documentation
✅ Completed Swift.org Documentation
✅ Completed Swift Evolution Proposals
✅ Completed Package Metadata
❌ Failed Sample Code: Authentication required

⚠️  Completed with 1 failure(s)
```

## Option Inheritance

Options like `--max-pages`, `--force`, and `--resume` apply to all relevant fetch types:

```bash
# Force re-fetch all types
cupertino fetch --type all --force

# Resume all interrupted fetches
cupertino fetch --type all --resume

# Limit pages for web crawl types
cupertino fetch --type all --max-pages 1000
```

## Sample Code Authentication

To include sample code, add `--authenticate`:

```bash
cupertino fetch --type all --authenticate
```

Without this flag:
- Sample code fetch will fail
- Other types will complete successfully
- Warning displayed about missing authentication

## Use Cases

- **Initial setup** - Download entire corpus at once
- **Complete refresh** - Re-download everything with `--force`
- **Comprehensive coverage** - Ensure all documentation available
- **CI/CD pipelines** - Automated documentation updates
- **Research projects** - Analyze entire Apple ecosystem

## Notes

- **Most time-efficient** - Parallel execution saves time
- **Network intensive** - Downloads ~1-2 GB of data
- **Disk space** - Requires ~2-3 GB free space
- **Resumable** - Can pause and resume with `--resume`
- **Best for initial setup** - After initial fetch, use individual types for updates
- **Authentication optional** - Only required for sample code
- Compatible with `cupertino save` for search indexing all content

## Recommended Workflow

1. **Initial fetch** (one-time):
   ```bash
   cupertino fetch --type all --authenticate
   ```

2. **Build search index**:
   ```bash
   cupertino save
   ```

3. **Future updates** (individual types):
   ```bash
   cupertino fetch --type docs --resume
   cupertino fetch --type evolution
   cupertino save --clear
   ```
