# --save

Include the maintenance-side sections in the doctor report (additive on top of the default health suite)

## Synopsis

```bash
cupertino doctor --save
```

## Description

Adds the `cupertino save` maintenance sections to the regular doctor output. The default health suite (MCP server health, providers, the three database sections, schema versions) still runs; `--save` appends:

- 📂 Raw corpus directories (the inputs `cupertino save` would consume)
- 📦 Swift Packages: user selection state + downloaded README counts + orphan / missing tallies
- 🔍 `cupertino save` per-source preflight summary: which sources are present, sidecar coverage, annotation status (backed by `Indexer.Preflight.preflightLines(...)`, lifted in [#244](https://github.com/mihaelamj/cupertino/issues/244))

Use this before `cupertino save` to confirm sources + selections are ready, or after `cupertino fetch` to verify the corpus dirs look right. Read-only, no DB writes.

## Default

`false` (default doctor output is DB + MCP only; corpus + selection state is hidden)

## Background ([#68](https://github.com/mihaelamj/cupertino/issues/68))

Pre-#68 the default doctor output included raw corpus directory walks + package selection state. That made sense for maintainers running `cupertino fetch` + `cupertino save`, but users who ran `cupertino setup` (which downloads pre-built DBs and never populates `docs/`) saw a `0 files` line under "Apple docs" and thought their install was broken. It wasn't: `setup` users have databases, which is what the runtime actually needs.

`--save` is now the explicit opt-in for "I'm about to crawl / re-index, show me what the indexer sees." Pre-#68 it short-circuited to only the preflight summary; it is now additive on top of the default health suite, so a maintainer sees one combined report instead of two passes.

## Example

```bash
cupertino doctor --save
```

Sample output (database sections elided, same as `cupertino doctor` default):

```
🏥 MCP Server Health Check

✅ MCP Server
   ✓ Server can initialize
   ✓ Transport: stdio
   ✓ Protocol version: 2025-11-25

📦 Packages Index (packages.db)
   ✓ Database: ~/.cupertino/packages.db
   ✓ Size: 988.9 MB
   ✓ Indexed files: 20186
   ℹ  Bundled version: 1.1.0

🧪 Sample Code Index (apple-sample-code.db)
   ✓ Database: ~/.cupertino/apple-sample-code.db
   ✓ Size: 184.4 MB
   ✓ Projects: 619
   ✓ Indexed files: 18928
   ✓ Indexed symbols: 108536

🔍 Search Index
   ⚠  search.db: not found (legacy unified DB; superseded by the per-source DBs in v1.3.0)

🔍 Apple Developer Documentation (apple-documentation.db)
   ✓ Database: ~/.cupertino/apple-documentation.db
   ✓ Size: 2.82 GB
   ✓ Schema version: 18 (matches installed binary)
   ✓ Frameworks: 398
   📚 Indexed sources:
     ✓ apple-docs: 351505 entries

   … one 🔍 section per source follows (hig.db, apple-archive.db,
     swift-evolution.db, swift-org.db, swift-book.db), each with size,
     schema 18, and framework + entry counts

🔧 Providers
   ✓ MCP.Support.DocsResourceProvider: available
   ✓ SearchToolProvider: available


8. Schema versions (#234)

   ⚠ search.db: not found (legacy unified DB; superseded by per-source DBs)
   ✓ apple-documentation.db: 18 (sequential), journal=wal
   ✓ hig.db: 18 (sequential), journal=wal
   ✓ apple-archive.db: 18 (sequential), journal=wal
   ✓ swift-evolution.db: 18 (sequential), journal=wal
   ✓ swift-org.db: 18 (sequential), journal=wal
   ✓ swift-book.db: 18 (sequential), journal=wal
   ✓ packages.db: 5 (sequential), journal=delete (read-only distribution mode)
   ✓ apple-sample-code.db: 4 (sequential), journal=delete (read-only distribution mode)

📂 Raw corpus directories (input for `cupertino save`)
   ✓ Apple docs: ~/.cupertino/docs (415212 files)
   ✓ Swift Evolution: ~/.cupertino/swift-evolution (483 proposals)
   ✓ Swift.org: ~/.cupertino/swift-org (196 pages)
   ✓ HIG: ~/.cupertino/hig (173 pages)
   ✓ Apple Archive: ~/.cupertino/archive (406 guides)

📦 Swift Packages
   ✓ User selections: ~/.cupertino/selected-packages.json
     135 packages selected
   ✓ Downloaded READMEs: 448 packages
   ℹ  Priority packages: 135 total (Apple: 43, Ecosystem: 92)

🔍 `cupertino save` preflight check

  Docs (apple-documentation.db)
    ✓  ~/.cupertino/docs  (415212 entries)
    ✓  Availability annotation present

  Packages (packages.db)
    ✓  ~/.cupertino/packages  (183 packages)
    ✓  availability.json sidecars  (183/183)

  Samples (apple-sample-code.db)
    ✓  ~/.cupertino/sample-code  (627 zips)
    (annotation runs inline during save, no preflight check needed)

✅ All checks passed - MCP server ready
```

## Notes

- Identical preflight summary to what `cupertino save` prints before its confirmation prompt.
- Read-only: never touches any DB.
- Default `cupertino doctor` output is unaffected; this flag only adds sections.
