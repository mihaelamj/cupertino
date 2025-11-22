# --evolution-dir

Directory containing Swift Evolution proposals

## Synopsis

```bash
cupertino doctor --evolution-dir <path>
```

## Description

Specifies the directory to check for Swift Evolution proposal files. The doctor command will verify that the directory exists and contains proposal Markdown files.

## Default

`~/.cupertino/swift-evolution`

## Examples

### Check Default Evolution Directory
```bash
cupertino doctor
```

### Check Custom Directory
```bash
cupertino doctor --evolution-dir ./my-evolution
```

### Absolute Path
```bash
cupertino doctor --evolution-dir /Users/username/Documents/swift-evolution
```

## Health Check Behavior

The doctor command checks:
- ✓ Directory exists
- ✓ Directory is readable
- ✓ Contains proposal files (SE-*.md)
- ✓ Reports proposal count

Example output:
```
📚 Documentation Directories
   ✓ Swift Evolution: ~/.cupertino/swift-evolution (414 proposals)
```

If not found (warning, not failure):
```
📚 Documentation Directories
   ⚠  Swift Evolution: ~/.cupertino/swift-evolution (not found)
     → Run: cupertino fetch --type evolution
```

## Expected Structure

```
evolution-dir/
├── metadata.json           # Optional
├── SE-0001.md
├── SE-0002.md
├── SE-0296.md              # Async/await
├── SE-0297.md              # Concurrency
└── ... (~400 proposals)
```

## Notes

- Tilde (`~`) expansion is supported
- Checks for `.md` files in root directory
- Reports total proposal count
- **Warning only** if missing (not required for server to run)
- Used by both `doctor` and `serve` commands
- Directory should be created by `cupertino fetch --type evolution`
- Evolution proposals are optional but recommended
