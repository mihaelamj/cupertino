# Spec: Exhaustive Per-DB Schema Reference (search.db)

## Status (2026-05-20)

Living reference. Updated whenever a schema migration lands on
`main`. Companion to `per-db-enrichment.md` (which decides *why*
each DB exists) and `how-cupertino-answers-a-query.md` (which
decides *how* a query lands). This doc is the *what*: every
table, every column, every index, every type, every nullability.

Written so a reader who has never opened the codebase, never used
SQLite, and never heard of cupertino can answer "what does
cupertino store, where, and which code writes it" by reading only
this file.

This first revision covers **search.db**. Sibling sections for
samples.db + packages.db land as separate PRs in this same file.

---

## 0. How to read this document

If you have zero context, read sections in order: §1 explains what
cupertino is and why it has databases at all; §2 explains the
SQLite + FTS5 vocabulary used in every later section; §3 explains
how to read a column table; §4 onward goes table by table.

If you have project context, jump straight to the table-of-tables
in §4 and click the table name you care about.

---

## 1. One-paragraph primer for someone with zero context

**What cupertino is.** cupertino is a command-line tool you
install once via Homebrew (`brew install cupertino`). After install
you run `cupertino setup` which downloads a precomputed bundle (a
zip of three SQLite database files, ~5 GB total). Once that bundle
is in place, the cupertino binary acts as a fast local search engine
over Apple's developer documentation. Its primary consumer is the
cupertino MCP server, which exposes the search engine to AI coding
assistants (Claude Code, Cursor, Codex) so those assistants can
look up the right Apple API at sub-millisecond latency rather than
guess from training data that may be months out of date.

**Why three SQLite databases instead of one.** The bundle ships
three files because three different kinds of data have three
different shapes. The reference documentation (one row per Apple
documentation page, ~412 K rows) lives in `search.db`. Sample-code
projects (one row per project, each with its source files) live
in `samples.db`. Open-source Swift Package Manager packages (one
row per package, each with its files) live in `packages.db`. Each
DB has a schema tuned to its content; combining them would make
no schema fit anything well.

**Why this doc exists.** When a bug surfaces or a new feature
needs to add a column, a contributor needs to know what's already
there. Re-reading the schema source files is slow and the inline
SQL doesn't say *who* writes each column or *what code* reads it.
This doc is the spec.

---

## 2. SQLite + FTS5 + DocC vocabulary used below

If you've worked with relational databases before, skim this
section. If not, read it.

### 2.1 What an SQLite database is

A single file on disk (`*.db`). Inside the file: a set of tables.
A table is a grid; each row is one record; each column has a name
and a declared type. SQL queries (`SELECT ... FROM ... WHERE ...`)
read or write rows. SQLite is the engine that interprets those
queries and reads/writes the file accordingly. It is process-local;
there's no server — cupertino's binary opens the file directly.

### 2.2 What types SQLite enforces, loosely

