# --swift-org-dir

Directory containing Swift.org documentation

## Synopsis

```bash
cupertino save --swift-org-dir <path>
```

## Description

Specifies the directory containing Swift.org documentation to include in the search index.

## Default

`~/.cupertino/swift-org`

## Examples

### Include Swift.org Documentation (Default)
```bash
cupertino save
```

### Custom Swift.org Directory
```bash
cupertino save --swift-org-dir ./my-swift-org
```

### No Swift.org Documentation
```bash
cupertino save --swift-org-dir ""
```

## Expected Structure

The directory should contain:
```
swift-org-dir/
├── documentation-page-1.md
├── documentation-page-2.md
└── ...
```

## Use Cases

- Index Swift.org documentation alongside Apple docs
- Search Swift language documentation
- Unified search across all Swift resources

## Notes

- Directory must exist if specified
- Should contain Markdown (`.md`) files from Swift.org
- Works with output from `cupertino fetch --type swift`
- Indexed separately but searchable together
- Can be empty or omitted if not needed

## See Also

- [--docs-dir](docs-dir.md) - Apple developer documentation
- [--evolution-dir](evolution-dir.md) - Swift Evolution proposals
- [--base-dir](base-dir.md) - Base directory
