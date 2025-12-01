# --dry-run

Show what would be cleaned without modifying files

## Synopsis

```bash
cupertino cleanup --dry-run
```

## Description

Performs a dry run that analyzes archives and reports what would be cleaned, without actually modifying any files. Use this to preview the cleanup before committing.

## Default

`false` (cleanup will modify files)

## Examples

### Preview Cleanup
```bash
cupertino cleanup --dry-run
```

### Preview with Custom Directory
```bash
cupertino cleanup --sample-code-dir ~/samples --dry-run
```

## Output

Shows:
- Number of archives found
- Items that would be removed per archive
- Estimated space savings

## Notes

- Safe to run multiple times
- No files are modified
- Recommended before first real cleanup
