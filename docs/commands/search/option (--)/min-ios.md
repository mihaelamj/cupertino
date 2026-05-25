# --min-ios

Filter search results to APIs available on a specific iOS version or earlier.

## Synopsis

```bash
cupertino search <query> --min-ios <version>
```

## Description

Filters search results to only include APIs that were introduced at or before the specified iOS version. This is useful when you need to find APIs compatible with a specific iOS deployment target.

Only returns documents that have availability data. Documents without availability information are excluded from filtered results.

## Values

Version string in `MAJOR.MINOR` format:

- `13.0` - iOS 13.0+
- `14.0` - iOS 14.0+
- `15.0` - iOS 15.0+
- `16.0` - iOS 16.0+
- `17.0` - iOS 17.0+
- `18.0` - iOS 18.0+

## Examples

### Find APIs available on iOS 13+

```bash
cupertino search "Combine" --min-ios 13.0
```

### Find SwiftUI APIs available on iOS 17+

```bash
cupertino search "Observable" --min-ios 17.0 --framework swiftui
```

### Combined with macOS filter

```bash
cupertino search "async await" --min-ios 15.0 --min-macos 12.0
```

## Notes

- Only documents with availability data are included in filtered results
- The filter checks if the API was **introduced** at or before the version (not deprecated)
- Use with `--framework` for more precise results
- Availability data comes from `cupertino fetch --source availability`

## See Also

- [min-macos](min-macos.md) - Filter by macOS version
- [framework](framework.md) - Filter by framework
- [source](source.md) - Filter by documentation source
