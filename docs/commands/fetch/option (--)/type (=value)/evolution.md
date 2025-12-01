# --type evolution

Fetch Swift Evolution Proposals

## Synopsis

```bash
cupertino fetch --type evolution
```

## Description

Downloads all Swift Evolution proposals from the swift-evolution GitHub repository. These proposals document the evolution of the Swift programming language, including accepted features, rejected ideas, and proposals under review.

## Data Source

**Swift Evolution GitHub Repository** - https://github.com/apple/swift-evolution

## Output

Creates Markdown files for each proposal:
- One `.md` file per proposal (e.g., `SE-0001.md`)
- Original formatting preserved
- Metadata tracking in `metadata.json`

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/swift-evolution` |
| Source | GitHub swift-evolution repository |
| Fetch Method | Direct GitHub raw content download |
| Authentication | Not required (GitHub API) |
| Estimated Count | ~400-450 proposals |

## Examples

### Fetch All Proposals
```bash
cupertino fetch --type evolution
```

### Fetch Only Accepted/Implemented Proposals
```bash
cupertino fetch --type evolution --only-accepted
```

### Resume Interrupted Download
```bash
cupertino fetch --type evolution --resume
```

### Force Re-download All Proposals
```bash
cupertino fetch --type evolution --force
```

### Custom Output Directory
```bash
cupertino fetch --type evolution --output-dir ./evolution
```

## Output Structure

```
~/.cupertino/swift-evolution/
├── metadata.json
├── SE-0001.md    # Allow (most) keywords as argument labels
├── SE-0002.md    # Removing currying func declaration syntax
├── SE-0003.md    # Removing var from Function Parameters
├── SE-0296.md    # Async/await
├── SE-0297.md    # Concurrency Interoperability with Objective-C
└── ... (~400 proposals)
```

## Proposal Status Types

Proposals have various statuses:
- **Implemented** - Accepted and shipped in Swift
- **Accepted** - Approved but not yet implemented
- **Active Review** - Currently under community review
- **Returned for Revision** - Needs changes
- **Rejected** - Not accepted
- **Withdrawn** - Author withdrew proposal
- **Deferred** - Postponed to future Swift version

## Filtering Options

### `--only-accepted` Flag

When using `--only-accepted`, only downloads proposals with status:
- Implemented (Swift X.X)
- Accepted

This excludes:
- Rejected proposals
- Withdrawn proposals
- Proposals under review

```bash
cupertino fetch --type evolution --only-accepted
```

## Metadata File

`metadata.json` tracks proposals:

```json
{
  "version": "1.0",
  "source": "swift-evolution",
  "totalProposals": 414,
  "lastUpdated": "2025-11-19T10:30:00Z",
  "proposals": {
    "SE-0296": {
      "title": "Async/await",
      "status": "Implemented (Swift 5.5)",
      "contentHash": "a1b2c3d4...",
      "lastFetched": "2025-11-19T10:30:00Z"
    }
  }
}
```

## Notable Proposals

### Concurrency
- **SE-0296** - Async/await
- **SE-0297** - Concurrency interoperability with Objective-C
- **SE-0304** - Structured concurrency
- **SE-0306** - Actors

### Modern Swift Features
- **SE-0255** - Implicit returns from single-expression functions
- **SE-0279** - Multiple trailing closures
- **SE-0293** - Extend property wrappers to function and closure parameters
- **SE-0346** - Lightweight same-type requirements for primary associated types

### SwiftUI-Related
- **SE-0258** - Property wrappers
- **SE-0289** - Result builders

## Performance

| Metric | Value |
|--------|-------|
| Download time | 5-15 minutes (400+ proposals) |
| Incremental update | Minutes (only changed/new) |
| Average file size | 10-50 KB |
| Total storage | ~5-10 MB |

## Use Cases

- Swift language evolution research
- Understanding Swift feature history
- Proposal reference and lookup
- Language design study
- Community proposal tracking
- Full-text search of proposals

## Notes

- Downloads directly from GitHub raw content
- No web crawling required
- Faster than web crawling (direct downloads)
- Proposals are official Swift evolution documents
- Compatible with `cupertino save` for search indexing
- Regularly updated as new proposals are added
- Each proposal includes rationale, design, and alternatives
