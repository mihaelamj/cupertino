# --evolution-dir

Directory containing Swift Evolution proposals

## Synopsis

```bash
cupertino save --evolution-dir <path>
```

## Description

Specifies the directory containing Swift Evolution proposal Markdown files to include in the search index.

## Default

`~/.cupertino/swift-evolution`

## Examples

### Include Evolution Proposals (Default)
```bash
cupertino save
```

### Custom Evolution Directory
```bash
cupertino save --evolution-dir ./my-evolution
```

### No Evolution Proposals
```bash
cupertino save --evolution-dir ""
```

## Expected Structure

The directory should contain:
```
evolution-dir/
├── proposal-0001.md
├── proposal-0002.md
└── ...
```

## Use Cases

- Index both Apple docs and Swift Evolution together
- Search proposals alongside documentation
- Unified search across all Swift resources

## Notes

- Directory must exist if specified
- Should contain Markdown (`.md`) files from Swift Evolution
- Works with output from `cupertino fetch --type evolution`
- Indexed separately but searchable together
- Can be empty or omitted if not needed
