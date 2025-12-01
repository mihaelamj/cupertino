# cleanup

Clean up downloaded sample code archives

## Synopsis

```bash
cupertino cleanup [--sample-code-dir <dir>] [--dry-run] [--keep-originals]
```

## Description

Removes unnecessary files from sample code ZIP archives to reduce disk space. This can reduce storage from ~26GB to ~2-3GB for a full sample code download.

## Files Removed

- `.git` folders (often 7+ MB each)
- `.DS_Store` files
- `xcuserdata` folders
- `DerivedData` folders
- Build artifacts
- `Pods` folders
- `.swiftpm` folders
- `__MACOSX` folders

## Options

| Option | Description |
|--------|-------------|
| `--sample-code-dir` | Sample code directory to clean |
| `--dry-run` | Show what would be cleaned without modifying |
| `--keep-originals` | Save cleaned as `.cleaned.zip`, keep originals |

## Examples

### Dry Run
```bash
cupertino cleanup --dry-run
```

### Clean Default Directory
```bash
cupertino cleanup
```

### Keep Original Files
```bash
cupertino cleanup --keep-originals
```

### Custom Directory
```bash
cupertino cleanup --sample-code-dir ~/my-samples
```

## Default Directory

`~/.cupertino/sample-code`

## Output

Shows progress and statistics:
- Total archives processed
- Cleaned vs skipped count
- Original and cleaned sizes
- Space saved (percentage)
- Duration

## Notes

- Run `cupertino fetch --type code` first to download sample code
- Backup important files before running without `--dry-run`
- Use `--keep-originals` for safe first run
