# swift-evolution/ - Swift Evolution Proposals

Swift Evolution proposals documenting the evolution of the Swift language.

## Location

**Default**: `~/.cupertino/swift-evolution/`

## Created By

```bash
# All proposals
cupertino crawl --type evolution

# Only accepted/implemented
cupertino crawl --type evolution --only-accepted
```

## Structure

```
~/.cupertino/swift-evolution/
├── metadata.json                # Crawl metadata
└── proposals/
    ├── SE-0001-keywords-as-argument-labels.md
    ├── SE-0002-remove-currying.md
    ├── SE-0003-remove-var-parameters.md
    ├── SE-0004-remove-pre-post-inc-decrement.md
    ├── SE-0005-objective-c-name-translation.md
    └── ...                      # 400+ proposals
```

## Contents

### Proposal Files
- One Markdown file per proposal
- Numbered: SE-NNNN-description.md
- Contains full proposal text
- Includes status, rationale, implementation notes

### Proposal Statuses
- **Implemented** - In current Swift
- **Accepted** - Approved, being implemented
- **Rejected** - Not accepted
- **Under Review** - Being reviewed
- **Withdrawn** - Proposal withdrawn
- **Returned for Revision** - Needs changes

## Filtering

### Get Only Accepted
```bash
cupertino crawl --type evolution --only-accepted
```

Downloads only proposals with status:
- ✅ Accepted
- ✅ Implemented

## Files

### Proposal Files (.md)
- Original proposal content
- Formatted Markdown
- Links to related proposals
- Implementation details

### [metadata.json](../docs/metadata.json.md)
- Tracks all downloaded proposals
- Status information
- Change detection

## Size

- **~400-500 proposals** total
- **~100-200 proposals** if using `--only-accepted`
- **~50-100 MB** total

## Usage

### Search Proposals
```bash
# Build search index
cupertino index --evolution-dir ~/.cupertino/swift-evolution
```

### Browse Locally
```bash
# Open proposals folder
open ~/.cupertino/swift-evolution/proposals/
```

### Find Specific Proposal
```bash
# Search for SE-0123
ls ~/.cupertino/swift-evolution/proposals/SE-0123*.md
```

## Customizing Location

```bash
# Use custom directory
cupertino crawl --type evolution --output-dir ./evolution
```

## Notes

- Proposals are numbered chronologically
- Use `--only-accepted` to reduce download size
- Complete history of Swift's evolution
- Valuable for understanding language design decisions
