# --min-tvos

Filter search results to APIs available on or before a specific tvOS version.

## Usage

```bash
cupertino search "animation" --min-tvos 13.0
```

## Description

The `--min-tvos` option filters search results to only show documentation for APIs that were introduced in the specified tvOS version or earlier. This is useful when developing for older tvOS versions and you need to ensure API compatibility.

## Arguments

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `VERSION` | String | Yes | tvOS version number (e.g., "13.0", "15.0") |

## Examples

```bash
# Find APIs available on tvOS 13.0 or earlier
cupertino search "animation" --min-tvos 13.0

# Combine with framework filter
cupertino search "player" --framework avfoundation --min-tvos 15.0

# Combine with multiple platform filters
cupertino search "view" --min-ios 15.0 --min-tvos 15.0
```

## MCP Tool Usage

When using via MCP, use the `min_tvos` parameter:

```json
{
  "name": "search",
  "arguments": {
    "query": "animation",
    "min_tvos": "13.0"
  }
}
```

## Notes

- Results without tvOS availability information are excluded when this filter is active
- Version comparison is semantic (e.g., "13.0" < "13.1" < "14.0")
- Can be combined with other platform filters (`--min-ios`, `--min-macos`, `--min-watchos`, `--min-visionos`)
