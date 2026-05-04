# --refresh

Re-resolve the package closure even if cached (hidden)

## Synopsis

```bash
cupertino fetch --type packages --refresh
```

## Description

Forces the priority-package dependency resolver to re-resolve from scratch instead of reusing the cached `~/.cupertino/resolved-packages.json`. Use after editing `priority-packages.json` or when manifest changes upstream invalidate the cached closure.

## Default

`false`

## Example

```bash
cupertino fetch --type packages --refresh
```

## Notes

- Hidden flag in `--help` (still functional).
- The cache stores parentage + checksum so the resolver can detect when a re-resolve is unnecessary; `--refresh` bypasses that check.
