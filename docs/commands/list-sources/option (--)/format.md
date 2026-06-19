# --format

Output format for the source inventory

## Synopsis

```bash
cupertino list-sources --format <format>
```

## Description

Controls how the per-source database inventory is rendered. Different formats suit a human reader
versus a programmatic consumer.

## Values

| Format | Description |
|--------|-------------|
| `text` | Human-readable: an `N of M databases installed:` header followed by one `✓/✗ id: displayName (schema V) [filename]` row per source (default) |
| `json` | A `SourceInventory` object: `{ "sources": [ { "id", "displayName", "filename", "present", "schemaVersion" }, ... ] }` |

## Default

`text`

## Examples

### Default text output
```bash
cupertino list-sources
```

### JSON for programmatic consumers
```bash
cupertino list-sources --format json | jq '.sources | map(select(.present == false)) | .[].id'
```

(Lists the ids of any declared source whose database file is missing.)

## Notes

- The set of sources is the registry-declared active set (the canonical per-source databases),
  excluding the legacy unified `search.db`, so the count is the authoritative number of
  documentation databases.
- This is the same data the `list_sources` MCP tool returns to a connected client.
