# Design: Cupertino

## Status (2026-05-18)

Current stable release: v1.0.2 (2026-05-11). v1.2.0 reindex in progress on `develop`.

---

## Problem

Apple ships ~412,000 JSON documentation files across ~410 frameworks. That corpus changes continuously: symbols are added, deprecated, moved between SDKs, and back-filled with availability annotations. No existing tool:

1. Indexes the full corpus locally (all frameworks, all symbol kinds, all availability tiers)
2. Exposes that corpus to AI agents via a standard protocol at sub-100ms latency
3. Keeps the index current without a full re-crawl every time Apple changes one file

Cupertino solves all three. It crawls Apple's documentation JSON API, imports the results into a local SQLite FTS5 database, enriches it with derived authoritative facts, and serves it to CLI users and AI agents via a hand-rolled MCP server that runs in-process with the CLI binary.

---

## System overview

Four sequential stages, all driven by `cupertino save --docs`:

```
Crawl ──▶ Import / Index ──▶ Enrich ──▶ Serve
```

Each stage is independently runnable:

| Stage | Trigger | Writes |
|---|---|---|
| Crawl | `cupertino fetch --type docs` | JSON files in `~/.cupertino/docs/` |
| Import / Index | `cupertino save --docs` | `search.db` |
| Enrich | inline in `save` today; `cupertino-postprocessor` after #769 | enrichment columns in `search.db` |
| Serve | `cupertino serve` (default when no args given) | nothing — reads `search.db` |

---

## Stage 1: Crawl

**Goal:** produce a stable, content-addressed local corpus of JSON files.

### Source format

Apple's documentation server publishes a private JSON API at `https://developer.apple.com/tutorials/data/documentation/<path>`. Each response contains:

- `metadata.title` — display name
- `primaryContentSections` — declarations, abstract, discussion, code examples
- `references` — links to related symbols
- `diffAvailability` — OS version constraints per platform
- `externalID` — stable symbol identifier (e.g., `c:@S@exclave_textlayout_info_v1`)

The API is not publicly documented. Cupertino reverse-engineers it from Apple's JavaScript.

### WKWebView crawl

`Crawler` uses WKWebView rather than a plain HTTP client because some pages return `"title": null` or a bare React shell when fetched without a real browser context. WKWebView runs the page JavaScript, resolves the JSON data layer, and returns the fully populated response. For ~99% of pages, a direct HTTP fetch works; WKWebView covers the remaining 1% at the cost of macOS-only crawling.

Session resume: the crawler checkpoints its BFS queue so a killed process can continue from where it stopped. The checkpoint is keyed by start URL, preventing a resumed session from accepting a different URL's state.

### URI canonicalization

Every fetched URL is canonicalized to an `apple-docs://` URI before storage:

