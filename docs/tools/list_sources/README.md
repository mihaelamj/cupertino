# list_sources

List the installed documentation sources (per-source databases) and their schema versions.

## Synopsis

```json
{
  "name": "list_sources",
  "arguments": {}
}
```

## Description

Returns the canonical set of per-source databases the server expects, derived from the source
registry, so it excludes the legacy unified `search.db` and stays correct across the
per-source-DB split (#1036). Each source is annotated with whether its database file is present
and the schema version read from it.

UI clients (cupertino-desktop) use this to detect a missing or partial corpus and guide the user
to run `cupertino setup`, instead of scanning the filesystem and hardcoding database filenames.
It is the MCP sibling of [`cupertino list-sources`](../../commands/list-sources/), and is
advertised whenever the server is running (the composition root always supplies the inventory).

## Parameters

None.

## Response

A `SourceInventory` JSON object:

```json
{
  "sources": [
    { "id": "apple-documentation", "displayName": "Apple Developer Documentation", "filename": "apple-documentation.db", "present": true, "schemaVersion": 18 },
    { "id": "packages", "displayName": "Packages", "filename": "packages.db", "present": false, "schemaVersion": 0 }
  ]
}
```

- `present` is whether the database file exists on disk.
- `schemaVersion` is read from the database (`0` when absent or unreadable).
- The number of entries is the canonical count of documentation databases (8 on a complete
  install). The legacy unified `search.db` is never listed.

## See Also

- [`cupertino list-sources`](../../commands/list-sources/) - the CLI equivalent
- [setup](../../commands/setup/) - download and install the databases
- [doctor](../../commands/doctor/) - full per-database health check
