# --output-dir

Output directory for downloaded resources

## Synopsis

```bash
cupertino fetch --source <type> --output-dir <path>
```

## Description

Specifies where to save the fetched resources.

## Default

Depends on `--source`:
- `packages`: `~/.cupertino/packages`
- `code`: `~/.cupertino/sample-code`

## Examples

### Custom Output for Packages
```bash
cupertino fetch --source packages --output-dir ./my-packages
```

### Custom Output for Sample Code
```bash
cupertino fetch --source apple-sample-code --output-dir ./sample-code
```

### Absolute Path
```bash
cupertino fetch --source packages --output-dir /Users/username/Documents/swift-packages
```

## Output Structure

### For packages
```
output-dir/
└── checkpoint.json    # All package metadata
```

### For code
```
output-dir/
├── checkpoint.json                                    # Progress tracking
├── swiftui-building-lists.zip
├── arkit-creating-ar-experience.zip
└── ...                                               # 600+ ZIP files
```

## Notes

- Directory is created if it doesn't exist
- Tilde (`~`) expansion is supported
- Checkpoint file is always in the output directory
