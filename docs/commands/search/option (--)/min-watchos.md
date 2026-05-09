# --min-watchos

Filter search results to APIs available on or before a specific watchOS version.

## Usage

```bash
cupertino search "health" --min-watchos 6.0
```

## Description

The `--min-watchos` option filters search results to only show documentation for APIs that were introduced in the specified watchOS version or earlier. This is useful when developing for older watchOS versions and you need to ensure API compatibility.

## Arguments

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `VERSION` | String | Yes | watchOS version number (e.g., "6.0", "8.0") |

## Examples

```bash
# Find APIs available on watchOS 6.0 or earlier
cupertino search "health" --min-watchos 6.0

# Combine with framework filter
cupertino search "workout" --framework healthkit --min-watchos 7.0

# Combine with multiple platform filters
cupertino search "notification" --min-ios 15.0 --min-watchos 8.0
```

## MCP Tool Usage

When using via MCP, use the `min_watchos` parameter:

```json
{
  "name": "search",
  "arguments": {
    "query": "health",
    "min_watchos": "6.0"
  }
}
```

## Notes

- Results without watchOS availability information are excluded when this filter is active
- Version comparison is semantic (e.g., "6.0" < "6.2" < "7.0")
- Can be combined with other platform filters (`--min-ios`, `--min-macos`, `--min-tvos`, `--min-visionos`)
