# --swift

Filter search results to swift-evolution proposals implemented at or below a given Swift toolchain version.

## Usage

```bash
cupertino search "actors" --source swift-evolution --swift 5.5
```

## Description

The `--swift` option scopes search results by the Swift toolchain version a swift-evolution proposal landed in (parsed from each proposal's `Implementation: Swift X.Y` line, or its `Status: Implemented (Swift X.Y)` line as fallback).

Rows from every other source (`apple-docs`, `samples`, `hig`, `swift-org`, `swift-book`, `packages`) are filtered out when this is set — the same `NULL` rejection semantic the per-platform filters (`--min-ios`, `--min-macos`, etc.) use. Pair it with `--source swift-evolution` to make the scope explicit; without `--source`, any non-evolution row mixed into the result set is dropped silently.

## Arguments

| Argument | Type | Required | Description |
|----------|------|----------|-------------|
| `VERSION` | String | Yes | Swift toolchain version (e.g., `5.5`, `5.10`, `6.0`) |

## Examples

```bash
# Every accepted proposal that shipped in Swift 5.5 or earlier
cupertino search "actors" --source swift-evolution --swift 5.5

# Concurrency proposals up to Swift 6.0
cupertino search "concurrency" --source swift-evolution --swift 6.0

# Combine with --min-ios to find evolution proposals whose iOS-availability
# derivation also caps at iOS 16+
cupertino search "sendable" --source swift-evolution --swift 5.7 --min-ios 16.0
```

## MCP Tool Usage

When using via MCP, use the `min_swift` parameter:

```json
{
  "name": "search",
  "arguments": {
    "query": "actors",
    "source": "swift-evolution",
    "min_swift": "5.5"
  }
}
```

## Notes

- Comparison is semver-aware over the dotted-decimal version, NOT string compare — `5.10` correctly compares as **greater** than `5.2` (string compare would mistakenly accept the row).
- Single-component versions in proposal markdown (e.g. `Swift 6`) are stored normalised as `6.0`.
- Swift-evolution rows whose markdown the parser couldn't read a version from (e.g. `Status: Accepted` without an `Implementation:` line) are rejected when this filter is set — they reappear in unfiltered searches.
- Companion to `--swift-tools` on `cupertino package-search`, which filters the packages corpus by each repo's `swift-tools-version` declaration.
