# --type evolution

Crawl Swift Evolution Proposals

## Synopsis

```bash
cupertino crawl --type evolution
```

## Description

Crawls Swift Evolution proposals from swift.org/swift-evolution. These are the proposals that drive the evolution of the Swift language.

## Default Settings

| Setting | Value |
|---------|-------|
| Start URL | `https://www.swift.org/swift-evolution` |
| Output Directory | `~/.cupertino/swift-evolution` |
| URL Prefix | `https://www.swift.org/swift-evolution/` |

## What Gets Crawled

- All Swift Evolution proposals (SE-NNNN)
- Proposal status (Accepted, Implemented, Rejected, etc.)
- Proposal content and rationale
- Implementation details

## Special Option

Use `--only-accepted` to download only accepted/implemented proposals:

```bash
cupertino crawl --type evolution --only-accepted
```

See [--only-accepted](../only-accepted.md) for details.

## Examples

### Crawl All Proposals
```bash
cupertino crawl --type evolution
```

### Crawl Only Accepted Proposals
```bash
cupertino crawl --type evolution --only-accepted
```

### Limited Crawl
```bash
cupertino crawl --type evolution --max-pages 100
```

## Output Structure

```
~/.cupertino/swift-evolution/
├── metadata.json
├── proposals/
│   ├── SE-0001.md
│   ├── SE-0002.md
│   └── ...
└── ...
```

## Proposal Statuses

- **Implemented** - Feature is in Swift
- **Accepted** - Approved, being implemented
- **Rejected** - Not accepted
- **Under Review** - Being reviewed
- **Withdrawn** - Proposal withdrawn

## Notes

- Hundreds of proposals available
- Use `--only-accepted` to filter by status
- Each proposal is a separate page
- Historical record of Swift's evolution
