# --packages-dir

Directory containing package READMEs

## Synopsis

```bash
cupertino save --packages-dir <path>
```

## Description

Specifies the directory containing Swift package README files to include in the search index.

## Default

`~/.cupertino/packages`

## Examples

### Include Package READMEs (Default)
```bash
cupertino save
```

### Custom Packages Directory
```bash
cupertino save --packages-dir ./my-packages
```

### No Package Documentation
```bash
cupertino save --packages-dir ""
```

## Expected Structure

The directory should contain:
```
packages-dir/
├── package1-README.md
├── package2-README.md
└── ...
```

## Use Cases

- Index Swift package documentation alongside Apple docs
- Search package READMEs
- Unified search across all Swift resources

## Notes

- Directory must exist if specified
- Should contain README Markdown (`.md`) files from Swift packages
- Works with output from `cupertino fetch --type packages`
- Indexed separately but searchable together
- Can be empty or omitted if not needed

## See Also

- [--docs-dir](docs-dir.md) - Apple developer documentation
- [--evolution-dir](evolution-dir.md) - Swift Evolution proposals
- [--base-dir](base-dir.md) - Base directory
