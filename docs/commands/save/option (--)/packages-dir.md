# --packages-dir

Directory containing Swift package source trees

## Synopsis

```bash
cupertino save --source packages --packages-dir <path>
```

## Description

Specifies the directory containing Swift package source trees to include in `packages.db`.

## Default

`~/.cupertino/packages`

## Examples

### Include Packages (Default)
```bash
cupertino save --all
```

### Custom Packages Directory
```bash
cupertino save --source packages --packages-dir ./my-packages
```

### No Package Documentation
```bash
cupertino save --source packages --packages-dir ""
```

## Expected Structure

The directory should contain:
```
packages-dir/
├── owner/
│   └── repo/
│       ├── README.md
│       ├── Package.swift
│       └── Sources/
└── ...
```

## Use Cases

- Index Swift package source, READMEs, manifests, and DocC content
- Search package code and documentation
- Unified search across all Swift resources

## Notes

- Directory must exist if specified
- Should contain extracted Swift package source trees from `cupertino fetch --source packages`
- Works with output from `cupertino fetch --source packages`
- Indexed separately but searchable together
- Can be empty or omitted if not needed

## See Also

- [--docs-dir](docs-dir.md) - Apple developer documentation
- [--evolution-dir](evolution-dir.md) - Swift Evolution proposals
- [--base-dir](base-dir.md) - Base directory
