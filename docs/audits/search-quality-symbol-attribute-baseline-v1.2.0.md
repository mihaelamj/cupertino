# Search-quality baseline: symbol-attribute (Phase 1.6, v1.2.0 candidate)

**Date:** 2026-05-20
**System under test:** `~/.cupertino-dev/search.db` (v1.2.0 candidate)
**Binary:** `Packages/.build/release/cupertino` 1.1.0 (post-merge `a00a7b1`)
**Methodology:** `docs/design/search-quality-eval.md` §14.2 Phase 1.6 (symbol-attribute), query class H from §1.4
**Companion handbook:** `docs/database-handbook.md` §5

This audit tests symbol-attribute queries — queries that conceptually describe symbols by attribute (`@MainActor`, `@Observable`), by signature flag (`async throws`, `public static`), by conformance (`Sendable conformance`, `Hashable conformance`), or by kind (`actor type`, `protocol type`, `initializer`, `subscript`, `typealias`). Unlike previous phases where relevance was defined by a URI regex, here relevance is defined by a SQL filter against the `doc_symbols` table.

A URI is "relevant" for a query iff there's at least one row in `doc_symbols` for that `doc_uri` matching the per-query SQL filter. For "actor type" the filter is `kind = 'actor'`; for "Sendable conformance" it's `conformances LIKE '%Sendable%'`; etc. The metric is **P@5 only** per the design — MRR is meaningless when relevance is set-membership rather than a singleton.

---

## Aggregate

| Metric | Value |
|---|---|
| Queries | 15 |
| **Mean P@5 (headline)** | **0.2533** |
| Mean P@1 | 0.2000 |
| Mean P@10 | 0.2667 |
| Zero P@5 queries | 8 / 15 |

This is the second-poorest baseline by P@5 after acronym (which was even more dramatic: 4/22 = 18%). For symbol-attribute, the picture is bimodal: some queries score near 1.0, many score 0.

---

## The bimodal split

**Strong (P@5 ≥ 0.6):**

| Query | Relevant set size | P@5 | First-match rank |
|---|---|---|---|
| @MainActor | 4,892 | **1.00** | 1 |
| protocol type | 2,540 | **1.00** | 1 |
| Sendable conformance | 179 | 0.60 | 2 |
| Hashable conformance | 67 | 0.60 | 3 |

**Weak (0 < P@5 < 0.6):**

| Query | Relevant set size | P@5 | First-match rank |
|---|---|---|---|
| public static | 27,846 | 0.20 | 1 |
| @Observable | 13 | 0.20 | 3 |
| @available | 13 | 0.20 | 3 |

**Zero P@5 (no relevant in top-5):**

| Query | Relevant set size | First-match rank |
|---|---|---|
| async throws | 1,459 | not in top-10 |
| Codable conformance | 46 | 10 |
| View conformance | 599 | 7 |
| actor type | 3 | 6 |
| initializer | 18,497 | not in top-10 |
| subscript | 760 | not in top-10 |
| typealias | 2,761 | not in top-10 |
| generic constraint | 17,475 | not in top-10 |

---

## What this baseline says

The split is consistent with cupertino's actual search architecture. The default search path goes through FTS5 over `docs_fts` columns (`uri`, `source`, `framework`, `language`, `title`, `content`, `summary`, `symbols`, `symbol_components`). It does NOT consult `doc_symbols.kind`, `doc_symbols.is_async`, `doc_symbols.attributes`, or `doc_symbols.conformances` directly.

