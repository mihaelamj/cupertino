# --docs-dir

Directory containing crawled Apple documentation

## Synopsis

```bash
cupertino doctor --docs-dir <path>
```

## Description

Specifies the directory to check for Apple Developer Documentation. The doctor command will verify that the directory exists and contains documentation files.

## Default

`~/.cupertino/docs`

## Examples

### Check Default Documentation
```bash
cupertino doctor
```

### Check Custom Directory
```bash
cupertino doctor --docs-dir ./my-docs
```

### Check Swift.org Documentation
```bash
cupertino doctor --docs-dir ~/.cupertino/swift-book
```

### Absolute Path
```bash
cupertino doctor --docs-dir /Users/username/Documents/apple-docs
```

## Health Check Behavior

The doctor command checks:
- ✓ Directory exists
- ✓ Directory is readable
- ✓ Contains `.md` files
- ✓ Reports file count

Example output:
```
📚 Documentation Directories
   ✓ Apple docs: ~/.cupertino/docs (13,842 files)
```

If not found:
```
📚 Documentation Directories
   ✗ Apple docs: ~/.cupertino/docs (not found)
     → Run: cupertino fetch --type docs
```

## Expected Structure

```
docs-dir/
├── metadata.json           # Optional but recommended
├── Foundation/
│   ├── NSString.md
│   └── NSArray.md
├── SwiftUI/
│   ├── View.md
│   └── Text.md
└── ... (framework directories)
```

## Notes

- Tilde (`~`) expansion is supported
- Checks recursively for `.md` files
- Reports total file count
- Used by both `doctor` and `serve` commands
- Directory should be created by `cupertino fetch`
