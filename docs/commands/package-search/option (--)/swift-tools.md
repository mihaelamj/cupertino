# --swift-tools

Restrict results to packages whose authored Swift compiler floor is at or above the given version.

## Synopsis

```bash
cupertino package-search <question> --swift-tools <version>
```

## Description

Filters the candidate set to packages whose `Package.swift` declares a `// swift-tools-version: X.Y` at or above `--swift-tools`. The declaration is parsed once during `cupertino fetch --type packages` (via the same annotation pass that captures deployment-target platforms) and stored in `package_metadata.swift_tools_version`.

This is the authored Swift compiler floor — the version the package author declared their manifest is compatible with. It is **not** derived from the deployment-target platform versions (`--platform iOS --min-version 16` would loosely imply Swift 5.7+, but a package targeting iOS 13 can still be authored against Swift 6).

Packages with **no** `swift-tools-version` declaration in their manifest (older corpora, packages whose manifest doesn't carry a parseable declaration on the first non-blank line) are dropped from the result set when `--swift-tools` is in effect. The filter is exclusive — "unknown" Swift floor is treated as "doesn't match the requested floor".

`--swift-tools` is **orthogonal** to `--platform` / `--min-version`. Both can be set on the same query; they filter on different axes (Swift compiler vs. deployment target) and stack as AND.

## Values

A dotted-decimal Swift major.minor version (e.g. `5.7`, `5.9`, `6.0`, `6.2`). Patch-level versions are stripped on the indexer side (a manifest declaring `5.7.1` indexes as `5.7`); pass `--swift-tools 5.7` to match those rows.

Lexicographic compare in SQL — correct for current Swift majors 4.x through 6.x where minor widths are uniform. If Swift ever ships a minor wider than the current 2-digit conventions (e.g. `6.10` vs `6.2`), this filter will mis-order; the assumption matches what the issue body (#225) explicitly scoped in.

## Examples

### Swift 6.0+ packages

```bash
cupertino package-search "concurrency patterns" --swift-tools 6.0
```

### Swift 5.9+ packages on iOS 16+ (both filters stack)

```bash
cupertino package-search "navigation stack" \
    --platform iOS --min-version 16.0 \
    --swift-tools 5.9
```

### Find packages authored against the latest Swift

```bash
cupertino package-search "async stream throwing" --swift-tools 6.2
```

## See Also

- `--platform` / `--min-version` — orthogonal filter on the package's deployment-target platforms
- `cupertino fetch --type packages` — populates the `swift_tools_version` column during the annotation pass
- Issue #225 — the design rationale (Swift compiler floor is a distinct axis from platform deployment target)