A column is declared `TEXT`, `INTEGER`, or `REAL` (also `BLOB`
for raw bytes; cupertino doesn't use it). SQLite is dynamically
typed at the value level — you could technically write an integer
into a TEXT column and it would not refuse. Cupertino treats the
declared types as authoritative anyway and every insert path goes
through the matching `sqlite3_bind_text` / `sqlite3_bind_int(64)?`
C API call, so type mismatches don't accidentally happen.

`NOT NULL` and `DEFAULT <value>` are enforced. A column declared
`NOT NULL` with no default and not named in an `INSERT` statement
rejects the insert.

### 2.3 What a primary key, foreign key, and index are

- **Primary key (PK):** the column whose value uniquely identifies
  a row. `INTEGER PRIMARY KEY AUTOINCREMENT` is the common shape
  for synthetic id columns; SQLite generates the next integer at
  insert time. `TEXT PRIMARY KEY` is used when the natural row
  identifier is a string (e.g. a URI).

- **Foreign key (FK):** a column on table B whose value matches
  the primary key of some row in table A. The clause `FOREIGN
  KEY (b_col) REFERENCES a(a_pk) ON DELETE CASCADE` declares this
  intent. With `ON DELETE CASCADE`, deleting the row in A
  automatically deletes every referencing row in B.

- **Index:** a separate B-tree data structure SQLite maintains
  alongside a table so `WHERE column = ?` queries against the
  indexed column don't have to scan every row. Created by
  `CREATE INDEX <name> ON <table>(<column>)`. Indexes cost write
  speed and disk space; you only create them on columns you
  actually filter or sort by.

### 2.4 What FTS5 is

FTS5 is SQLite's full-text search extension. It is an opt-in
"virtual table" mechanism — a table created with `CREATE VIRTUAL
TABLE foo USING fts5(...)` does NOT store rows in the normal
row-store. Instead it maintains an inverted index from words to
row identifiers, optimised for `WHERE foo MATCH 'query'` queries.

Each FTS5 virtual table produces five shadow tables behind the
scenes (`foo_data`, `foo_idx`, `foo_content`, `foo_docsize`,
`foo_config`). Cupertino never reads or writes those; the column
tables below only list the virtual columns the developer code
actually binds into.

**Tokenizer.** Each FTS5 table picks a tokenizer that defines
what counts as a word. Cupertino uses two:

- `tokenize='porter unicode61'` for prose-shaped columns. Porter
  is an English stemmer that folds plural/verb endings so a
  search for `"buttons"` also matches `"button"`. `unicode61`
  handles non-ASCII tokens (accents, CJK, etc.) per the Unicode 6.1
  standard.
- `tokenize='unicode61'` (no Porter) for code-shaped columns.
  We don't want `func` and `funcs` collapsed when both are
  meaningful Swift tokens.

**BM25.** When `MATCH` returns multiple rows, FTS5's default
ranking function is BM25 — a tunable formula that scores rows by
how often the query terms appear in each row, normalised by row
length. Cupertino can also pass per-column BM25 weights (BM25F),
which is what makes a query-term hit in the `title` column
contribute more than the same hit in the `content` column.

### 2.5 What "AST extraction" means inside cupertino

When the indexer walks an Apple documentation page, the page
sometimes contains Swift code declarations (`struct Picker<Label,
SelectionValue, Content> { ... }`). Cupertino runs the SwiftSyntax
library over those code blocks. SwiftSyntax produces an Abstract
Syntax Tree — a parse tree of the source — from which the indexer
extracts each named declaration: its name, kind (`struct`, `func`,
`protocol`), generic parameters, conformances, attributes, line
position. Those extracted symbols become rows in the `doc_symbols`
table below.

### 2.6 What DocC is

DocC is Apple's documentation compiler. It turns Swift source
comments + standalone Markdown into a structured JSON format
(`*.json` files served under `developer.apple.com/tutorials/data/`).
cupertino's `cupertino fetch` crawler downloads those JSON files;
the indexer reads them; the parsed DocC fields populate the
columns of `docs_metadata` and `docs_structured` below. When the
doc references a DocC field (e.g. "DocC `roleHeading`"), it
refers to a named field in that JSON format.

---

## 3. How to read the per-column tables in §4 onward

Every column row carries six values, in this order:

| Column | Meaning |
|---|---|
| **name** | The literal column name as it appears in the CREATE TABLE statement. |
| **SQL type** | `TEXT`, `INTEGER`, etc. Declared type; SQLite enforces it through cupertino's bind paths. |
| **Nullable** | `NOT NULL` (cannot be missing) or NULL (can be missing). For FTS5 virtual columns this is marked "implicit" because FTS5 doesn't carry NULL semantics at the schema level. |
| **Default** | The value SQLite uses when an INSERT doesn't name this column. `—` means no default. |
| **What writes it** | Which Swift code path binds a value here, with source-file pointers where helpful. |
| **What reads it** | Which query path / CLI flag / MCP tool consults this column at read time. |

A table that opens with a `WHAT IT IS FOR, IN PLAIN TERMS` paragraph
explains the row shape before the column list — read that first.

---

## 4. search.db — quick table-of-tables

**On-disk path:** `~/.cupertino/search.db` (production / brew) or
`~/.cupertino-dev/search.db` (dev binary).

**Built by:** `cupertino save --docs` against a corpus rooted at
`~/.cupertino/docs/` (or `~/.cupertino-dev/docs/`). A full build
takes ≈12 hours on the Studio against the ~412 K-page Apple-docs
corpus. Output file is ≈2.7 GB.

**Schema version:** `PRAGMA user_version = 18`. Declared in
`Packages/Sources/Search/Search.Index.swift:88` as
`Search.Index.schemaVersion: Int32 = 18`.

**Sources stored.** A single search.db can hold rows from
multiple logically-distinct corpora. The `source` column on
`docs_metadata` is the discriminator. Possible values today:

- `apple-docs` — modern Apple framework reference (SwiftUI,
  UIKit, Foundation, …)
- `apple-archive` — legacy guides (Core Animation, Quartz 2D,
  KVO/KVC)
- `swift-evolution` — Swift Evolution proposals (SE-0001, …)
- `swift-org` — swift.org documentation pages
- `swift-book` — *The Swift Programming Language* book chapters
- `hig` — Apple's Human Interface Guidelines

A `swift-packages` source existed pre-#789; was removed because
the canonical packages store moved to packages.db.

**Tables in this DB** (13 user-facing + the FTS5 shadow tables):

| Table | Purpose | §  |
|---|---|---|
| `docs_fts` | FTS5 inverted index over every page's prose | 5.1 |
| `docs_metadata` | One canonical row per page; primary key URI | 5.2 |
| `docs_structured` | DocC structured fields extracted from `json_data` | 5.3 |
| `framework_aliases` | Per-framework identifier + alias mapping | 5.4 |
| `sample_code_metadata` | Apple sample-code cross-ref (URL → framework + zip) | 5.5 |
| `sample_code_fts` | FTS5 index over the cross-ref table above | 5.6 |
| `doc_code_examples` | Each `<CodeListing>` block found inside a page | 5.7 |
| `doc_code_fts` | FTS5 index over the code listings | 5.8 |
| `doc_symbols` | AST-extracted per-symbol declarations | 5.9 |
| `doc_symbols_fts` | FTS5 index over the symbol declarations | 5.10 |
| `doc_imports` | Each `import` statement in any page's code listings | 5.11 |
| `inheritance` | Edge table of superclass → subclass relationships | 5.12 |

---

## 5. search.db — table-by-table specification

### 5.1 Table: `docs_fts` (FTS5 virtual table)

**WHAT IT IS FOR, IN PLAIN TERMS.** The single largest piece of
work cupertino does at index time is read every Apple
documentation page's prose, normalise it, and feed it into a
search index that can answer queries like "how do I make a
navigation flow where the destination view depends on a runtime
selection?" in single-digit milliseconds. FTS5 is SQLite's
full-text search engine. This table is the FTS5 inverted index;
every word in every page's prose becomes an entry pointing back
at the page's URI. The text BM25-ranks those entries when a
query comes in. Every search query touches this table.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `uri` | TEXT | implicit | — | per-source insert paths in `Search.Index.Indexing.swift` bind the page's URI here so a JOIN to `docs_metadata.uri` always works | every search SQL JOINs `docs_fts f ON s.doc_uri = f.uri` to surface the prose context for ranked results |
| `source` | TEXT | implicit | — | same insert paths bind the source tag (`'apple-docs'`, `'hig'`, `'swift-evolution'`, …) | source-filter WHERE clauses in `Search.Index.Search.swift`; per-source CLI runners |
| `framework` | TEXT | implicit | — | bound to the parsed framework slug (`'swiftui'`, `'uikit'`, `'combine'`, …) | the `--framework` filter; framework-scoped queries |
| `language` | TEXT | implicit | — | bound to `'swift'` for Swift API pages, `'objc'` for Objective-C variants | the `--language` filter |
| `title` | TEXT | implicit | — | bound to the page's H1 heading or DocC `displayName` | FTS5 BM25 ranking — title hits rank high |
| `content` | TEXT | implicit | — | bound to the page's full prose, code blocks normalised | BM25 ranking; the bulk of the search signal |
| `summary` | TEXT | implicit | — | bound to the DocC `abstract` (first paragraph) | BM25 weighted lower than `title` and `content`; used for excerpt chunking |
| `symbols` | TEXT | implicit | — | bound to a denormalized blob of every AST-extracted Swift symbol name on the page (per #192 column D), joined with spaces | BM25 weight 5.0 — type-name queries hit here directly |
| `symbol_components` | TEXT | implicit | — | bound to the CamelCase-split form of `symbols` (`'LazyVGrid'` → `'Lazy VGrid Grid'`), per #77 | BM25 weight 1.5 vs `symbols` 5.0; lets a query `lazy grid` find `LazyVGrid` |

**FTS5 options:** `tokenize='porter unicode61'`. Porter stems
English plurals/verbs; `unicode61` handles non-ASCII.

### 5.2 Table: `docs_metadata`

**WHAT IT IS FOR, IN PLAIN TERMS.** This is the canonical
per-page row — one row per Apple documentation page in the
bundle. Every other docs-related table FK-references it via the
`uri` column. If you only kept one table from this DB, this is
the one — every search result emits row data joined back to
docs_metadata.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `uri` | TEXT | NOT NULL (PK) | — | per-source insert paths in `Search.Index.Indexing.swift`. URI shape is `apple-docs://<framework>/<lowercased-path>` (cupertino's internal URI scheme, not Apple's URL) | every JOIN target; the FK pivot for the whole DB |
| `source` | TEXT | NOT NULL | `'apple-docs'` | per-source insert paths bind one of `'apple-docs'`, `'hig'`, `'swift-evolution'`, `'swift-org'`, `'apple-archive'`, `'swift-book'` | source-filter WHERE clauses; per-source CLI runners; supported by index `idx_source` |
| `framework` | TEXT | NOT NULL | — | bound to the parsed framework slug at insert time | `--framework` filter; index `idx_framework`; corpus validation in `Search.IndexBuilder.buildFetchers` |
| `language` | TEXT | NOT NULL | `'swift'` | bound to `'swift'` / `'objc'` | `--language` filter; index `idx_language` |
| `kind` | TEXT | NOT NULL | `'unknown'` | per-source classifier per #192 column C1; values include `'class'`, `'struct'`, `'protocol'`, `'guide'`, `'tutorial'`, `'sampleCode'`, `'unknown'` | kind filter; index `idx_kind` |
| `symbols` | TEXT | NULL | — | the denormalized symbol name blob (#192 D) — same value as `docs_fts.symbols` | rare; this redundant column lets non-FTS SQL still see symbol names without a JOIN to FTS |
| `file_path` | TEXT | NOT NULL | — | absolute path to the source JSON file on disk during the indexing run | debug + `cupertino doctor` |
| `content_hash` | TEXT | NOT NULL | — | SHA-256 of the source page content at index time | #199 content-hash determinism check; re-index skip path |
| `last_crawled` | INTEGER | NOT NULL | — | epoch seconds when the crawler last touched this URI | freshness reporting (`cupertino doctor --freshness`) |
| `word_count` | INTEGER | NOT NULL | — | word count of the prose text bound into `docs_fts.content` | corpus statistics; `cupertino doctor` |
| `source_type` | TEXT | NULL | `'apple'` | bound to `'apple'` for first-party rows, otherwise the source slug | secondary classifier; index `idx_source_type` |
| `package_id` | INTEGER | NULL | — | **deprecated; always NULL post-#789.** Used to FK to a now-removed `packages` table inside search.db | nothing reads this column anymore; preserved for back-compat |
| `json_data` | TEXT | NULL | — | the full DocC JSON payload for the page, stored as text | source of truth for `docs_structured` extraction; future structured-query paths |
| `min_ios` | TEXT | NULL | — | #219 availability extraction; format `"13.0"` etc. | `--min-ios` filter; index `idx_min_ios` |
| `min_macos` | TEXT | NULL | — | same as above | `--min-macos` filter; index `idx_min_macos` |
| `min_tvos` | TEXT | NULL | — | same | `--min-tvos`; index `idx_min_tvos` |
| `min_watchos` | TEXT | NULL | — | same | `--min-watchos`; index `idx_min_watchos` |
| `min_visionos` | TEXT | NULL | — | same | `--min-visionos`; index `idx_min_visionos` |
| `availability_source` | TEXT | NULL | — | one of `'api'` / `'parsed'` / `'inherited'` / `'derived'`; records HOW the availability columns were populated | provenance display in `cupertino doctor` |
| `implementation_swift_version` | TEXT | NULL | — | #225 Part B; bound only on swift-evolution rows whose markdown carries an "Implemented in" version | `--swift` filter (swift-evolution scoped); index `idx_implementation_swift_version` |

**Indexes (11):** `idx_source`, `idx_framework`, `idx_language`,
`idx_kind`, `idx_source_type`, `idx_min_ios`, `idx_min_macos`,
`idx_min_tvos`, `idx_min_watchos`, `idx_min_visionos`,
`idx_implementation_swift_version`.

### 5.3 Table: `docs_structured`

**WHAT IT IS FOR, IN PLAIN TERMS.** DocC's JSON payload (stored
verbatim in `docs_metadata.json_data`) contains structured fields
that callers want to filter/sort on (the page's `module`, its
`abstract`, its list of `conforms_to` protocols, etc.). Parsing
JSON at query time would be slow. This table is the
denormalized form — every queryable DocC field gets its own
column, populated at index time by parsing `json_data` once.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `uri` | TEXT | NOT NULL (PK, FK→`docs_metadata.uri` ON DELETE CASCADE) | — | `Search.Index.IndexingDocs.swift` JSON parse path | `docs_structured`-aware filters in `Search.Index.Search.swift` |
| `url` | TEXT | NOT NULL | — | the DocC page's canonical `https://developer.apple.com/...` URL | result-formatting (`--format json`) |
| `title` | TEXT | NOT NULL | — | DocC `displayName` field | result-formatting |
| `kind` | TEXT | NULL | — | DocC `roleHeading` field (`'Structure'`, `'Protocol'`, `'Class'`, `'Article'`, `'Sample Code'`, …) | kind-aware queries; index `idx_docs_kind` |
| `abstract` | TEXT | NULL | — | DocC first-paragraph abstract | excerpt chunking |
| `declaration` | TEXT | NULL | — | DocC declaration fragment (the bare Swift signature) | result-formatting; symbol-search rendering |
| `overview` | TEXT | NULL | — | DocC long-form discussion section | excerpt chunking when `abstract` is too thin |
| `module` | TEXT | NULL | — | the Swift module the symbol belongs to (`'SwiftUI'`, `'UIKit'`, …) | module-scoped queries; index `idx_docs_module` |
| `platforms` | TEXT | NULL | — | comma-separated platform tags (`'iOS,macOS,visionOS'`) | not currently queried; reserved for future filter shape |
| `conforms_to` | TEXT | NULL | — | comma-separated protocol names this type conforms to | conformance graph queries; consumed by MCP `search_conformances` |
| `inherited_by` | TEXT | NULL | — | comma-separated subclass names (descendants in the class graph) | inheritance walk; superseded by the dedicated `inheritance` table for graph traversal |
| `conforming_types` | TEXT | NULL | — | comma-separated list of types that conform to this protocol | conformance walk; reverse direction of `conforms_to` |
| `attributes` | TEXT | NULL | — | comma-separated Swift attributes the type declares (`'@MainActor'`, `'@Sendable'`, `'@available(...)'`, …) | MCP `search_property_wrappers`, `search_concurrency`; index `idx_docs_attributes` |

**Indexes (3):** `idx_docs_kind`, `idx_docs_module`,
`idx_docs_attributes`.

### 5.4 Table: `framework_aliases`

**WHAT IT IS FOR, IN PLAIN TERMS.** Apple framework names come in
three forms: the URL slug Apple uses in paths
(`'corebluetooth'`, lowercased), the CamelCase Swift import name
(`'CoreBluetooth'`), and the human-readable display name (`'Core
Bluetooth'`). A user searching `'bluetooth'` doesn't know any of
those — they know the natural-language term. This table maps all
three plus a comma-separated list of natural-language aliases
that should resolve to the framework. The 22-entry alias list is
hand-curated and is what makes `'bluetooth'` → `'corebluetooth'`,
`'machine learning'` → `'coreml'`, etc.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `identifier` | TEXT | NOT NULL (PK) | — | lowercase framework slug; bound at index time by `Search.Index.Indexing.swift` from the corpus framework list | every framework filter; corpus validation; `Search.Index.resolveFrameworkIdentifier(...)` |
| `import_name` | TEXT | NOT NULL | — | the CamelCase Swift import name (`'CoreBluetooth'`, `'AppIntents'`) | rendering in result-formatting; index `idx_alias_import` |
| `display_name` | TEXT | NOT NULL | — | the human-readable form, from each framework's DocC root `module.displayName` (`'Core Bluetooth'`) | rendering; index `idx_alias_display` |
| `synonyms` | TEXT | NULL | — | comma-separated alias list (`'bluetooth'`, `'data'`, `'ml,machinelearning'`); written by `Enrichment.SynonymsPass` (the 22-entry hand-curated list, post-#837; pre-#837 this was a private method `Search.IndexBuilder.registerFrameworkSynonyms`) | every framework-resolution path; substring-match against this column is what makes `'bluetooth'` route to `'corebluetooth'` |

**Indexes (2):** `idx_alias_import`, `idx_alias_display`.

### 5.5 Table: `sample_code_metadata`

**WHAT IT IS FOR, IN PLAIN TERMS.** When the apple-docs indexer
encounters a DocC `<sampleCode>` node on a page (a reference to
a downloadable Apple sample-code project), it stores the
cross-reference here so queries can join from a documentation
page to its associated sample. The sample's ACTUAL contents
(every source file, every extracted symbol) live in `samples.db`,
not here — this table is just the URL → framework + downloadable
zip mapping.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `url` | TEXT | NOT NULL (PK) | — | the sample's `developer.apple.com` URL | cross-ref from docs result to sample row |
| `framework` | TEXT | NOT NULL | — | the framework slug the sample lives under | `--framework` filter on sample searches; index `idx_sample_framework` |
| `zip_filename` | TEXT | NOT NULL | — | the downloadable zip filename Apple publishes | `cupertino fetch --samples` |
| `web_url` | TEXT | NOT NULL | — | duplicate of `url` for legacy back-compat; some indexer paths bind the canonical landing URL here when it differs from `url` | rendering |
| `last_indexed` | INTEGER | NULL | — | epoch seconds | freshness reporting |
| `min_ios` | TEXT | NULL | — | derived from the framework's availability data | filter; index `idx_sample_min_ios` |
| `min_macos` | TEXT | NULL | — | same | filter; index `idx_sample_min_macos` |
| `min_tvos` | TEXT | NULL | — | same | filter; index `idx_sample_min_tvos` |
| `min_watchos` | TEXT | NULL | — | same | filter; index `idx_sample_min_watchos` |
| `min_visionos` | TEXT | NULL | — | same | filter; index `idx_sample_min_visionos` |

**Indexes (6):** `idx_sample_framework` + five `idx_sample_min_*`.

### 5.6 Table: `sample_code_fts` (FTS5 virtual table)

**WHAT IT IS FOR, IN PLAIN TERMS.** A small FTS5 index over the
title/description text of `sample_code_metadata` so cross-ref
queries from the docs side can do `WHERE sample_code_fts MATCH ?`
without scanning every row.

| Column | What writes it | What reads it |
|---|---|---|
| `url` | bound at insert from `sample_code_metadata.url` | result-formatting |
| `framework` | bound at insert | filter |
| `title` | the sample's title | BM25 ranking |
| `description` | the sample's abstract | BM25 ranking |

**FTS5 options:** `tokenize='porter unicode61'`.

### 5.7 Table: `doc_code_examples`

**WHAT IT IS FOR, IN PLAIN TERMS.** Documentation pages embed
example Swift code (`<CodeListing>` blocks in DocC). When
indexing a page, the indexer extracts each listing as its own
row here so a query for `"actor reentrancy"` can match against
code that uses `actor` even when the prose around it doesn't
say "actor". Each listing is one row; the parent page's URI is
the foreign key.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `id` | INTEGER | NOT NULL (PK AUTOINCREMENT) | — | auto-assigned at insert | row identity |
| `doc_uri` | TEXT | NOT NULL (FK→`docs_metadata.uri`) | — | the parent page's URI | every JOIN; index `idx_code_doc_uri` |
| `code` | TEXT | NOT NULL | — | the literal text of the code listing, lightly cleaned | result-formatting; mirrored into `doc_code_fts.code` |
| `language` | TEXT | NULL | `'swift'` | DocC's `syntax` attribute on the listing | language filter; index `idx_code_language` |
| `position` | INTEGER | NULL | `0` | the 0-indexed position of the listing within the page (so excerpts can be displayed in original order) | result-formatting |

**Indexes (2):** `idx_code_doc_uri`, `idx_code_language`.

### 5.8 Table: `doc_code_fts` (FTS5 virtual table)

**WHAT IT IS FOR, IN PLAIN TERMS.** FTS5 inverted index over the
code listings. Tokenizer is bare `unicode61` (no Porter stemmer)
because we don't want `func`/`funcs` collapsed when both are
meaningful Swift tokens.

| Column | What writes it | What reads it |
|---|---|---|
| `code` | bound from `doc_code_examples.code` at insert | FTS5 prefix-tokenised match for code-shaped queries (#192 D); BM25 ranking |

**FTS5 options:** `tokenize='unicode61'`.

### 5.9 Table: `doc_symbols`

**WHAT IT IS FOR, IN PLAIN TERMS.** Each documentation page often
declares one or more Swift symbols (a class, struct, function,
variable, …). Those declarations get extracted by SwiftSyntax AST
(see §2.5) and one row per symbol lives in this table. This is
where the "search for an async function" type of query lands,
because the row carries `is_async = 1` for those rows. The
constraint-enrichment work in #837 writes to `generic_constraints`
on this table.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `id` | INTEGER | NOT NULL (PK AUTOINCREMENT) | — | auto at insert | row identity |
| `doc_uri` | TEXT | NOT NULL (FK→`docs_metadata.uri` ON DELETE CASCADE) | — | parent page URI | index `idx_doc_symbols_uri`; every JOIN |
| `name` | TEXT | NOT NULL | — | the literal symbol name as SwiftSyntax sees it (`'NavigationLink'`, `'init(value:label:)'`) | index `idx_doc_symbols_name`; symbol-search WHERE |
| `kind` | TEXT | NOT NULL | — | one of `'classDecl'`, `'structDecl'`, `'protocolDecl'`, `'enumDecl'`, `'funcDecl'`, `'varDecl'`, `'extensionDecl'`, etc., per the `ASTIndexer.SymbolKind` enum | kind filter; MCP `search_property_wrappers` / `search_concurrency`; index `idx_doc_symbols_kind` |
| `line` | INTEGER | NOT NULL | — | source-line offset of the declaration within the page's text | navigation links in `cupertino fetch-doc` |
| `column` | INTEGER | NOT NULL | — | source-column offset | same |
| `signature` | TEXT | NULL | — | the literal declaration signature (`'func navigate(to destination: View)'`) | symbol-search where-clause harvesting #755; result-formatting |
| `is_async` | INTEGER | NOT NULL | `0` | `1` iff signature contains `async`, parsed at index time | MCP `search_concurrency`; index `idx_doc_symbols_async` |
| `is_throws` | INTEGER | NOT NULL | `0` | `1` iff signature contains `throws` | MCP `search_concurrency` |
| `is_public` | INTEGER | NOT NULL | `0` | `1` iff signature carries `public` / `open` | symbol filter |
| `is_static` | INTEGER | NOT NULL | `0` | `1` iff signature carries `static` / `class` (the Swift keyword form) | symbol filter |
| `attributes` | TEXT | NULL | — | comma-separated Swift attributes (`'@MainActor,@Sendable'`) | MCP `search_property_wrappers`; mirrored into `doc_symbols_fts.attributes` |
| `conformances` | TEXT | NULL | — | comma-separated conformed protocols (`'View,Hashable'`) | MCP `search_conformances`; mirrored into `doc_symbols_fts.conformances` |
| `generic_params` | TEXT | NULL | — | comma-separated generic parameter NAMES (`'Label,Destination,Content'`) — iter 1 from SwiftSyntax | symbol-shape queries |
| `generic_constraints` | TEXT | NULL | — | comma-separated authoritative CONSTRAINTS (`'View,Hashable,View'`). Three writers in order: (1) iter 1 inline at AST extraction time when the source had `<T: View>`; (2) iter 3 — `Enrichment.AppleConstraintsPass` (post-#837; was `applyAppleStaticConstraints` inline pre-#837) — overrides iter 1 from the cupertino-symbolgraphs lookup; (3) iter 2 — `Enrichment.HierarchyPass` — fills NULL child rows from the now-richer parent map. Order matters: iter 3 must precede iter 2 so the hierarchy walk reads the authoritative values | MCP `search_generics`; symbol-search WHERE/JOIN; index `idx_doc_symbols_generic_constraints` |

**Indexes (5):** `idx_doc_symbols_uri`, `idx_doc_symbols_kind`,
`idx_doc_symbols_name`, `idx_doc_symbols_async`,
`idx_doc_symbols_generic_constraints`.

### 5.10 Table: `doc_symbols_fts` (FTS5 virtual table)

**WHAT IT IS FOR, IN PLAIN TERMS.** FTS5 index over the symbol
declarations. Tokenizer is bare `unicode61` (no Porter); code-shape
matters here too.

| Column | What writes it | What reads it |
|---|---|---|
| `name` | mirrored from `doc_symbols.name` at insert | symbol-name FTS match (case-insensitive via `unicode61` folding) |
| `signature` | mirrored | signature FTS match |
| `attributes` | mirrored | attribute search |
| `conformances` | mirrored | conformance search |

**FTS5 options:** `tokenize='unicode61'`.

### 5.11 Table: `doc_imports`

**WHAT IT IS FOR, IN PLAIN TERMS.** Each `import` statement found
inside any page's code listings becomes a row here. Useful for
cross-referencing — "which pages import Combine" — and for
extracting the implicit module graph from the documentation.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `id` | INTEGER | NOT NULL (PK AUTOINCREMENT) | — | auto | identity |
| `doc_uri` | TEXT | NOT NULL (FK→`docs_metadata.uri` ON DELETE CASCADE) | — | parent page URI | index `idx_doc_imports_uri` |
| `module_name` | TEXT | NOT NULL | — | the bare module name (`'SwiftUI'`, `'Combine'`) | index `idx_doc_imports_module`; cross-ref queries |
| `line` | INTEGER | NOT NULL | — | source line offset within the listing | navigation |
| `is_exported` | INTEGER | NOT NULL | `0` | `1` iff `@_exported import` | rarely; specialty queries |

**Indexes (2):** `idx_doc_imports_uri`, `idx_doc_imports_module`.

### 5.12 Table: `inheritance`

**WHAT IT IS FOR, IN PLAIN TERMS.** Each `parent → child` class
inheritance edge from Apple's docs gets a row. Extracted at index
time from DocC's `relationshipsSections.inheritsFrom` and
`inheritedBy` arrays. The composite primary key prevents the
same edge from appearing twice when it shows up on both ends.

| Column | SQL type | Nullable | Default | What writes it | What reads it |
|---|---|---|---|---|---|
| `parent_uri` | TEXT | NOT NULL (composite PK) | — | URI of the superclass | inheritance walk; index `inheritance_by_parent` |
| `child_uri` | TEXT | NOT NULL (composite PK) | — | URI of the subclass | inheritance walk; index `inheritance_by_child` |

**Indexes (2):** `inheritance_by_parent`, `inheritance_by_child`.

---

## 6. Migration history (search.db)

`Search.Index.schemaVersion: Int32 = 18` is the current value. The
migration runner in `Search.Index.Migrations.swift` chains every
older DB forward to the current version on open. Each migration
function is named `migrateToVersion<N>()`. Version-number gaps
reflect a few abandoned-then-reverted schema directions; #635 is
the schema-stamp safety guard ensuring unknown versions are
rejected with a clear "rebuild via `cupertino setup`" message
rather than silent data corruption.

| Bump | Issue | What landed |
|---|---|---|
| → 2 | initial | Tables defined inline by `createTables()` for fresh DBs; older DBs migrate from v1's docs_fts-only shape |
| → 3 | early Phase 1 | `doc_code_examples` + `doc_code_fts` (code-listing extraction) |
| → 4 | early Phase 1 | `json_data` column on `docs_metadata` (full DocC JSON for structured extraction later) |
| → 6 | #192 D | `source` column on `docs_metadata`; multi-source indexing |
| → 7 | #192 D | `language` column on `docs_metadata` (Swift vs Obj-C variants); BREAKING — full reindex required |
| → 10 | #219 | availability columns (`min_ios`, `min_macos`, …) on `docs_metadata` + indexes |
| → 11 | #219 follow-up | `availability_source` column |
| → 16 | #749 | `inheritance` table (#274); `attributes` column on `docs_structured`; index hardening per the schema-stamp guard |
| → 17 | #755 | `generic_constraints` column on `doc_symbols` + index |
| → 18 | #789 | drop the redundant `packages` and `package_dependencies` tables (canonical packages store moved to packages.db) |

---

## 7. What search.db does NOT store

Calling out gaps that surprise readers:

- **The raw DocC JSON artefacts themselves.** Only the page-level
  text payload is stored in `docs_metadata.json_data`. The
  `*.json` files on disk live under `~/.cupertino/docs/` and are
  managed by `cupertino fetch` independently of the search index.
- **Image / asset binaries.** Not stored; the corpus references
  them by URL.
- **Per-page raw HTML.** Not stored; cupertino indexes the DocC
  JSON, never the rendered HTML.
- **Swift package metadata.** Was here pre-#789; moved to
  packages.db.
- **Sample code SYMBOL extracts.** Cross-referenced via
  `sample_code_metadata` but the actual extracted symbols live in
  samples.db. The two indexes are queried separately and the
  cross-source SmartQuery fan-out unifies them at read time (see
  `how-cupertino-answers-a-query.md`).

---

## 8. References

- Source code: `Packages/Sources/Search/Search.Index.Schema.swift`
  (CREATE TABLE statements), `Packages/Sources/Search/Search.Index.Migrations.swift`
  (in-place ALTER paths).
- Companion docs: `docs/design/per-db-enrichment.md` (the *why*),
  `docs/design/how-cupertino-answers-a-query.md` (the *read
  path*), `docs/design/post-processor.md` (the enrichment pipeline
  shape), `docs/design/837-pre-index-test-plan.md` (correctness
  gate before any save run).
- Schema-stamp safety guard:
  `Issue635SchemaStampGuardTests.swift` — unknown versions are
  rejected with a clear remediation message.

---

**Next revisions of this doc** add §9 samples.db and §10
packages.db at the same exhaustive level, plus a §11 cross-DB
column mapping (which user-visible filter touches which column on
which DB). Those land as separate PRs.
