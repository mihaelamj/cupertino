# list-sources

List the installed documentation sources (per-source databases) and their schema versions.

## Synopsis

```bash
cupertino list-sources [--format <format>]
```

## Description

Reports the canonical set of per-source databases the binary expects, derived from the source
registry, so it excludes the legacy unified `search.db` and stays correct across the
per-source-DB split (#1036). Each source is annotated with whether its database file is present on
disk and the schema version read from it.

Use it to see how many of the documentation databases are installed and whether any are missing,
for example before or after `cupertino setup`.

This is the human-runnable equivalent of the `list_sources` MCP tool (#1277): a connected client
can ask a running server the same question over MCP; this command answers it from the command
line.

## Options

### --format

Output format: `text` (default) or `json`.

## Examples

```bash
# List the installed databases (human-readable)
cupertino list-sources

# Machine-parseable JSON
cupertino list-sources --format json
```

## Sample Output

```
8 of 8 databases installed:
  ✓ apple-documentation: Apple Developer Documentation (schema 18) [apple-documentation.db]
  ✓ hig: Human Interface Guidelines (schema 18) [hig.db]
  ✓ apple-sample-code: Apple Sample Code (schema 4) [apple-sample-code.db]
  ✓ apple-archive: Apple Archive (schema 18) [apple-archive.db]
  ✓ swift-evolution: Swift Evolution (schema 18) [swift-evolution.db]
  ✓ swift-org: Swift.org (schema 18) [swift-org.db]
  ✓ swift-book: Swift Book (schema 18) [swift-book.db]
  ✓ packages: Packages (schema 5) [packages.db]
```

A `✗` marks a source whose database file is not present; run `cupertino setup` to download the
bundle. The doc databases share one schema version (18 here); `apple-sample-code.db` and
`packages.db` carry their own per-database schema versions, which is expected.

## See Also

- [setup](../setup/) - download and install the databases
- [doctor](../doctor/) - full health check of every database
- [list-frameworks](../list-frameworks/) - list frameworks within the documentation sources
