# --verify

During `--dry-run`, open each archive with `zipinfo` to count cleanup candidates exactly.

## Synopsis

```bash
cupertino cleanup --dry-run --verify
```

## Description

By default, `cupertino cleanup --dry-run` is **stat-only**: it lists every ZIP archive in the sample-code directory and reports the count + cumulative on-disk size without opening any archives. This completes in seconds on the default ~620-zip corpus.

`--verify` opts back into the pre-#656 behaviour: each archive is opened with `/usr/bin/zipinfo` and scanned for cleanup-pattern matches (`.git`, `xcuserdata`, `DerivedData`, etc.) so the dry-run report carries an accurate "items to remove" count. Use it when you want the precise per-archive savings estimate; expect minutes of wall time on a full corpus.

The flag is a no-op when `--dry-run` is not set — real cleanup always extracts + scans + (optionally) recompresses, so the verification work is implicit.

## Default

`false` — stat-only dry-run.

## Examples

### Fast preview (default)
```bash
cupertino cleanup --dry-run
```
Reports archive count + total size in <1 s. `Items to remove` is reported as 0.

### Accurate per-archive scan (slow)
```bash
cupertino cleanup --dry-run --verify
```
Reports archive count + total size + exact items-to-remove count after walking every archive. Expect minutes on a 600+ zip corpus.

## Why it's off by default

`#656` — pre-fix, every dry-run forked `/usr/bin/zipinfo` 600+ times in series, turning a "preview" into ~3 minutes of work. Most operators want dry-run to answer "do I have a corpus to clean?" — which the stat-only fast path already answers. Users who specifically want the items-to-remove count opt in.

## Notes

- Has no effect outside of `--dry-run`.
- The `--verify` path reads-only; no files are modified.
- See also: `--dry-run`, `--keep-originals`.
