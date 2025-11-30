# swift-evolution

Swift Evolution proposals source

## Synopsis

```bash
cupertino search <query> --source swift-evolution
```

## Description

Filters search results to only include Swift Evolution proposals. These are the official proposals that document changes to the Swift language.

## Content

- **Language proposals** (SE-0001 through SE-0400+)
- **Proposal status** (implemented, accepted, rejected, etc.)
- **Technical rationale** and design discussions
- **Migration guides** for language changes

## Typical Size

- **~430 proposals** indexed
- **~50 MB** on disk
- Updated as new proposals are accepted

## Examples

### Search for Concurrency Proposals
```bash
cupertino search "async await" --source swift-evolution
```

### Search for Specific Feature
```bash
cupertino search "Sendable" --source swift-evolution
```

### Find Macro Proposals
```bash
cupertino search "macro" --source swift-evolution
```

## URI Format

Results use the `swift-evolution://` URI scheme:

```
swift-evolution://{proposal-id}
```

Examples:
- `swift-evolution://SE-0001`
- `swift-evolution://SE-0296`
- `swift-evolution://SE-0302`

## How to Populate

```bash
# Fetch all proposals (2-5 minutes)
cupertino fetch --type evolution

# Build index
cupertino save
```

## Notable Proposals

| Proposal | Title |
|----------|-------|
| SE-0255 | Implicit returns from single-expression functions |
| SE-0296 | Async/await |
| SE-0302 | Sendable and @Sendable closures |
| SE-0382 | Expression macros |
| SE-0395 | Observation |

## Notes

- Fetched from GitHub swift-evolution repository
- Markdown format (fast downloads)
- Framework field is typically `nil` or `swift`
- Great for understanding language design decisions
