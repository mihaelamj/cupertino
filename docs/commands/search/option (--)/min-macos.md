# --min-macos

Filter search results to APIs available on a specific macOS version or earlier.

## Synopsis

```bash
cupertino search <query> --min-macos <version>
```

## Description

Filters search results to only include APIs that were introduced at or before the specified macOS version. This is useful when you need to find APIs compatible with a specific macOS deployment target.

Only returns documents that have availability data. Documents without availability information are excluded from filtered results.

## Values

Version string in `MAJOR.MINOR` format:

- `10.15` - macOS Catalina+
- `11.0` - macOS Big Sur+
- `12.0` - macOS Monterey+
- `13.0` - macOS Ventura+
- `14.0` - macOS Sonoma+
- `15.0` - macOS Sequoia+

## Examples

### Find APIs available on macOS Catalina+

```bash
cupertino search "Combine" --min-macos 10.15
```

### Find SwiftData APIs (macOS 14+)

```bash
cupertino search "SwiftData" --min-macos 14.0
```

### Combined with iOS filter

```bash
cupertino search "async await" --min-ios 15.0 --min-macos 12.0
```

## Notes

- Only documents with availability data are included in filtered results
- The filter checks if the API was **introduced** at or before the version (not deprecated)
- Use with `--framework` for more precise results
- Availability data comes from `cupertino fetch --source availability`

## See Also

- [min-ios](min-ios.md) - Filter by iOS version
- [framework](framework.md) - Filter by framework
- [source](source.md) - Filter by documentation source
