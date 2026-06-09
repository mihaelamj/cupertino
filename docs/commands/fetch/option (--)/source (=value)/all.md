# --source all

Fetch all fetchable sources

## Synopsis

```bash
cupertino fetch --source all
```

## Description

Fetches all fetchable sources in parallel: Apple docs, Swift.org docs, the Swift Book, Swift Evolution proposals, HIG, Apple Archive, Swift package archives, Apple sample-code ZIPs, the GitHub sample-code mirror, and the availability maintenance pass. This is the most comprehensive local rebuild path; most users should prefer `cupertino setup`.

## Fetched Sources

Runs every non-`all` fetchable source **in parallel**:

1. **apple-docs**, Apple Developer Documentation
2. **swift-org**, Swift.org documentation
3. **swift-book**, The Swift Programming Language book
4. **swift-evolution**, Swift Evolution proposals
5. **packages**, priority Swift package source archives; metadata refresh is opt-in via `--refresh-metadata`
6. **apple-sample-code**, Apple sample-code ZIPs from `developer.apple.com/sample-code` (requires Safari sign-in for cookie reuse)
7. **samples**, sample-code projects from GitHub (recommended path for sample data)
8. **apple-archive**, Apple Archive legacy programming guides
9. **hig**, Human Interface Guidelines
10. **availability**, API version-info pass over an existing docs corpus

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/` (base directory) |
| Execution Mode | Parallel (all sources simultaneously) |
| Authentication | Required for sample code only |
| Estimated Total Pages | ~404,000+ items |

## Examples

### Fetch Everything
```bash
cupertino fetch --source all
```

### Fetch Everything with Custom Settings
```bash
cupertino fetch --source all --max-pages 5000 --limit 100
```

## Output Structure

```
~/.cupertino/
├── docs/                     # Apple Documentation
│   ├── metadata.json
│   ├── Foundation/
│   ├── SwiftUI/
│   └── ... (~404,000+ pages)
│
├── swift-org/                # Swift.org documentation
│   ├── metadata.json
│   └── ... (~500 pages)
│
├── swift-book/               # The Swift Programming Language
│   ├── metadata.json
│   └── ... (~40 pages)
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

All fetchable sources run **simultaneously** in separate tasks:

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

✅ All documentation sources fetched successfully!
```

## Performance

| Metric | Value |
|--------|-------|
| Total download time | dominated by Apple docs; multi-day for a full crawl |
| Total storage | several GB of raw corpus data before indexing |
| Total items | Apple docs alone are ~404,000 raw pages; other source counts vary |
| Network bandwidth | source-dependent |

### Individual Type Timing

| Source | Estimated Time | Item Count |
|------|----------------|------------|
| apple-docs | 12+ days | ~404,000+ raw pages |
| swift-org | 15-30 minutes | ~500 pages |
| swift-book | minutes | ~40 pages |
| swift-evolution | 5-15 minutes | ~400 proposals |
| packages | ~100 seconds for priority archives; metadata refresh is hours without `GITHUB_TOKEN` | 185 indexed release packages / larger SPI metadata catalog |
| apple-sample-code | 2-6 hours | ~600 projects |
| samples | minutes, dominated by Git LFS bandwidth | 619 projects |

## Error Handling

If any fetch source fails:
- Other sources continue running
- Final summary shows which sources succeeded/failed
- Failed sources can be re-run individually
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

Options like `--max-pages`, `--force`, and `--start-clean` apply to all relevant fetch sources:

```bash
# Force re-fetch all sources
cupertino fetch --source all --force

# Discard saved sessions and start every source fresh
cupertino fetch --source all --start-clean

# Limit pages for web-crawl sources
cupertino fetch --source all --max-pages 1000
```

Resume is automatic across all sources, interrupted fetches pick up where they left off on the next run with no flag.

## Sample Code Authentication

To include `--source apple-sample-code`, sign in to `https://developer.apple.com/` in Safari first. The fetcher reuses Safari's `myacinfo` cookie from the system cookie store:

```bash
cupertino fetch --source all
```

Without a valid Safari sign-in:
- Sample code fetch will fail
- Other sources will complete successfully
- Warning displayed about missing cookie

Alternative: drop `code` and use `samples` (GitHub mirror, no auth required) for sample-code coverage.

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
- **Resumable** - Interrupted runs auto-resume on the next invocation; pass `--start-clean` to override
- **Best for initial setup** - After initial fetch, use individual types for updates
- **Authentication optional** - Only required for sample code
- Compatible with `cupertino save` for search indexing all content

## Recommended Workflow

1. **Initial fetch** (one-time):
   ```bash
   cupertino fetch --source all
   ```

2. **Build search index**:
   ```bash
   cupertino save --all
   ```

3. **Future updates** (individual types):
   ```bash
   cupertino fetch --source apple-docs        # auto-resumes if interrupted previously
   cupertino fetch --source swift-evolution
   cupertino save --all --clear
   ```