1. Lowercase the URL path
2. Strip fragment and query string
3. Normalize dashes and underscores in path segments (#285, in progress)
4. Emit `apple-docs://<framework>/<path...>`

Canonicalization is lossless and reversible: any consumer can recover the source URL by string substitution. Hash-based identifiers were ruled out because they carry a non-zero collision floor at any corpus size and are opaque to debugging. See `docs/PRINCIPLES.md` §1.

Helper: `Shared.Models.URLUtilities.appleDocsURI(from:)`.

### Content hashing

Each JSON file is stored under a SHA-256 content hash. If the hash of a re-fetched page matches the stored hash, the file is skipped without a write. Re-crawls are incremental: only changed pages write new files.

---

## Stage 2: Import / Index

**Goal:** take the local JSON corpus and produce a populated `search.db`.

### The door

Every file crosses a door before any DB write. The door has three responsibilities:

**Placeholder filter** (`Search.StrategyHelpers.titleLooksLikePlaceholderError`): reject files whose title is empty, `"Apple Developer Documentation"` (bare shell page), or a bare property name like `"error"` (server-side rendering artifact from WebKitJS). All rejections are logged with `⛔` and counted in `IndexStats`.

**URI deduplication** (`classifyDoorEncounter`): for any URI already seen in this run, classify before writing:

| Tier | Match | Action |
|---|---|---|
| A | same URI + same `contentHash` | silent skip (byte-identical) |
| B | same URI + same canonical title, different hash | richest variant wins; both logged with `⏭️` |
| C | same URI + different canonical title | first arrival stays; collision surfaced with `🚨` |

Tier-C non-zero at end of run causes `cupertino save` to exit non-zero. The full tiering contract — including richest-variant selection and logging guarantees — is in `docs/PRINCIPLES.md` §2–3.

**Validity check**: reject files whose URL does not decompose into a documentation URI (e.g., marketing pages that stray into the crawl BFS).

Every rejection is written to the JSONL import log (`~/.cupertino-dev/reindex-<timestamp>.log`) as a structured `Search.ImportLogEntry` via `Search.JSONLImportLogSink`.

### SQLite FTS5 index

`search.db` has four primary structures:

**`docs_fts`** — virtual FTS5 table with porter stemmer + unicode61 tokenizer. Column order matches the BM25 weight vector `bm25(docs_fts, 1.0, 1.0, 2.0, 1.0, 10.0, 1.0, 3.0, 5.0, 1.5)`:

| Column | Weight | Content |
|---|---|---|
| `uri` | 1.0 | `apple-docs://` identifier |
| `source` | 1.0 | `apple-docs`, `swift-evolution`, `swift-org`, `swift-book` |
| `framework` | 2.0 | e.g., `swiftui`, `foundation` |
| `language` | 1.0 | `swift`, `objc` |
| `title` | 10.0 | page display name |
| `content` | 1.0 | full discussion text |
| `summary` | 3.0 | one-sentence abstract |
| `symbols` | 5.0 | AST-extracted Swift symbol names |
| `symbol_components` | 1.5 | CamelCase splits (`LazyVGrid` → `Lazy`, `VGrid`, `Grid`) |

**`docs_metadata`** — one row per document, non-FTS columns:
- `uri` (PK), `source`, `framework`, `language`, `kind` (`func`/`class`/`struct`/…)
- `symbols` (denormalized from doc_symbols for fast column access)
- `file_path`, `content_hash`, `last_crawled`, `word_count`
- `json_data` (raw JSON blob for full-doc read)
- `min_ios`, `min_macos`, `min_tvos`, `min_watchos`, `min_visionos` (for availability filtering)
- `availability_source` (`api`/`parsed`/`inherited`/`derived`)
- `implementation_swift_version` (for Swift Evolution rows)

**`docs_structured`** — extracted declaration fields for attribute search:
- `abstract`, `declaration`, `overview`, `module`, `platforms`
- `conforms_to`, `inherited_by`, `conforming_types`, `attributes`

**`doc_symbols`** — AST-extracted symbol rows, one per declared symbol:
- `name`, `kind`, `signature`, `is_async`, `is_throws`, `is_public`, `is_static`
- `attributes`, `conformances`, `generic_params`, `generic_constraints`

**Why FTS5 over a vector database:** Apple documentation is symbol-structured. A query like `"URLSession dataTaskPublisher"` is a token match, not a semantic embedding lookup. FTS5 handles it at sub-millisecond latency with zero external dependencies. Vector/semantic search is planned as a complementary path in Phase 2.5 (#183), not a replacement.

### AST symbol extraction

After each doc is inserted, `ASTIndexer.Extractor` (SwiftSyntax) runs on two paths:

**Declaration path**: if the page has a `declaration.code` field, extract symbol names and import statements from the Swift declaration. Feeds the `symbols` FTS5 column and the `doc_symbols` table.

**Code example path** (`extractCodeExampleSymbols`): for pages with Swift code blocks in discussion sections, extract symbol names from usage snippets. Fires for all pages with Swift code, not only those with a formal declaration — it boosts pages that use a symbol without declaring it in their own type signature.

~165,000 of the ~285,000 Apple docs pages in the v1.2.0 corpus have `doc_symbols` rows.

---

## Stage 3: Enrich

**Goal:** annotate raw indexed rows with derived authoritative facts, without re-running the crawl or the main index loop.

Four passes run after the document loop inside `Search.IndexBuilder.buildIndex()`:

| Pass | Writes | Input | Depends on |
|---|---|---|---|
| `synonyms` | `framework_aliases.synonyms`: 22 frameworks get alternate search names (e.g., `corebluetooth` → `bluetooth`) | hardcoded list in `registerFrameworkSynonyms()` | — |
| `constraints` | `doc_symbols.generic_constraints`: Apple's authoritative constraint table from `swift symbolgraph-extract` output | `apple-constraints.json` via `AppleConstraintsKit` | — |
| `hierarchy` | same column: constraints propagated down the symbol hierarchy | `doc_symbols` parent/child rows | `constraints` |
| `recovery` | re-inserts placeholder-title-rejected pages using URL-leaf title derivation (#777) | JSONL import log | — |

Today all four run inline with no per-pass start/end log line, which makes the indexer appear frozen for up to 5+ minutes at 90% completion (#768). Epic #769 extracts them into a standalone `cupertino-postprocessor` binary with an `EnrichmentPass` protocol, per-pass idempotency, and progress lines. A proposed `doc_enrichment_version` column on `docs_metadata` (#778) will let passes skip already-enriched rows on partial re-runs. Full design in `docs/design/post-processor.md`.

---

## Stage 4: Serve

**Goal:** answer queries against `search.db` via CLI and MCP at sub-100ms latency.

### Search pipeline

Default `cupertino search <query>` is a multi-pass ranker, not a plain FTS5 query:

```
query
 │
 ├─ extractSourcePrefix         — strip "swift-evolution://", "hig://", etc.
 ├─ extractAttributeFilters     — strip @concurrency, @observable, etc. → SQL WHERE
 └─ sanitizeFTS5Query           — quote terms, split on hyphens

 ├─ searchSymbolsForURIs        — symbol fast path: URI set from doc_symbols_fts
 └─ docs_fts MATCH              — BM25 with column weights (title 10×, symbols 5×, summary 3×, framework 2×)

 ├─ Heuristic 1 (exact-title boost, #254)
 │    50× for clean match · 20× for suffixed match
 │    separates Array<Swift> from array_*<C>
 │
 ├─ Heuristic 1.5 (URI simplicity + framework authority, #256)
 │    shorter URI ranks above longer at equal BM25 score
 │    swift/swiftui/foundation boosted · webkitjs/installer_js penalized
 │
 ├─ fetchCanonicalTypePages     — force-include canonical type page (#254)
 │
 └─ RRF fusion (k=60, #192)    — merge across active sources
      apple-docs 3.0 · swift-evolution 1.5 · packages 1.5
```

Scores are negative (lower = better match, FTS5 convention). Adjusted rank divides the BM25 score by a combined boost multiplier, so a 50× boost on an exact-title match moves it above a 10× raw-BM25 winner.

### MCP server

The `cupertino` binary defaults to MCP serve mode when run with no arguments and stdin is a pipe. No separate install.

Transport: JSON-RPC 2.0 over stdio. Each message is one compact line plus a newline delimiter. No embedded newlines (MCP spec requirement).

Tools:

| Tool | Does |
|---|---|
| `search` | multi-source fan-out: docs + samples + packages |
| `search_symbols` | symbol-name lookup via `doc_symbols_fts` |
| `search_generics` | generic constraint query via `doc_symbols.generic_constraints` |
| `search_conformances` | protocol conformance lookup via `docs_structured.conforms_to` |
| `search_concurrency` | Swift concurrency usage patterns |
| `search_property_wrappers` | property wrapper lookup |
| `read_document` | full page content by `apple-docs://` URI (reads `docs_metadata.json_data`) |
| `read_sample` | sample code project by ID |
| `read_sample_file` | individual file from a sample |
| `list_frameworks` | all indexed frameworks from `framework_aliases` |
| `list_samples` | all indexed sample projects |

**Why single binary, not `cupertino` + `cupertino-mcp`:** the pre-v0.2 two-binary model required users to install and version two separate executables. Merging them simplified deployment to one Homebrew formula and one PATH entry. The binary detects its mode by whether stdin is a pipe (MCP serve) or a TTY (CLI).

---

## Package architecture

~35 SPM targets in five tiers, organized so producers never import other producers:

```
Foundation tier    SharedConstants · LoggingModels · MCPCore · MCPSharedTools · Resources
                   (foundation-only by construction; any target may import these)

Models tier        *Models protocol seams:
                   CrawlerModels · SearchModels · IndexerModels · DistributionModels
                   SampleIndexModels · ServicesModels · RemoteSyncModels · CleanupModels
                   CorePackageIndexingModels · CoreSampleCodeModels
                   (foundation-only by contract; any producer may import any seam)

Infrastructure     ASTIndexer (SwiftSyntax) · Diagnostics (SQLite read-only) · Logging (os.log)

Producers          Crawler · Core · CoreJSONParser · CorePackageIndexing · CoreSampleCode
                   Search · SampleIndex · Services · Indexer · Distribution · Ingest
                   SearchToolProvider · MCPSupport · AppleConstraintsKit · Availability
                   Cleanup · RemoteSync
                   (each imports only foundation tier + own *Models seam + external primitives)

Composition roots  CLI → cupertino binary
                   TUI → cupertino-tui
                   ConstraintsGen → cupertino-constraints-gen
                   MockAIAgent · ReleaseTool (aux tooling)
                   (executableTarget; import everything; wire producers together)
```

**Key invariant:** a producer that imports a concrete writer from another producer fails to build. No workaround exists because the import ban is enforced at compile time, not by convention.

CI enforcement:
- `scripts/check-package-purity.sh` — bans producer→concrete-producer imports
- `scripts/check-target-foundation-only.sh` — per-target allow-list for strict producer opt-in

Full per-target import contract: `docs/package-import-contract.md`.

---

## Key design decisions

### ExtremePackaging over a fat library

~35 packages instead of one. Cost: boilerplate in `Package.swift`. Benefit: import boundaries are statically enforced by the compiler. When `Search` can't accidentally gain a `Crawler` dependency because the build fails if it does, the constraint holds at every PR, not just on audit days.

### SQLite over a vector database

Apple documentation is symbol-structured, not natural-language prose. Exact symbol names are the primary query signal. FTS5 with BM25 handles token-match queries at sub-millisecond latency with zero external runtime dependencies. Vector/semantic search adds latency, an embeddings pipeline, and a model dependency for queries that are structurally exact anyway. It will be added as a complementary path (Phase 2.5 per #183).

### WKWebView over headless HTTP

Some pages return `"title": null` or a bare React shell when fetched without browser context (~1% of pages, concentrated in certain frameworks). WKWebView is the only reliable way to get fully-rendered title fields for those pages. Cost: macOS-only crawling. Benefit: complete coverage.

### Single binary, no separate `cupertino-mcp`

Pre-v0.2, the MCP server was a separate binary. Merging it simplified deployment: one formula, one PATH entry, one binary to update. The binary detects its mode from stdin being a pipe vs. a TTY.

### Corpus as a git time-series database

`cupertino-docs` is not just a distribution vehicle; it is a git-history record of Apple's documentation changes. `git diff <commit-A> <commit-B>` on the corpus repo answers "what did Apple change between crawl X and crawl Y" with no additional tooling. Commit granularity is one crawl session. The git object store is the diffable audit log.

### Enrichment separated from indexing

The four post-processing passes were originally buried in `buildIndex()` because they were added one at a time as point fixes. Epic #769 extracts them into a dedicated stage so enrichment can be re-run against a finished `search.db` without a 12-hour re-index, and so each pass can be developed and tested in isolation against a known DB snapshot.

### Hand-rolled MCP over the official Swift SDK

The MCP implementation in the `MCP` package is hand-rolled. The official Swift MCP SDK was reviewed and rejected: it was longer, carried more dependencies, and did not cover the specific transport edge cases that Apple's MCP client exercises. The hand-rolled implementation covers exactly the protocol surface needed, nothing more.

---

## References

- `docs/PRINCIPLES.md` — six engineering principles (lossless URIs, door, content preservation, garbage filter, 10× headroom, correctness first)
- `docs/ARCHITECTURE.md` — package layout, `Search.Index` file map, `search()` ranker pipeline diagram, MCP server details
- `docs/package-import-contract.md` — per-target allowed and forbidden imports
- `docs/design/post-processor.md` — enrichment-pass pipeline design (epic #769, child #778)
- GitHub issue #183 — roadmap
- GitHub issue #769 — layer-separation epic (Crawler / Indexer / PostProcessor / Search+MCP independently buildable)
