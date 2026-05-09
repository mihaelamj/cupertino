# --platform

Restrict results to packages compatible with a named platform

## Synopsis

```bash
cupertino package-search <question> --platform <platform> --min-version <version>
```

## Description

Filters the candidate set to packages whose declared deployment target is compatible with the named Apple platform. The package's deployment-target metadata is harvested during `cupertino fetch --type packages` (annotated by `--annotate-availability`) and stored in `packages.db`.

Packages with **no** annotation source (no `Package.swift` deployment-targets parsed, no per-package `availability.json`) are dropped from the result set when `--platform` is in effect — the filter is exclusive, not best-effort.

`--platform` requires `--min-version`.

## Values

`iOS`, `macOS`, `tvOS`, `watchOS`, `visionOS`. Case-insensitive.

## Examples

### iOS 16+ packages only
```bash
cupertino package-search "async stream" --platform iOS --min-version 16.0
```

### macOS 13+ packages
```bash
cupertino package-search "swift-syntax" --platform macos --min-version 13.0
```

## Notes

- Lexicographic version compare in SQL — works correctly for current Apple platform versions (iOS 13+, macOS 11+, etc.) where component widths are stable.
- Mirrors `cupertino search --platform` for the multi-source path. (#220)
- Without `--platform`, every package in `packages.db` is eligible.
