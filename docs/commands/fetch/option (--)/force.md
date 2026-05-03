# --force

Force re-download of existing files

## Synopsis

```bash
cupertino fetch --type <type> --force
```

## Description

Forces re-downloading of all files, even if they already exist. Ignores checkpoint and re-fetches everything.

## Default Behavior (Without --force)

- Checks if files already exist
- Skips downloading existing files
- Uses checkpoint to resume efficiently

## With --force

- Re-downloads all files
- Overwrites existing files
- Ignores checkpoint progress
- Starts from beginning

## Examples

### Force Re-download All Packages
```bash
cupertino fetch --type packages --force
```

### Force Re-download Sample Code
```bash
cupertino fetch --type code --force
```

### Force with Limit
```bash
cupertino fetch --type packages --force --limit 100
```

## Use Cases

- Files were corrupted
- Want fresh copies of everything
- Checkpoint file is invalid
- Files were modified externally

## Notes

- Overwrites existing files without confirmation
- Can be slower than regular fetch
- Re-fetches every page; combine with `--start-clean` for a true ground-zero rerun
- Resets per-page change-detection hashes
