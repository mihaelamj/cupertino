# --docs-dir

Directory containing crawled documentation

## Synopsis

```bash
cupertino index --docs-dir <path>
```

## Description

Specifies the directory containing Markdown files from a previous crawl operation.

## Default

`~/.cupertino/docs`

## Examples

### Index Default Documentation
```bash
cupertino index
```

### Index Custom Directory
```bash
cupertino index --docs-dir ./my-docs
```

### Index Swift.org Documentation
```bash
cupertino index --docs-dir ~/.cupertino/swift-org
```

### Absolute Path
```bash
cupertino index --docs-dir /Users/username/Documents/apple-docs
```

## Expected Structure

The directory should contain:
```
docs-dir/
├── metadata.json           # Optional but recommended
├── framework1/
│   ├── page1.md
│   └── page2.md
└── framework2/
    └── page3.md
```

## Notes

- Directory must exist
- Should contain Markdown (`.md`) files
- Works with output from `cupertino crawl`
- Tilde (`~`) expansion is supported
- Recursive: indexes all `.md` files in subdirectories