A query for `@MainActor` works because the literal token `MainActor` appears in `docs_fts.symbols` (extracted by ASTIndexer at index time) and in `docs_fts.content` (Apple's prose mentions @MainActor). A query for `initializer` does NOT work because the token `initializer` rarely appears in titles or content (the title might say `init(_:)` instead), and the `kind='initializer'` filter is not part of the default search path.

This is **architecturally consistent with the database design** documented in `docs/architecture/database.md`. The `doc_symbols` table is a relational store for symbol-level metadata; the default FTS5 search is a separate path. The intended access pattern for attribute-style queries is via `Search.Index.SearchByAttribute` (file: `Packages/Sources/Search/Search.Index.SearchByAttribute.swift`), which exists in the codebase but is invoked only by code paths that explicitly want filter-based search, not by `cupertino search "<query>"`.

For an LLM agent or human typing `cupertino search initializer` and expecting initializer-defining pages, the current path returns nothing useful. To get attribute-filtered results today the consumer must reach for filter-style query operators that the CLI does not currently expose as a first-class flag.

---

## Why some attribute queries DID work

`@MainActor`, `Sendable conformance`, `protocol type`, `Hashable conformance` — these all happen to align with token-presence:

- `MainActor` is also a Swift type name, indexed in `docs_fts.symbols` at weight 5.0
- `Sendable` is a Swift protocol name, same
- `Hashable` same
- `protocol` is a Swift keyword that appears in titles and content
- `actor` (in `actor type`) appears in titles for the 3 actor-defining pages but those pages don't dominate

So the win isn't the symbol-attribute mechanism working; it's a coincidence that the attribute name is also a token-rich symbol name. When the attribute name is a generic English word that doesn't surface as a symbol (`initializer`, `subscript`, `typealias`, `generic constraint`), the query fails completely.

---

## Possible future directions (out of scope for this audit)

Per the `feedback_code_changes_as_ideas_for_future` rule:

1. **CLI flag for kind-based filtering.** `cupertino search --kind initializer` or `--kind actor` would route through `SearchByAttribute` and return all pages with at least one matching symbol. Small CLI surface change; harness logic already exists. Highest-value first move.
2. **Heuristic intent routing for attribute queries.** Queries that match the pattern `^(async|throws|public|static|init|subscript|typealias|@\w+|.* conformance)$` route through `SearchByAttribute` automatically. More work, but no flag-discovery burden on the consumer.
3. **Augment FTS5 with attribute tokens.** Add a `attributes` column to `docs_fts` containing concatenated per-page attribute / conformance strings, BM25F-weighted (similar to `symbols`). Largest surface change; affects schema (`user_version` bump); requires reindex.

The acronym audit (`search-quality-acronym-baseline-v1.2.0.md`) raised analogous concerns about `framework_aliases.synonyms` not being consulted at FTS5 ranking time. Both audits point at the same broader pattern: cupertino's relational metadata tables are richer than the default FTS5 search path consults. A consolidated design for "non-text search modes" could address both classes simultaneously.

---

## Implications for Criterion 2 (anti-hallucination)

An AI agent issuing `find async throws functions returning Result` gets top-10 results that don't constrain on async/throws/return-type. The agent then has to read those pages and hope they're relevant; for most of the 8-zero-P@5 queries above, none would be useful.

Mitigation in current state: the agent would need to issue more concrete queries (`Result<Success, Failure>` plus `async throws` separately and intersect mentally) rather than rely on cupertino to filter. This is feasible but inefficient.

The Phase 1.7 agent-end-to-end eval (`docs/design/search-quality-eval.md` §14.4) is where the practical impact of these attribute-query limitations gets measured end-to-end. Until that lands, this 25% baseline is the closest signal.

---

## Method recap

15 (query, sql_filter) pairs. For each:
1. Compute `relevant_uris = {row.doc_uri for row in doc_symbols WHERE <filter>}`
2. Run `cupertino search "<query>" --limit 10`
3. Compute P@1, P@5, P@10 against `relevant_uris` membership

Read-only SQLite via `file:...?mode=ro`. No writes anywhere.

Harness source: `/tmp/cupertino-search-eval-symbol-attribute.py`.
Full JSON dump: `/tmp/cupertino-search-eval-symbol-attribute-20260520.json`.

---

## Combined Phase 1 baseline coverage on v1.2.0

All 6 of 6 query classes A-G from §1.4 (excluding Phase 1.7 which is its own design) now have documented baselines on the v1.2.0 candidate DB:

| Baseline | Class | Headline | Interpretation |
|---|---|---|---|
| `search-quality-baseline-v1.2.0.md` | A + B | MRR 0.9467, P@1 46/50 | Strong; the canonical use case |
| `search-quality-deprecation-baseline-v1.2.0.md` | E | 30/30 Swift wins, p = 0.0078 | Strong; anti-hallucination axis intact |
| `search-quality-crosssource-baseline-v1.2.0.md` | F | 19/19 conditional, p = 1.9 × 10⁻⁶ | Strong but biased (intentionally) |
| `search-quality-fragment-baseline-v1.2.0.md` | D | P@1 = 1.0, P@5 = 0.92 | Strong; symbol_components working |
| `search-quality-acronym-baseline-v1.2.0.md` | C | 4/22 = 18% | **Weak**; synonyms not at ranking time |
| `search-quality-prose-baseline-v1.2.0.md` | G | 4/15 = 26.7% strict (53-67% adj) | Methodology-limited; BM25F trade-off |
| **`search-quality-symbol-attribute-baseline-v1.2.0.md`** (this doc) | **H** | **P@5 = 0.25** | **Weak; default path doesn't consult doc_symbols metadata** |

Remaining: §14.4 Phase 1.7 anti-hallucination agent-end-to-end eval. That is its own design (`docs/design/anti-hallucination-eval.md`, not yet written) and the actual release-blocker test.
