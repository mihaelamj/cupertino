# Design: Cupertino

| Field | Value |
|---|---|
| **Status** | Living document. Sections are revised in PRs that change the corresponding subsystem. |
| **Latest release** | v1.1.0 (2026-05-14). v1.2.0 in flight on `develop`. |
| **Roadmap** | GitHub issue [#183](https://github.com/mihaelamj/cupertino/issues/183) |
| **Companion docs** | `docs/PRINCIPLES.md`, `docs/ARCHITECTURE.md`, `docs/package-import-contract.md`, `docs/design/post-processor.md` |

---

## TL;DR

Cupertino is a local-first indexing and serving system for Apple developer documentation. It crawls the full Apple docs JSON API (~412,000 pages, ~420 frameworks), imports the result into a SQLite FTS5 database with a multi-pass BM25F ranker, and serves it to AI agents over the Model Context Protocol from a single hand-rolled Swift binary. Search latency is sub-100ms p99; the entire system runs offline after a one-time bundle download. The bundle is rebuilt and distributed via GitHub Releases (~685 MB compressed). Crawl-to-bundle is a ~14-day pipeline that runs out-of-band; the user-facing install path skips the crawl entirely.

---

## 1. Context

### 1.1 Problem

Apple publishes developer documentation as a JavaScript-rendered single-page application backed by an undocumented JSON API. AI coding agents (Claude, Copilot, Cursor, etc.) need accurate, current Apple API references to avoid generating code that calls nonexistent symbols, uses deprecated APIs, or violates platform availability constraints. The naive approaches all fail:

- **Web scraping at query time** is too slow, fragile against Apple's JS changes, and hits Apple's rate limits.
- **Inline embedding in the agent's prompt** is too large (the full docs corpus is ~3 GB structured, would not fit in any current context window).
- **Vector embedding the corpus** loses the symbol-name token-match signal that 80%+ of Apple-docs queries depend on, and adds an inference dependency to every query.
- **Training the agent on the docs** is stale within months and can't be updated incrementally.

### 1.2 Why a local index

The corpus has favorable properties for a local index:

- **Bounded size**: ~412k pages, ~3 GB structured JSON, ~2.4 GB compressed FTS5 index. Fits on consumer hardware.
- **Slow churn**: Apple ships major doc revisions once per OS release cycle (twice a year). Daily delta is small.
- **Symbol-structured content**: most queries match on exact symbol names (`URLSession`, `@Observable`, `dataTaskPublisher`). FTS5 + BM25F handles this at sub-millisecond latency without an embeddings pipeline.
- **Public**: Apple ships the docs under no auth.

### 1.3 Why MCP

The Model Context Protocol (Anthropic, 2024) standardizes how AI agents discover and invoke tools and read external resources. MCP-compatible agents (Claude Desktop, Claude Code, Cursor, VS Code Copilot, Zed, Windsurf, OpenAI Codex, GitHub Copilot for Xcode) can consume Cupertino without per-agent integration work. Targeting MCP avoids building N adapter binaries.

---

## 2. Goals

### P0 (release blockers)

- **G1**: Index the full Apple developer docs corpus locally. Coverage measured by frameworks present in `framework_aliases` and document count in `docs_metadata`.
- **G2**: Serve via MCP at p99 < 100ms for typical search queries against the local index.
- **G3**: Lossless URI canonicalization (zero hash-collision floor, fully reversible to source URL).
- **G4**: Single-binary install via Homebrew with a one-command setup that downloads the prebuilt bundle.
- **G5**: Multi-source ranking. Apple docs, Apple sample code, Swift Evolution, Swift.org, Swift Book, Apple Archive, HIG, and Swift packages all queryable from one CLI/MCP entry point.

### P1 (high priority, not release blockers)

- **G6**: Incremental re-crawl. Skip unchanged pages via content hashing.
- **G7**: Resumable crawl session. Killed processes resume from checkpoint, not from scratch.
- **G8**: AST-aware ranking. Swift symbol declarations get a BM25 column boost so `Task` finds Swift's `Task` struct above the Mach kernel's `task_*` C functions.
- **G9**: Attribute search. Filter by `kind`, `conforms_to`, `@MainActor`, platform availability (`min_ios`, `min_macos`, etc.), and other DocC-extracted fields without parsing JSON at query time.
- **G10**: Audit log. Every rejected, deduplicated, or skipped row is recorded with its reason in a JSONL log for offline forensics.

### P2 (nice to have, post-1.x)

- **G11**: Vector/semantic search as a complement to token-match (Phase 2.5 per #183).
- **G12**: Diagnostic block in MCP responses surfacing why a result was ranked where it was (Phase 2.1).
- **G13**: Differential re-crawl. Use the corpus git history to fetch only pages Apple changed since the last commit.

---

## 3. Non-goals

These are explicit non-goals so future contributors don't waste cycles re-proposing them:

- **NG1**: Authenticated Apple endpoints. `FASTLANE_SESSION` and xcodes-style SRP authentication were evaluated and rejected; no consumer in the design needs them.
- **NG2**: Real-time documentation updates. Apple's API isn't push-based and the bundle re-build cadence is multi-day; users expect a snapshot, not a live feed.
- **NG3**: Indexing non-Apple-published content. Third-party tutorials, Stack Overflow, blog posts are out of scope. The trust model is "Apple shipped it" and that boundary is load-bearing for the no-hallucinations guarantee.
- **NG4**: Cross-platform crawling. WKWebView is macOS-only. A Linux crawl variant is open future work but not in scope for v1.x.
- **NG5**: User-content storage. Cupertino does not collect, store, or transmit user queries, telemetry, or personally identifying information. The MCP server is stateless across sessions.
- **NG6**: In-place schema migrations. When the schema bumps, users re-run `cupertino setup` to get a clean bundle. Migration code paths are a known source of subtle bugs in long-lived databases; we chose to skip them entirely and rebuild from source.

---

## 4. Requirements

### 4.1 Functional

| ID | Requirement | Verified by |
|---|---|---|
| F1 | Full-text search across all indexed sources | `cupertino search`, MCP `search` tool |
| F2 | Read a full document by `apple-docs://` URI | `cupertino read`, MCP `read_document` |
| F3 | List indexed frameworks with document counts | `cupertino list-frameworks`, MCP `list_frameworks` |
| F4 | Filter search results by framework, platform version, source | CLI flags and MCP tool parameters |
| F5 | Symbol-shape queries (find all `actor`s conforming to `Sendable`) | MCP `search_symbols`, `search_conformances` |
| F6 | Property-wrapper and concurrency pattern lookup | MCP `search_property_wrappers`, `search_concurrency` |
| F7 | Sample code read at file granularity | MCP `read_sample`, `read_sample_file` |
| F8 | Crawl resume from arbitrary kill point | `Crawler` session checkpoint, keyed by start URL |
| F9 | Content-hash-based incremental re-crawl | SHA-256 per JSON file; skip on hash match |
| F10 | Audit log of all rejected and deduplicated rows | `Search.JSONLImportLogSink` writes JSONL |

### 4.2 Non-functional

| ID | Requirement | Target | Current state |
|---|---|---|---|
| N1 | Search latency p99 | < 100ms | Holds on v1.1.0 bundle (~285k docs); tracked in integration test |
| N2 | Read latency p99 | < 50ms | SQLite single-row lookup on indexed PK |
| N3 | Memory at serve time | < 500MB resident | SQLite mmap; process is the binary + open file handles |
| N4 | Storage footprint | < 5 GB bundle on disk | search.db 2.4 GB + packages.db 990 MB + samples.db 185 MB = ~3.6 GB (v1.1.0) |
| N5 | Setup time | < 60s | bundle download from GitHub Releases, ~685 MB compressed |
| N6 | Scale headroom | 10x current corpus | analyzed in §10 |
| N7 | Correctness | zero data loss on power loss; zero tier-C collisions on healthy run | SQLite ACID + door classification (`docs/PRINCIPLES.md` §2-3) |
| N8 | Reproducibility | same crawl → same bundle (modulo Apple changes) | content hashing + deterministic URI canonicalization |
| N9 | Portability | single Homebrew formula, no runtime deps | binary is self-contained except for SQLite (system) |
| N10 | Build hygiene | zero producer→producer imports; CI-enforced | `scripts/check-package-purity.sh` + `scripts/check-target-foundation-only.sh` |

---

## 5. Design Overview

### 5.1 Pipeline

Four sequential stages. Each is independently runnable; the user-facing `cupertino save --docs` chains them inline today, but they are designed to decouple cleanly (epic #769):

```
┌────────┐    ┌──────────────┐    ┌────────┐    ┌────────┐
│ Crawl  │ →  │ Import/Index │ →  │ Enrich │ →  │ Serve  │
└────────┘    └──────────────┘    └────────┘    └────────┘
   ~14d            ~12h            ~5 min        runtime
```

| Stage | Binary | Input | Output | Idempotent |
|---|---|---|---|---|
| Crawl | `cupertino fetch --source apple-docs` | Apple JSON API over the network | `~/.cupertino/docs/**/*.json` | Yes (content hash skip) |
| Import / Index | `cupertino save --docs` | JSON files on disk | `search.db` | Yes (`INSERT OR REPLACE`) |
| Enrich | `cupertino-postprocessor` (after #769) | `search.db` | enrichment columns in same DB | Yes (upsert + version column) |
| Serve | `cupertino serve` | `search.db` | MCP responses over stdio | Read-only |

The decoupling lets us re-run enrichment without a re-crawl, ship pre-built bundles via GitHub Releases (skipping crawl + index for end users), and run the crawl on dedicated hardware.

### 5.2 Topology

```
            ┌──────────────────────────────────────────┐
            │           Apple developer docs           │
            │  developer.apple.com/tutorials/data/...  │
            └─────────────────┬────────────────────────┘
                              │ WKWebView, 0.05s delay, BFS
                              ▼
            ┌──────────────────────────────────────────┐
            │    ~/.cupertino/docs/<framework>/*.json  │
            │   git-tracked corpus repo (cupertino-docs) │
            └─────────────────┬────────────────────────┘
                              │ cupertino save --docs
                              ▼
            ┌──────────────────────────────────────────┐
            │  search.db (SQLite FTS5 + metadata + AST)│
            └─────────────────┬────────────────────────┘
                              │ enrichment passes
                              ▼
            ┌──────────────────────────────────────────┐
            │ search.db (synonyms, constraints,        │
            │ hierarchy, recovery applied)             │
            └─────────────────┬────────────────────────┘
                              │ cupertino serve / search
                  ┌───────────┴───────────────┐
                  ▼                           ▼
        ┌───────────────────┐    ┌──────────────────────┐
        │  MCP (stdio JSON- │    │  CLI (search, read,  │
        │  RPC) for agents  │    │  list, doctor)       │
        └───────────────────┘    └──────────────────────┘
```

### 5.3 Process model

Cupertino is a single Swift binary that runs in one of two modes, detected at startup:

| stdin shape | argv | Mode |
|---|---|---|
| pipe | none or `serve` | MCP server (long-lived, reads JSON-RPC, replies on stdout) |
| TTY | none or `serve` | error: `serve` from terminal is almost always wrong |
| any | subcommand (`search`, `read`, `fetch`, `save`, `doctor`, `setup`, `cleanup`, `list-frameworks`, ...) | CLI mode, executes subcommand, exits |

The single-binary topology was chosen over a separate `cupertino-mcp` to simplify deployment: one Homebrew formula, one PATH entry, one update path. Per-mode dispatch is a 5-line check at startup.

---

## 6. Detailed Design: Crawl

### 6.1 Source format

Apple's developer documentation site is an SPA. The page at `https://developer.apple.com/documentation/swiftui/view` fetches its content from a parallel JSON endpoint:

```
https://developer.apple.com/tutorials/data/documentation/swiftui/view.json
```

The JSON response is structured. Key fields:

| Field | Type | Used for |
|---|---|---|
| `metadata.title` | string | display name, FTS5 `title` column |
| `metadata.role` | string | maps to `kind` column (`func`, `struct`, ...) |
| `metadata.externalID` | string | stable symbol identifier (e.g., `c:@S@exclave_textlayout_info_v1`) |
| `metadata.modules[].name` | string | framework slug |
| `metadata.platforms[]` | array | drives `min_ios`/`min_macos`/etc columns |
| `abstract` | array | short summary, FTS5 `summary` column |
| `primaryContentSections[]` | array | declarations, discussion, code examples |
| `references` | dict | linked symbol metadata |
| `diffAvailability` | dict | version diff vs previous SDKs |

The shape is not publicly documented. Cupertino reverse-engineers it. Schema drift is a known risk (§13).

### 6.2 Why WKWebView

For ~99% of pages, a direct HTTP GET against the JSON endpoint works. For the remaining ~1%, Apple's CDN returns one of:

- `"title": null` with otherwise valid JSON
- A 3,297-byte React shell with no content (server-side rendering fell back)
- A redirect chain that breaks without cookies

WKWebView executes the page's JavaScript, follows redirects with browser semantics, and gives us the fully-resolved JSON. The cost is macOS-only crawling. The benefit is complete coverage.

`Crawler` runs WKWebView with `@MainActor` isolation, navigates to the page URL, waits for the JS to settle, extracts the embedded JSON via a small JS bridge, and writes it to disk. Each navigation uses a fresh WKWebView instance to avoid state leakage; instances are pooled via a small actor.

### 6.3 BFS crawl strategy

Starting from `https://developer.apple.com/documentation/technologies`, BFS over `references[]` links, scoped to documentation paths. Frameworks are also seeded from `technologies.json` (Apple's framework directory) to catch the ~200 frameworks not reachable from the homepage at depth ≤ 5.

Configurable knobs:

| Flag | Default | Purpose |
|---|---|---|
| `--max-pages` | unbounded for `--source apple-docs --source all` | safety bound for testing |
| `--max-depth` | 21 | empirical; depth at which Apple's deeper symbol pages live |
| `--request-delay` | 0.05s | conservative rate limit; nothing publicly documented but 50ms is well below Apple's threshold |
| `--start-url` | docs home | for targeted re-crawls |
| `--allowed-prefixes` | none | filter BFS to a path prefix |

### 6.4 URI canonicalization

Every fetched URL is canonicalized to an `apple-docs://` URI before storage. The canonicalization is **lossless and reversible**:

1. Lowercase the URL path (Apple's routing is case-insensitive; preserving case creates phantom duplicates).
2. Strip fragment and query.
3. Normalize dash/underscore in path segments (Apple serves the same content at `building-a-pass` and `building_a_pass`; in progress #285).
4. Emit `apple-docs://<framework>/<path-tail-joined-by-slashes>`.

The URI is reversible to the original URL by string substitution. No hashing. This guarantees:

- **No collision floor**. A hash-suffix scheme (e.g., 8-byte SHA truncation) carries `1 - exp(-N²/2·2⁶⁴)` collision probability; at 40M docs the expected collisions are non-zero. Lossless URIs make collisions impossible by construction.
- **Debugability**. Any URI is grep-able. A user reporting a bug names the URI and we know exactly which page they hit.

### 6.5 Content hashing

Each fetched JSON is hashed with SHA-256 and compared against the previously stored file at the canonicalized URI. If the hashes match, the new fetch is discarded (the disk file is already current). This makes re-crawls incremental: a re-fetch of an unchanged page is one HTTP request + one SHA computation, no disk write.

The hash uses the raw JSON bytes after canonicalizing JSON key order. JSON serialization can vary across crawls even when content hasn't changed; key-order canonicalization removes that source of false positives.

### 6.6 Session checkpoint

The BFS queue and visited-URI set are periodically serialized to disk under a session key derived from the start URL. A killed crawler that resumes with the same start URL picks up where it left off. Sessions from a different start URL do not collide.

### 6.7 Failure handling

- **Network error**: retry with exponential backoff, max 5 attempts. After 5 failures the URI is logged to the error file and the crawl continues.
- **WKWebView timeout**: page rendering is bounded at 30s. Timeouts are recorded and the URI is requeued at the end of the BFS frontier for one retry.
- **Page returns null/empty title**: handled at the door, not at the crawler. The crawler stores the file as-is; the indexer rejects it.

---

## 7. Detailed Design: Import / Index

### 7.1 The door

Every JSON file crosses a door before any DB write. The door has three responsibilities, executed in order:

#### 7.1.1 Validity check

`URLUtilities.appleDocsURI(from:)` returns the canonical URI or `nil`. A `nil` return rejects the file (it doesn't represent a doc page; e.g., a marketing page that strayed into the BFS).

#### 7.1.2 Placeholder filter

`Search.StrategyHelpers.titleLooksLikePlaceholderError` rejects files whose extracted title matches one of:

| Pattern | Example | Why |
|---|---|---|
| empty | `""` | server-side rendering returned nothing |
| `Apple Developer Documentation` | bare shell, never rendered | React fallback when JS failed |
| `error` (case-insensitive, when URL leaf is also `error`) | WebKitJS `FileReader.error`, `IDBRequest.error` | Apple's renderer collapsed the property name into the title field |

Rejections are written to the JSONL import log with reason `placeholderTitle`. The associated symbol can be recovered downstream by the recovery enrichment pass (§8.4) using the URL leaf as a synthetic title.

#### 7.1.3 Deduplication

The door maintains a per-run `seen` map keyed by URI. For any URI that's already been accepted in this run, classify the encounter:

| Tier | Match criteria | Action | Log |
|---|---|---|---|
| A | same URI + same `contentHash` | silent skip (byte-identical) | none |
| B | same URI + same canonical title + different `contentHash` | richest variant wins; loser logged | `⏭️` |
| C | same URI + different canonical title | first arrival stays; collision surfaced | `🚨` |

Tier-A is byte-equality. Tier-B is the case of "same logical Apple page, slightly drifted JSON between crawls" (a 2-byte trailing-slash difference, a rendering nondeterminism). Tier-C is the case where URI canonicalization conflated two genuinely different pages; this is a correctness bug that must be fixed in canonicalization, not papered over in the index.

Tier-C non-zero at end-of-run causes `cupertino save` to exit non-zero with a "work-not-done" banner. The full contract is in `docs/PRINCIPLES.md` §2-3.

#### 7.1.4 Richest-variant selection (Tier B)

When a Tier-B match fires, the door picks the "richest" variant deterministically:

1. More non-empty fields among `{abstract, declaration, sections, codeExamples, rawMarkdown}`.
2. Tie → larger total byte length across those fields.
3. Tie → first arrived (stable order).

This guarantees Tier-B drift produces a monotonic improvement in the indexed row: a populated abstract never loses to an empty one, a full declaration never loses to an empty one. The corpus on disk preserves both variants for offline audit.

### 7.2 Schema

Six primary structures in `search.db`. The schema is in `Search.Index.Schema.swift`; columns called out here are the load-bearing ones for the design.

#### 7.2.1 `docs_fts`

Virtual FTS5 table, porter + unicode61 tokenizer. Column order matches the BM25 weight vector:

```sql
CREATE VIRTUAL TABLE docs_fts USING fts5(
  uri,                -- weight 1.0
  source,             -- weight 1.0
  framework,          -- weight 2.0
  language,           -- weight 1.0
  title,              -- weight 10.0
  content,            -- weight 1.0
  summary,            -- weight 3.0
  symbols,            -- weight 5.0 (AST-extracted Swift symbol names)
  symbol_components,  -- weight 1.5 (CamelCase splits: LazyVGrid → Lazy / VGrid / Grid)
  tokenize='porter unicode61'
);
```

Weight rationale:

- `title` dominates at 10× because Apple titles are concise, symbol-named, and the highest-signal field for "I'm looking for X" queries.
- `symbols` at 5× ensures AST-extracted symbol names beat random prose mentions. Without this, `Task` matches every page that uses the English word "task".
- `summary` at 3× boosts the curated 1-sentence abstract over the discussion body.
- `framework` at 2× breaks ties between `swiftui/view` and `webkit/view` when the query is `View SwiftUI`.
- `symbol_components` at 1.5× lets `vgrid` match `LazyVGrid` without requiring users to know the exact CamelCase form.
- All other columns at 1.0× are kept in the index for filterability, not for ranking signal.

#### 7.2.2 `docs_metadata`

One row per document. Non-FTS columns for filtering and JSON retrieval:

```sql
CREATE TABLE docs_metadata (
  uri TEXT PRIMARY KEY,
  source TEXT, framework TEXT, language TEXT,
  kind TEXT,                          -- func | class | struct | enum | actor | protocol | ...
  symbols TEXT,                       -- denormalized from doc_symbols for fast column read
  file_path TEXT, content_hash TEXT, last_crawled INTEGER, word_count INTEGER,
  source_type TEXT, package_id INTEGER, json_data TEXT,
  min_ios TEXT, min_macos TEXT, min_tvos TEXT, min_watchos TEXT, min_visionos TEXT,
  availability_source TEXT,           -- api | parsed | inherited | derived
  implementation_swift_version TEXT,  -- for swift-evolution rows: toolchain version
  FOREIGN KEY (package_id) REFERENCES packages(id)
);
```

`json_data` carries the full raw JSON, so `read_document` returns the original Apple payload without re-parsing the disk file. Trade-off: doubles the DB size. We accept it for read latency (§N2).

Indexes on `source`, `framework`, `language`, `kind`, `min_ios`, `min_macos`, `min_tvos`, `min_watchos`, `min_visionos`, `implementation_swift_version` keep attribute-filter queries < 10ms even at full corpus size.

#### 7.2.3 `docs_structured`

DocC-extracted declaration fields, one row per doc:

```sql
CREATE TABLE docs_structured (
  uri TEXT PRIMARY KEY,
  url TEXT, title TEXT, kind TEXT,
  abstract TEXT, declaration TEXT, overview TEXT,
  module TEXT, platforms TEXT,
  conforms_to TEXT, inherited_by TEXT, conforming_types TEXT,
  attributes TEXT,  -- @MainActor, @Sendable, @available comma-separated
  FOREIGN KEY (uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
);
```

This table is the surface for attribute queries: "find all protocols that inherit from `Equatable`" hits `inherited_by` directly, no FTS5 needed.

#### 7.2.4 `doc_symbols`

AST-extracted symbols, one row per declared symbol per doc:

```sql
CREATE TABLE doc_symbols (
  id INTEGER PRIMARY KEY,
  doc_uri TEXT, name TEXT, kind TEXT,
  line INTEGER, column INTEGER, signature TEXT,
  is_async INTEGER, is_throws INTEGER, is_public INTEGER, is_static INTEGER,
  attributes TEXT, conformances TEXT,
  generic_params TEXT, generic_constraints TEXT,
  FOREIGN KEY (doc_uri) REFERENCES docs_metadata(uri) ON DELETE CASCADE
);
```

`generic_constraints` is populated by the enrichment passes (§8). A separate FTS5 table `doc_symbols_fts` indexes `name`, `signature`, `attributes`, `conformances` for the semantic-search tools.

#### 7.2.5 `inheritance`

Edge table for class inheritance, populated from DocC's `relationshipsSections.inheritsFrom` and `inheritedBy` arrays:

```sql
CREATE TABLE inheritance (
  parent_uri TEXT, child_uri TEXT,
  PRIMARY KEY (parent_uri, child_uri)
);
```

A dedicated table (vs a JSON column on `docs_metadata`) because `NSObject` and `UIView` have thousands of descendants; a JSON-blob column would be unscannable and bloated.

#### 7.2.6 `framework_aliases`

Maps framework identifier, import name, display name, and search synonyms:

```sql
CREATE TABLE framework_aliases (
  identifier TEXT PRIMARY KEY,   -- "corebluetooth"
  import_name TEXT,              -- "CoreBluetooth"
  display_name TEXT,             -- "Core Bluetooth"
  synonyms TEXT                  -- "bluetooth"
);
```

Populated during indexing; the synonym column is updated by the `synonyms` enrichment pass (§8.1).

### 7.3 AST symbol extraction

After each doc is inserted, `ASTIndexer.Extractor` (SwiftSyntax) runs on two paths:

**Declaration path**: if the page has a `declaration.code` field (Apple's structured Swift declaration), extract symbol names, signatures, attributes, and import statements. Writes to `doc_symbols`.

**Code example path** (`extractCodeExampleSymbols`): for all pages with Swift code blocks in `discussion` sections, extract symbol names from usage snippets. This catches symbols that are used in examples but not formally declared by the page's own type. The extracted names are added to the page's `symbols` column for BM25 boost.

Coverage on the v1.2.0 corpus: ~165,000 of ~285,000 pages have at least one `doc_symbols` row. The remainder are pages with no Swift code (Objective-C frameworks, conceptual articles, HIG, sample-code metadata).

### 7.4 Audit log

Every door event (accept, Tier-A, Tier-B, Tier-C, placeholder reject, validity reject) is recorded as a `Search.ImportLogEntry` and serialized to JSONL via `Search.JSONLImportLogSink`. Writes are actor-isolated so concurrent strategies (apple-docs, swift-evolution, samples, etc.) interleave cleanly. The log path is surfaced in the `cupertino save` final report. JSONL was chosen over a DB-internal log table because:

- Crash-safe: each `\n` flush is durable. A killed indexer leaves a valid prefix.
- Diffable: between two runs we can diff the logs to spot regressions.
- Tooling-friendly: `jq`, `grep`, anything line-oriented.

---

## 8. Detailed Design: Enrich

Four passes run after the main indexing loop. Today they execute inline inside `Search.IndexBuilder.buildIndex()`; epic [#769](https://github.com/mihaelamj/cupertino/issues/769) extracts them into a standalone `cupertino-postprocessor` binary. Full design in `docs/design/post-processor.md`.

| Pass | Writes to | Reads from | Depends on |
|---|---|---|---|
| `synonyms` | `framework_aliases.synonyms` | hardcoded list of 22 mappings (`corebluetooth → bluetooth`, etc.) | nothing |
| `constraints` | `doc_symbols.generic_constraints` | `apple-constraints.json` (output of `swift symbolgraph-extract`) | nothing |
| `hierarchy` | same column | `doc_symbols` parent/child rows | `constraints` |
| `recovery` | re-inserts placeholder-title rejects | JSONL import log + URL leaf | nothing |

### 8.1 Synonyms

22 framework aliases get search-time alternate names so `bluetooth` finds `CoreBluetooth`, `nfc` finds `CoreNFC`, `mpsgraph` finds `MetalPerformanceShadersGraph`. The list is hardcoded (it doesn't change frequently and is small). The pass updates the `synonyms` column on existing `framework_aliases` rows; rows for frameworks not in the list keep `synonyms IS NULL`.

### 8.2 Constraints

Apple ships authoritative generic constraints for stdlib symbols via `swift symbolgraph-extract`. The `cupertino-constraints-gen` binary parses that output once at build time and produces `apple-constraints.json`. The `constraints` pass loads that JSON and joins it into `doc_symbols.generic_constraints` for symbols whose `pathComponents` match an entry.

This makes queries like "all stdlib protocols requiring `Self == X`" cheap: a WHERE on `generic_constraints LIKE '%Self == %'` against an indexed column.

### 8.3 Hierarchy

Symbol hierarchies in Apple's docs are flat: each page declares its own constraints but doesn't inherit parent constraints. The `hierarchy` pass walks parent→child edges in `doc_symbols` and propagates `generic_constraints` from parent to child. Required for accurate constraint queries on extensions and conformances.

Depends on `constraints` because it propagates the constraint values that pass writes.

### 8.4 Recovery

Some Apple JSON pages return `title: null` or `title: "error"` at fetch time and get rejected by the placeholder filter (§7.1.2). The recovery pass reads the JSONL import log, finds `placeholderTitle` rejections that have a recoverable URL leaf (e.g., `apple-docs://webkitjs/filereader/error`), and re-inserts the row with a synthesized title derived from the URL.

This is design tradeoff: recovered rows have a worse title than they would if Apple's renderer were healthy, but they exist in the index instead of being dropped. The alternative (drop them) loses content the user can clearly see exists on the live site.

Tracked at #777.

---

## 9. Detailed Design: Serve

### 9.1 Multi-pass ranker

The default `cupertino search <query>` is not a plain FTS5 MATCH. It is a multi-pass pipeline:

```
input query
   │
   ▼
┌──────────────────────────────────────────┐
│ 1. extractSourcePrefix                   │  "swift-evolution://" → source filter
│ 2. extractAttributeFilters                │  "@MainActor" → SQL WHERE clause
│ 3. sanitizeFTS5Query                      │  quote terms, split hyphens
└──────────────┬───────────────────────────┘
               │
       ┌───────┴───────────┐
       ▼                   ▼
┌──────────────┐   ┌──────────────────────┐
│ Symbol fast  │   │ BM25F                │
│ path (URI    │   │ bm25(docs_fts,       │
│ set from     │   │   1, 1, 2, 1,        │
│ doc_symbols_ │   │   10, 1, 3, 5, 1.5)  │
│ fts)         │   │                      │
└──────┬───────┘   └────────┬─────────────┘
       │                    │
       └────────┬───────────┘
                ▼
┌──────────────────────────────────────────┐
│ 4. HEURISTIC 1 (exact-title boost, #254) │
│    50× for clean match, 20× for suffix   │
│    Separates Swift's Task from           │
│    Mach kernel task_*                    │
└──────────────┬───────────────────────────┘
               ▼
┌──────────────────────────────────────────┐
│ 5. HEURISTIC 1.5 (URI simplicity + #256) │
│    shorter URI ranks above longer        │
│    + frameworkAuthority tiebreak         │
│    (swift, swiftui, foundation ↑;        │
│     webkitjs, installer_js ↓)            │
└──────────────┬───────────────────────────┘
               ▼
┌──────────────────────────────────────────┐
│ 6. HEURISTIC 1.6 (kind tiebreak, #610)   │
│    canonical type kinds (class, struct,  │
│    enum, protocol, actor) win over       │
│    property/method/initializer pages     │
│    Closes Task / View / Hashable wins    │
└──────────────┬───────────────────────────┘
               ▼
┌──────────────────────────────────────────┐
│ 7. fetchCanonicalTypePages (#254)        │
│    Force-include canonical apple-docs    │
│    page even if BM25 missed it           │
└──────────────┬───────────────────────────┘
               ▼
┌──────────────────────────────────────────┐
│ 8. RRF fusion (k=60, #192)               │
│    Reciprocal Rank Fusion across sources │
│    apple-docs 3.0 · evolution 1.5 ·     │
│    packages 1.5                          │
└──────────────┬───────────────────────────┘
               ▼
           results
```

BM25 scores are negative in FTS5 convention (lower = better match). Adjusted rank divides by the combined boost multiplier; a 50× exact-title boost moves a candidate above a 10× raw-BM25 winner.

#### 9.1.1 Why heuristics on top of BM25

Pure BM25F gets the right answer most of the time and the wrong answer in a small but high-visibility set of cases. The wrong answers cluster around:

- **Common nouns colliding with framework symbols**: `Array` matches every page that uses the word. BM25 buries the canonical `swift/array` type page under thousands of `someArray` prose mentions.
- **Property/method pages outranking type pages**: `URLSession.dataTask` is shorter than `URLSession` and has fewer terms, so BM25 with title weight ranks it above the type page.
- **JS framework pages matching Swift query intent**: `webkitjs/element` matches `Element` queries that meant `XMLDocument.element` or `Mirror.Element`.

Each heuristic addresses one of these failure modes empirically. #610 audit on v1.1.0 documents 14 wrong-winner cases; heuristic 1.6 closes 9 of them (Task, View, String, Array, Hashable, Equatable, Codable, Identifiable, Sendable). The remaining 5 (URL, Color, Font, List, Data) are Class B and recover via lossless URI canonicalization (#283), not via ranking.

### 9.2 RRF fusion

For a query without an explicit source prefix, the ranker runs per-source (apple-docs, swift-evolution, packages, ...) and fuses results via Reciprocal Rank Fusion (Cormack, Clarke, Büttcher 2009):

```
score(d) = Σ over sources s   weight(s) / (k + rank_in_s(d))
```

with `k = 60` (the standard RRF constant) and source weights tuned empirically: apple-docs gets 3.0, others get 1.5. The 2:1 ratio reflects that apple-docs is the largest and highest-signal source; we want it to dominate unless another source has a stronger match.

One dead source (e.g., samples.db missing because the user didn't run `--samples`) does not take the whole query down: its contribution is `0 / (60 + rank) = 0`.

### 9.3 MCP transport

JSON-RPC 2.0 over stdio. Each message is a single compact line plus a `\n` delimiter. No embedded newlines (MCP spec requirement). The server reads with line buffering, parses, dispatches, and writes the response on stdout. stderr is reserved for log output.

The MCP tools provided are summarized in `docs/ARCHITECTURE.md`. Tool implementations live in `SearchToolProvider`, which depends only on `ServicesModels`, `SearchModels`, `SampleIndexModels` (the protocol seams), not on `Search` or `SampleIndex` concrete writers. This keeps the MCP layer testable in isolation.

### 9.4 Read services

`cupertino read --source <s>` and the MCP `read_document` / `read_sample` / `read_sample_file` tools all delegate to `Services.ReadService`. The service dispatches on source:

| Source | Backing | Returns |
|---|---|---|
| `apple-docs`, `hig`, `apple-archive`, `swift-org`, `swift-book`, `swift-evolution` | `docs_metadata.json_data` | full JSON payload |
| `samples` | `Sample.Search.Service` | sample project metadata |
| `packages` | `Search.PackageQuery.fileContent` | package file content from `package_files_fts` |

No on-disk file reads at serve time. Everything is served from the SQLite databases.

---

## 10. Scalability Analysis

### 10.1 Current scale (v1.1.0)

| Quantity | Value |
|---|---|
| Apple docs pages crawled | ~412,000 |
| Apple docs pages indexed (post-dedup) | 285,735 |
| Frameworks | 420 |
| Pages with `doc_symbols` rows | ~165,000 |
| `search.db` size | ~2.4 GB |
| `packages.db` size | ~990 MB |
| `samples.db` size | ~185 MB |
| Sample projects | 619 |
| Indexed Swift sample files | ~18,000 |
| Compressed bundle | ~685 MB |

### 10.2 Design target: 10x

The principles file commits to designing for 10x current scale (4M docs). Per-component analysis:

**SQLite FTS5**. Production FTS5 deployments index O(10⁸) documents (Mozilla, Notion). At 4M docs, expected index size ~24 GB (linear with corpus). Query latency for FTS5 is `O(log N)` on the index; p99 stays well under 100ms at 4M docs.

**Door dedup map**. Per-run hashmap keyed by URI. At 4M docs:
- Average URI length: ~80 bytes
- Per-entry overhead (Swift Dictionary): ~64 bytes
- Total: ~570 MB resident during indexing

Acceptable on a build host. If we hit 40x (40M docs), we switch the hashmap to a bloom filter front + SQLite back, costing one extra DB hit per insert in exchange for O(1) memory.

**Per-row work at the door**: hashmap lookup (`O(1)`), SHA-256 (~40 μs on M1), one INSERT. No scans. The door is `O(N)` over the corpus; linear scaling.

**AST extraction**: SwiftSyntax parse of one declaration is ~5ms. At 4M docs × 50% AST coverage = 2M extractions × 5ms = ~2.8 hours. Acceptable.

**Crawl**: bottleneck is network + Apple's rate limit. We can't go below ~14 days at current delay; a 10x corpus would be ~140 days. **This is the binding constraint at scale**. Mitigation: parallel crawl from multiple IPs (operational, not in this design); incremental crawl (only fetch changed pages) is the design answer (G13).

**Bundle distribution**: GitHub Releases caps artifact size at 2 GB per file. At 10x corpus the compressed bundle is ~7 GB and needs chunking. Mitigation: split bundle by source (`search.db.zip`, `packages.db.zip`, `samples.db.zip`); `cupertino setup` already supports this.

### 10.3 Where scaling will hurt first

| Component | Scales to | Limit |
|---|---|---|
| FTS5 query | ~10⁸ docs | tens of GB index |
| Door hashmap | ~10⁷ docs | host RAM |
| WKWebView crawl | ~10⁶ pages | crawl time, not memory |
| Setup download | ~5 GB compressed | GitHub Releases per-file limit |
| os.log volume | ~10⁵ events/sec | macOS log subsystem throttling |

The first limit we hit at 10x is **crawl time, not architectural**. Incremental crawl (G13) is the long-pole feature.

---

## 11. Reliability & Failure Modes

| Failure mode | Detection | Mitigation |
|---|---|---|
| Crawler killed mid-run | none (silent) | session checkpoint resumes from last serialized BFS state |
| Indexer killed mid-run | partial DB rows | SQLite transactions; partial inserts rolled back on `cupertino save --clear` |
| Power loss during indexing | DB may have uncommitted | SQLite WAL keeps DB consistent; #236 is open for explicit WAL on local builds |
| Apple API returns malformed JSON | parser throws | per-page error; doesn't kill the crawl; rejected URLs logged |
| Apple changes JSON schema | parser fails on every page | manual: regression caught in next crawl; CI canary not yet implemented (open work) |
| Apple rate-limits | HTTP 429 | retry with backoff; `--request-delay` knob exposes the rate |
| Disk full | SQLite write fails | crawl/save exits non-zero with the SQLite error |
| Corpus repo corrupted (bad JSON) | door rejects per-page | logged to JSONL; manual recovery |
| Schema mismatch (old DB, new binary) | open-time version check | binary refuses to open; user runs `cupertino setup` for fresh bundle |
| Tier-C collision in run | `🚨` log + non-zero exit | save report names both URIs + content paths; user audits |
| MCP transport closed mid-response | error frame | host re-spawns server (host responsibility); `--no-reap` for Codex-style spawn-per-call |
| Concurrent `save` against same DB | undefined (SQLite write lock) | #253 open: detection and bail with clear error |

### 11.1 What we explicitly do NOT recover

- **In-place schema migrations**. We don't write them; users rebuild. Documented in #4 PRINCIPLES + `feedback_assume_no_local_db.md` memory.
- **Bad Apple content**. If Apple ships a page with a wrong title, we faithfully index the wrong title and the search ranker rewards the canonical (presumably correct) page.

---

## 12. Security & Privacy

### 12.1 Threat model

| Threat | Vector | Mitigation |
|---|---|---|
| Malicious documentation injecting prompts via MCP response | Apple's docs themselves | trust boundary: we trust apple.com content; same trust model as any agent that consults docs |
| Sandbox escape via WKWebView | crawler runtime | WKWebView is JS-isolated by macOS; we don't execute fetched JS, we only read its data layer |
| SQLite injection via search query | user input | `Search.Index.QueryParsing` sanitizes FTS5 special characters; parameterized SQL throughout |
| MCP server reads files outside corpus | path traversal | DB-backed reads only; `read_document` requires an `apple-docs://` URI, not a file path |
| Local DB tampered with | filesystem | DB is signed-and-notarized via Homebrew distribution; user-built DBs are user-trusted |

### 12.2 Data collected

None. The MCP server is stateless across sessions. Queries are not logged, not persisted, not transmitted. The os.log output stays on the local machine.

Telemetry, analytics, crash reporting, usage metrics: all explicitly **not** implemented. Adding any of these is a design change that requires an opt-in flag and a separate privacy review.

### 12.3 Network access at serve time

The serve binary makes **zero outbound network calls**. `cupertino setup` does (downloads the bundle from GitHub Releases over HTTPS); `cupertino fetch` does (crawls Apple); `cupertino serve` reads `search.db` and never opens a socket. This is enforceable by the `MCP layer` and `Search` packages not importing `URLSession` or `Network`.

---

## 13. Observability

### 13.1 Logging

`os.log` with subsystem `com.cupertino` and categories `crawler`, `mcp`, `search`, `cli`, `transport`, `pdf`, `evolution`, `samples`. Categories let consumers filter:

```
log show --predicate 'subsystem == "com.cupertino" AND category == "search"' --last 1h
```

The `Logging` concrete writer is composition-root-only: producer packages depend on `LoggingModels` (a protocol seam) and receive a `Recording` instance via init injection. This keeps producers testable without an os.log backend.

### 13.2 Progress signals

Long-running phases emit progress to stderr/stdout:

- Crawl: per-page `Saved` lines (configurable verbosity)
- Save: every-100-files `Progress: X/Y (indexed, skipped)` lines (#588)
- Door rejections: `⛔` for placeholder, `⏭️` for Tier-B, `🚨` for Tier-C
- Enrichment passes: **currently silent for 5+ minutes at end of save (#768)**; epic #769 fixes this by emitting per-pass start/end lines

### 13.3 Save report

End of `cupertino save` prints a structured summary:

```
✅ Indexed: N documents
⛔ Skipped (placeholder title): X
⏭️  Skipped (Tier-B dedup): Y
🚨 Collisions (Tier-C): Z   ← non-zero is a build failure
Audit log: /path/to/import-log.jsonl
```

### 13.4 Doctor

`cupertino doctor` is a read-only inspection over the local DB and filesystem state. It verifies:

- DB exists and opens at the expected schema version
- Framework coverage matches a baseline (no missing frameworks)
- Document counts are within expected ranges
- Sample DB optional sources are detected

Used as a smoke test after `setup` or `save`.

---

## 14. Testing Strategy

### 14.1 Test pyramid

| Tier | Tool | Scope | Count |
|---|---|---|---|
| Unit | Swift Testing (`@Test`, `@Suite`) | one type, one method, mocked deps via `withDependencies` | majority |
| Integration | Swift Testing tagged `.integration` | real SQLite, real WKWebView, real Apple docs (network) | smaller set |
| End-to-end | external (manual) | `cupertino save` on real corpus + golden-query regression | manual, pre-release |

Current count: ~330 test functions across 207 files, expanding to ~2,300+ runtime cases via `@Test(arguments:)` parameterization.

### 14.2 CI gates

Every PR runs:

- `xcrun swift build` (must compile)
- `xcrun swift test` (must pass)
- `swiftformat --lint` (zero diffs)
- `swiftlint` (zero violations)
- `scripts/check-package-purity.sh` (no producer→producer imports)
- `scripts/check-target-foundation-only.sh` (strict producer allow-list)
- `scripts/check-docs-commands-drift.sh` (CLI surface matches `docs/commands/`)
- `scripts/check-issue-body-staleness.sh` (issue refs in PR body are valid)

### 14.3 Regression locks

`docs/audits/stage-d-regression-locks-2026-05-17.md` documents the manual regression set (specific queries, specific expected top results) that must pass before any v1.x release. These are the queries that motivated heuristics 1, 1.5, and 1.6.

---

## 15. Rollout & Distribution

### 15.1 Channels

| Channel | Path | Audience |
|---|---|---|
| Homebrew | `mihaelamj/tap/cupertino` | macOS users |
| Direct binary | GitHub Releases attached binaries | scripted installs, CI |
| Source | `git clone + make build` | contributors |
| Pre-built bundle | GitHub Releases `cupertino-databases-vX.Y.Z.zip` | every install path (downloaded by `cupertino setup`) |

### 15.2 Version policy

Two version numbers are tracked separately:

- **Binary version** (`Shared.Constants.App.version`): the released cupertino CLI version.
- **Database version** (`Shared.Constants.App.databaseVersion`): the schema/content version of `search.db`.

They are decoupled. A binary version bump that doesn't touch the schema does not bump `databaseVersion`. A schema-bumping change bumps both. `cupertino setup` downloads the bundle whose name matches the binary's `databaseVersion`.

Backward compatibility:

- Binary refuses to open a `search.db` whose schema version is newer than the binary supports.
- Binary refuses to open a `search.db` whose schema version is older than the minimum supported. User runs `cupertino setup` for a fresh bundle.

There is no in-place migration. The rebuild-instead policy is documented in `docs/PRINCIPLES.md` and in the `assume-no-local-DB` memory entry.

### 15.3 Crawl-to-bundle cadence

The full pipeline runs out-of-band on the maintainer's hardware:

1. Apple changes its docs (continuously).
2. Maintainer kicks off `cupertino fetch --source all` (~14 days wall clock).
3. Cron-committed to `cupertino-docs` git repo (one commit per crawl session).
4. Maintainer runs `cupertino save` on the corpus (~12 hours).
5. Maintainer verifies via doctor + regression queries.
6. Maintainer tags a release, attaches the bundle to GitHub Releases.
7. Users run `cupertino setup` to pull the new bundle.

The crawl + save cost is paid once by the maintainer and amortized across every user. End users never run the full pipeline.

---

## 16. Alternatives Considered

### 16.1 Headless HTTP instead of WKWebView

**Considered**: pure URLSession + JSON decode against `tutorials/data/...`.

**Rejected**: ~1% of pages return `title: null` or a 3,297-byte React shell to non-browser fetches. Examples include some kernel pages (`exclave_textlayout_info_v1`) and certain WebKitJS property pages. WKWebView's JS execution is the only reliable way to get full content.

**Cost paid**: macOS-only crawling.

### 16.2 Vector / semantic search

**Considered**: embed every page via a sentence-transformer model; serve cosine similarity.

**Rejected as primary**: Apple-docs queries are symbol-named ~80% of the time. `URLSession.dataTaskPublisher` is a token-match query, not a semantic query. Adding an embedding lookup to every query adds 50-200ms of inference latency and a model dependency. The 20% of queries that benefit from semantic matching (conceptual queries: "how do I make a network request") are a real win but a complement, not a replacement.

**Status**: planned as Phase 2.5 (#183) as a parallel index, not a replacement.

### 16.3 Hash-based URIs

**Considered**: `apple-docs://<8-byte-SHA-of-URL>` instead of lossless path encoding.

**Rejected**: non-zero collision floor at any corpus size. At 4M docs (10x target), the expected number of 8-byte SHA collisions is `4e6² / 2 / 2⁶⁴ ≈ 4e-7` (one in 2.5 million corpora). Sounds small, but it's nonzero; a single collision corrupts the affected pages silently. The principles file commits to a zero-collision-floor design (`docs/PRINCIPLES.md` §1). Lossless URIs cost ~30% more bytes per row; we accept that cost.

### 16.4 Separate `cupertino-mcp` binary

**Considered**: ship the MCP server as a separate binary from the CLI.

**Rejected**: doubles deployment surface (two binaries, two formulas, two PATH entries, two update paths). Mode detection at startup (pipe-vs-TTY on stdin) is 5 lines of code. The binary contains both at ~4.3 MB total; the duplication is in compiled code, not in deployment friction.

### 16.5 Single fat library

**Considered**: one large SPM package containing all source.

**Rejected**: import boundaries cannot be enforced at compile time. The risk we've avoided by ExtremePackaging is `Search` accidentally importing `Crawler` because someone added a helper. With one library, every type is reachable from every other type. With 40 packages and a CI-enforced import contract, the build fails when the boundary is crossed. The cost is `Package.swift` boilerplate (large but mechanical); the benefit is structural.

### 16.6 PostgreSQL or MongoDB

**Considered**: server-backed DB for richer query and concurrent writes.

**Rejected**: deployment friction kills the "single binary, brew install" goal. SQLite is single-file portable, has FTS5 built in, and has zero operational overhead. The cost is no concurrent writers (one `cupertino save` at a time); we accept that.

### 16.7 Pre-rendered Markdown corpus

**Considered**: convert all Apple JSON to Markdown at crawl time, ship Markdown.

**Rejected**: loses structural metadata (declaration tokens, availability ranges, references). The structured JSON is the source of truth; Markdown is a lossy projection.

### 16.8 Solr / Elasticsearch

**Considered**: industry-standard search backends.

**Rejected**: external service, deployment burden, JVM dependency. SQLite FTS5 gives us 95% of Solr's BM25F capabilities at zero operational overhead. The 5% we lose (distributed sharding, more sophisticated analyzers) is not needed at our scale.

### 16.9 Official Swift MCP SDK

**Considered**: depend on the official `@anthropic-ai/mcp-swift-sdk`.

**Rejected**: longer line count, more dependencies, and missing several edge cases that real MCP clients (Claude Desktop, Codex, GitHub Copilot for Xcode) exercise around stdio framing and `Transport closed` recovery. Cupertino's hand-rolled implementation in the `MCP` package covers exactly the protocol surface needed (`docs/ARCHITECTURE.md` §"MCP Server Implementation"). When the official SDK matures and adds the missing edge-case coverage, this is worth re-evaluating.

---

## 17. Open Questions & Risks

### Open

| ID | Question | Tracking |
|---|---|---|
| Q1 | When does vector search enter the ranker? | Phase 2.5, after v1.0.3 ships |
| Q2 | What's the minimum-viable diagnostic block for MCP responses? | Phase 2.1 design pending |
| Q3 | Apple's JSON schema drift: do we add a CI canary that re-fetches N representative pages weekly? | Open work |
| Q4 | Can we ship a Linux server crawler variant by replacing WKWebView with a headless Chrome wrapper? | Open work, not in scope for v1.x |
| Q5 | Concurrent `cupertino save` against the same DB: detect and bail | #253 open |
| Q6 | Recovery pass: how aggressive should URL-leaf title derivation be? Just split on `_` and titlecase, or LLM-based? | #777, leaning toward mechanical only |
| Q7 | What happens to the 12-hour `save` time at 10x corpus? | open; AST extraction is the bottleneck |

### Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Apple changes JSON API shape | medium | high (parser breaks) | parser fails fast; manual fix cycle; CI canary (Q3) |
| R2 | Apple rate-limits aggressive crawlers | low | medium (slower crawls) | conservative default delay; respectful UA; back off on 429 |
| R3 | WKWebView macOS-only locks us out of cloud crawl | high (already the case) | medium | Linux crawler variant is open work (Q4) |
| R4 | 12-hour `save` makes iteration slow | high (current pain) | medium | enrichment separated (#769) so small fixes don't need full re-index |
| R5 | SQLite FTS5 BM25F doesn't scale past ~10⁸ docs | low at current scale | hypothetical | sharding architecture is well-understood; defer until needed |
| R6 | New MCP client doesn't tolerate our transport edge cases | medium | low (per-client fix) | mock agent + tagged integration tests per client family |

---

## 18. Future Work

These are deliberately out of scope for the current design but worth flagging for sequencing:

- **Phase 2.1**: Diagnostic block in MCP responses (`why_this_result`, `bm25_breakdown`, `heuristics_applied`) so agents can reason about ranking decisions instead of treating the response as opaque.
- **Phase 2.5**: Vector index as a parallel signal, fused into the existing ranker via RRF. Embedding model TBD; preference is for a small local-runnable model (~100M params) to preserve the offline guarantee.
- **Differential re-crawl**: read the `cupertino-docs` git history to enumerate pages Apple changed since the last commit; re-fetch only those. Cuts daily-update wall time from 14 days to hours.
- **Linux server crawler**: replace WKWebView with a Playwright/Chrome wrapper. Enables crawling from cloud VMs and CI.
- **Symbolgraph integration**: parse `swift symbolgraph-extract` output for more frameworks (not just stdlib) to richen the constraint table beyond what Apple's docs JSON exposes.
- **Agent skill mode beyond MCP**: stateless CLI invocations via OpenSkills; partially shipped, more work on response shape.
- **Tutor mode**: extension that scaffolds end-to-end SwiftUI / iOS sample code using indexed Apple sample-code projects as templates (Phase 3 per #183).

---

## 19. References

### Internal

- `docs/PRINCIPLES.md`: six engineering principles
- `docs/ARCHITECTURE.md`: package layout, file maps, ranker diagrams
- `docs/package-import-contract.md`: per-target allowed/forbidden imports
- `docs/design/post-processor.md`: enrichment-pass pipeline design (epic #769)
- `docs/audits/methodology.md`: audit and issue-hygiene policy
- `docs/audits/stage-d-regression-locks-2026-05-17.md`: pre-release regression set
- `docs/portability.md`: cross-Mac development setup

### External

- Robertson, Zaragoza, Taylor (2004), *Simple BM25 Extension to Multiple Weighted Fields*. The BM25F formula `docs_fts` implements.
- Cormack, Clarke, Büttcher (2009), *Reciprocal Rank Fusion outperforms Condorcet and individual Rank Learning Methods*. The RRF fusion `Search.SmartQuery` uses.
- Peng & Dabek (2010), *Large-scale Incremental Processing Using Distributed Transactions and Notifications*. Google Percolator; precedent for the enrichment-pass pattern in `cupertino-postprocessor`.
- Apache Solr Update Request Processor chain. Closest structural analogue to our enrichment passes.
- Elasticsearch enrich processor. Closest semantic analogue.
- Anthropic, *Model Context Protocol Specification* (2024). The serve protocol.
- SQLite FTS5 documentation. The full-text engine.
- SwiftSyntax / SwiftParser. The AST extraction toolchain.

### Roadmap

- GitHub issue [#183](https://github.com/mihaelamj/cupertino/issues/183): canonical roadmap
- GitHub issue [#769](https://github.com/mihaelamj/cupertino/issues/769): layer-separation epic (crawler / indexer / postprocessor / search+MCP)
- GitHub issue [#283](https://github.com/mihaelamj/cupertino/issues/283): URL case canonicalization (shipped v1.0.2)
- GitHub issue [#285](https://github.com/mihaelamj/cupertino/issues/285): dash/underscore canonicalization (in progress)
- GitHub issue [#777](https://github.com/mihaelamj/cupertino/issues/777): placeholder-title recovery pass
- GitHub issue [#768](https://github.com/mihaelamj/cupertino/issues/768): per-pass progress logging
