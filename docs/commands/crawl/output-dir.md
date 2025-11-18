# --output-dir

Output directory for crawled documentation

## Synopsis

```bash
cupertino crawl --output-dir <path>
```

## Description

Specifies where to save the crawled Markdown files and metadata.

## Default

Depends on `--type`:
- `docs`: `~/.cupertino/docs`
- `swift`: `~/.cupertino/swift-org`
- `evolution`: `~/.cupertino/swift-evolution`
- `packages`: `~/.cupertino/packages`

## Examples

### Custom Output Directory
```bash
cupertino crawl --output-dir ./my-docs
```

### Absolute Path
```bash
cupertino crawl --output-dir /Users/username/Documents/apple-docs
```

### Relative Path
```bash
cupertino crawl --output-dir ../documentation
```

## Output Structure

The output directory will contain:
```
output-dir/
├── metadata.json           # Crawl metadata and content hashes
├── framework-name/         # Directories mirror URL structure
│   ├── page1.md
│   ├── page2.md
│   └── subfolder/
│       └── page3.md
└── ...
```

## Notes

- Directory is created if it doesn't exist
- Tilde (`~`) expansion is supported
- Metadata file is always named `metadata.json` in the output directory
