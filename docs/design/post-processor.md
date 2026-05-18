# Design: Enrichment Pass Pipeline (cupertino-postprocessor)

## Status (2026-05-18)

Draft. Tracks epic #769, child issue #778. No implementation started.

---

## Problem

The post-indexing passes that run after the main document loop are:

1. `registerFrameworkSynonyms()` — 22 framework alias mappings
2. `applyAppleStaticConstraints()` — authoritative symbolgraph constraint table (#759 iter 3)
3. `propagateConstraintsFromParents()` — hierarchy walk (#759 iter 2)
4. Recovery pass — title derivation for placeholder-title rejects (#777)

Currently all four are buried inside `Search.IndexBuilder.buildIndex()`. They are silent for 5+ minutes (#768), cannot be re-run independently without a full 12-hour reindex, and live in the `Search` layer even though they logically belong to a separate enrichment stage.

---

## Industry pattern

This is the **enrichment pass** pattern, well established at the scale of major search systems.

| System | Name for this concept | Key reference |
|---|---|---|
| Google Percolator | Observer / incremental processor | OSDI 2010, Peng & Dabek |
| LinkedIn Galene | Annotator / transformer | LinkedIn Engineering Blog, 2014 |
| Apache Solr | Update Request Processor (URP) chain | Solr Reference Guide |
| Elasticsearch | Ingest pipeline / enrich processor | Elastic Blog, 2019 |
| Apache Beam | Enrichment PTransform | Beam docs |

**Solr's URP chain** is the closest structural match: an ordered list of processor units, each reading and writing the same document store, with a static execution order defined by explicit dependencies.

**Elasticsearch's enrich processor** is the closest semantic match: it does a keyed lookup against a reference index (the symbolgraph constraint table) and merges additional fields into the document — exactly what `applyAppleStaticConstraints` does.

**Common vocabulary across all five systems:**

- The raw indexing phase writes once and is expensive.
- The enrichment phase reads the raw output, applies derived facts, and writes enriched fields.
- The two phases are decoupled so enrichment logic can change without re-running the crawler or the raw indexer.
- Each enrichment unit is **idempotent** — running it twice produces the same result.

---

## Design

### Naming

These are **enrichment passes**, not "post-processors." Each pass annotates raw indexed documents with derived authoritative facts. The binary is `cupertino-postprocessor` for consistency with the existing CLI naming, but internally the units are `EnrichmentPass` types.

### Protocol

```swift
// EnrichmentModels package (new, lean — no Search import)
public protocol EnrichmentPass: Sendable {
    var identifier: String { get }        // e.g. "synonyms", "constraints", "hierarchy", "recovery"
    var schemaVersion: Int { get }        // pass refuses to run against a DB version it doesn't understand
    var dependsOn: [String] { get }       // identifiers of passes that must complete first
    func run(database: OpaquePointer, logger: any Logging.Recording) async throws -> EnrichmentResult
}

public struct EnrichmentResult: Sendable {
    public let passIdentifier: String
    public let rowsAffected: Int
    public let rowsSkipped: Int
    public let durationMs: Int
}
```

### Idempotency

Industry consensus (Solr, Elasticsearch, Beam) converges on two mechanisms:

1. **Upsert semantics**: every write in an enrichment pass uses `INSERT OR REPLACE` or `UPDATE ... WHERE`. Running twice produces the same row.
2. **Pass version column**: a `doc_enrichment_version` INTEGER column on `docs_metadata` records which enrichment schema version last touched each row. A pass skips rows whose `doc_enrichment_version` already matches the current version. Clear the column to force a re-run.

For `applyAppleStaticConstraints` and `propagateConstraintsFromParents`, the existing `UPDATE doc_symbols SET generic_constraints = ? WHERE doc_uri = ?` already has upsert semantics. No change needed for those. The recovery pass (#777) adds new rows — it must check for existence before inserting.

### Ordering and dependency enforcement

Four passes, with one explicit dependency:

```
synonyms        ─┐
                 ├─→ (no dependency between these two)
constraints ───┐ │
               ↓ ↓
            hierarchy   ← depends on constraints (reads generic_constraints written by iter 3)
recovery    ─────────── independent; depends on import log, not on other passes
```

The runner validates `dependsOn` before starting each pass. If a dependency hasn't run in the current session it either fails-fast (`--strict`) or runs the dependency first (`--auto-deps`, default).

### Separate layer

`cupertino-postprocessor` imports:

- `Search` (for DB access and `EnrichmentPass` implementations)
- `SearchModels`
- `AppleConstraintsKit`
- `Logging`, `SharedConstants`, `ArgumentParser`

It does **not** import `Crawler`, `CrawlerModels`, `Ingest`, `Core`, `CoreJSONParser`, `MCPCore`, `MCPSupport`. CI enforces this (see #775).

### Interface

```
cupertino-postprocessor --base-dir <path> [--pass <id>...] [--all] [--strict] [--dry-run]
```

- `--pass synonyms` / `--pass constraints` / `--pass hierarchy` / `--pass recovery`
- `--all` (default): runs all four passes in dependency order
- `--strict`: fail if any dependency hasn't been run in this session
- `--dry-run`: logs what each pass would do without writing

### Integration with the single-binary `cupertino`

The `cupertino save --docs` command continues to call all four passes inline via `Search.IndexBuilder.buildIndex()` — no user-visible change. After #772 (Ingest) and #776 (thin CLI), `buildIndex()` will call the same `EnrichmentPass` implementations that `cupertino-postprocessor` calls, so the two paths stay in sync automatically.

### Progress logging

Each pass emits a start line before it begins and a completion line when it finishes (see also #768):

```
   Enrichment: synonyms — registering 22 framework aliases...
   Enrichment: synonyms — done (22 rows, 3ms)
   Enrichment: constraints — applying static constraint table (N entries)...
   Enrichment: constraints — done (M rows affected, Xms)
   Enrichment: hierarchy — propagating generic constraints from parents...
   Enrichment: hierarchy — done (K rows affected, Xms)
   Enrichment: recovery — checking import log for recoverable rejects...
   Enrichment: recovery — done (J pages recovered, Xms)
```

---

## Acceptance criteria

- `swift build --target cupertino-postprocessor` succeeds with zero Crawler or MCP layer imports
- Running it against a freshly-built `search.db` produces identical results to the embedded passes in `cupertino save`
- Each pass is idempotent: running it twice produces the same `search.db` as running it once
- `--pass recovery` recovers `exclave_textlayout_info_v1` from the import log (see #777)
- CI builds this target on every push (part of #775)
- Binary is not shipped in the Homebrew formula

---

## References

- Peng & Dabek, "Large-scale Incremental Processing Using Distributed Transactions and Notifications" (OSDI 2010): https://research.google/pubs/pub36726/
- LinkedIn Galene: https://engineering.linkedin.com/blog/topic/galene
- Solr URP chain: https://solr.apache.org/guide/solr/latest/configuration-guide/update-request-processors.html
- Elasticsearch enrich processor: https://www.elastic.co/blog/introducing-the-enrich-processor-for-elasticsearch-ingest-nodes
- Apache Beam enrichment transform: https://beam.apache.org/documentation/transforms/python/elementwise/enrichment/
- LlamaIndex IngestionPipeline idempotency: https://docs.llamaindex.ai/en/stable/module_guides/loading/ingestion_pipeline/
