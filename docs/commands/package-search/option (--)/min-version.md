# --min-version

Minimum platform version for `--platform`

## Synopsis

```bash
cupertino package-search <question> --platform <platform> --min-version <version>
```

## Description

Together with `--platform`, restricts results to packages whose declared deployment target for that platform is **at or below** the named version (i.e., the package supports your target version or earlier). Required whenever `--platform` is set.

Format: dotted version string — `16.0`, `13.0`, `10.15`, etc.

## Examples

### iOS 16.0 floor
```bash
cupertino package-search "structured concurrency" --platform iOS --min-version 16.0
```

### macOS 13.0 floor
```bash
cupertino package-search "swift-syntax" --platform macos --min-version 13.0
```

### visionOS 1.0 floor
```bash
cupertino package-search "RealityKit" --platform visionOS --min-version 1.0
```

## Notes

- Comparison is lexicographic in SQL — works correctly for current Apple platform versions (iOS 13+, macOS 11+) where component widths are stable.
- Without `--platform`, this option is ignored.
- Mirrors `cupertino search --min-version` for the multi-source path. (#220)
