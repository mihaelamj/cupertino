# --min-visionos

Filter search results to APIs available on or before a specific visionOS version.

## Usage

```bash
cupertino search "immersive" --min-visionos 1.0
```

## Description

The `--min-visionos` option filters search results to only show documentation for APIs that were introduced in the specified visionOS version or earlier. This is useful when developing for Apple Vision Pro and you need to ensure API compatibility.

## Arguments

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `VERSION` | String | Yes | visionOS version number (e.g., "1.0", "2.0") |

## Examples

```bash
# Find APIs available on visionOS 1.0 (initial release)
cupertino search "immersive" --min-visionos 1.0

# Combine with framework filter
cupertino search "spatial" --framework realitykit --min-visionos 1.0

# Combine with multiple platform filters
cupertino search "view" --min-ios 17.0 --min-visionos 1.0
```

## MCP Tool Usage

When using via MCP, use the `min_visionos` parameter:

```json
{
  "name": "search",
  "arguments": {
    "query": "immersive",
    "min_visionos": "1.0"
  }
}
```

## Notes

- Results without visionOS availability information are excluded when this filter is active
- visionOS 1.0 was released with Apple Vision Pro in 2024
- Can be combined with other platform filters (`--min-ios`, `--min-macos`, `--min-tvos`, `--min-watchos`)
