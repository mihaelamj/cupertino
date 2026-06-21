# Cupertino Database Handbook

The single entry point for every question about cupertino's database design, schema, indexing pipeline, probing, and search-quality evaluation. If you are asking "where is the doc about X" for any database / FTS5 / ranking / eval topic, the answer is one click away from this page.

This file is the canonical index. If a database-related doc or rule exists and is not linked from here, treat it as undiscoverable; the fix is to add it to this index in the same PR that introduces it.

> **Physical layout as of v1.3.0 (2026-05-31):** the unified `search.db` this handbook and `docs/architecture/database.md` describe is now shipped as 8 per-source databases (`apple-documentation.db`, `hig.db`, `apple-archive.db`, `swift-evolution.db`, `swift-org.db`, `swift-book.db`, `apple-sample-code.db`, `packages.db`), each in rollback journal mode so it opens read-only without an `-shm` sidecar. Every query / read / serve connection opens the databases read-only ([#1194](https://github.com/mihaelamj/cupertino/issues/1194)), so an end user cannot write or delete rows. The split is physical packaging only: the per-database schema, BM25F weights, enrichment passes, and ranking are unchanged, so the `search.db` schema reference in `docs/architecture/database.md` and the v1.2.0 search-quality baselines in §5 still apply per database. `cupertino setup` downloads `cupertino-databases-v1.3.0.zip` (742 MB).

---

## 1. Cold-start bootstrap order

A fresh Claude session (or a new human contributor) coming to database / search work should read in this order:

| Step | Read | Why |
|---|---|---|
| 1 | `cupertino/CLAUDE.md` (auto-loaded by Claude at session start) | Project conventions, active focus, the imported `mihaela-agents/Rules/AGENTS.md` rule index. |
| 2 | `docs/PRINCIPLES.md` | The engineering principles every database design rests on (lossless URIs, collisions at the door, garbage filtered at input, 10× scale headroom, correctness first). |
| 3 | `docs/architecture/database.md` | The Methods-style description of `search.db`: what we built on top of vanilla SQLite + FTS5, every table, every BM25F weight, every enrichment pass, every PRAGMA. |
| 4 | `../private/mihaela-agents/Rules/universal/search-quality-eval.md` | The universal IR-evaluation rule. Fires whenever any "system A is better than B" search-quality claim is being made. Hard prohibitions on anecdotal evals, paired Wilcoxon for significance, TREC pooling vs programmatic ground truth. |
| 5 | `docs/design/search-quality-eval.md` | The cupertino-specific evaluation design. Eight-class query taxonomy, both success criteria (good search + anti-hallucination), phased plan including the Phase 1.7 agent-end-to-end eval that is the actual release-blocker test. |
| 6 | Memory files (auto-load via `MEMORY.md` in the Claude session memory directory) | Project + feedback memories including the file-based-DB invariant and the research-mode behaviour rules. |

After this sequence, every database question has a named home to point at.

---

## 2. Understanding what the database IS

| File | Gives you |
|---|---|
| `docs/architecture/database.md` | Methods-style reference. Every table, every FTS5 config, every indexer stage, every query-layer trick (BM25F weights, RRF, intent routing). §10 has the related-work comparison to Dash, Algolia, Sourcegraph Zoekt, DevDocs, PostgreSQL FTS. |
| `docs/enrichment-inventory.md` | The flat checklist of every add-on cupertino layers on top of raw SQLite content: FTS5 tables, platform/version columns, AST-extracted symbol data, symbolgraph-derived constraints, the 7 enrichment passes, structured-doc + inheritance extraction. Pairs with the architecture doc (which carries the full DDL); this is the "name every enrichment" index. |
| `docs/symbolgraph-corpus.md` | The input side of the constraints enrichment (#9/#10): how the Apple SDK symbol-graph corpus is generated (`cupertino-symbolgraphs-gen` or the published GitHub Release), how `cupertino-constraints-gen` turns it into `apple-constraints.json`, where every artifact in the chain lives, and which is committed vs gitignored vs released. |
| `docs/PRINCIPLES.md` | The **why** behind the design (lossless URIs, collisions at the door, garbage filtered at input, 10× scale headroom). |
| `README.md` + `docs/ARCHITECTURE.md` | Current system-wide design, package layout, and crawl / index / serve overview. |
| `docs/ARCHITECTURE.md` | Package structure across the whole codebase (which target owns what). |
| `docs/package-import-contract.md` | Strict-DI import contract between cupertino's Swift targets. |

---

## 3. Designing a new database (packages.db, apple-sample-code.db, or a future one)

| File | Gives you |
|---|---|
| `docs/design/_TEMPLATE.md` | The annotated FAANG-style design-doc template. Copy and fill in. |
| `../private/mihaela-agents/Rules/universal/templates/design-doc.md` | The same template, lives in mihaela-agents as the canonical source. Use either. |
| `docs/architecture/database.md` | Re-read as the worked example of what a database design doc looks like end-to-end. |
| `docs/PRINCIPLES.md` | Constraints any new database design must respect. |
| Memory `cupertino_file_based_db_invariant.md` | Hard constraint: file-based embedded SQLite. No server, SaaS, vector-DB. |

---

## 4. Probing / exploring an existing database

| File | Gives you |
|---|---|
| `docs/architecture/database.md` §11 | Pointer table from every concern (schema definition, migrations, PRAGMAs, BM25F, RRF, AST extraction, symbol-graph constraints) to the live file in `Packages/Sources/`. Use this first; do not re-grep the codebase. |
| `docs/audits/methodology.md` | General audit methodology (issue body hygiene, file path checks, etc.). |
| `docs/audits/release-readiness-v1.2.0.md` | Worked example of schema-shape + count-shape validation. Pattern to copy. |
| `docs/database-quality-checks.md` + `scripts/check-db-quality.sh` | **Semantic-quality release gate.** Catches rotten *content* under a healthy schema — placeholder-duplicate junk, stale rows a non-clean rebuild left behind (the `docs_structured`/`docs_fts` population invariant). Run before publishing any bundle. Born from the 2026-06-21 hig.db 173-junk-dupe incident. |
| Memory `feedback_never_touch_brew_db.md` | **Read-only probing is fine; never write to the brew DB at `~/.cupertino/`**. SELECT and PRAGMA only. |

The brew DBs in `~/.cupertino/` (`apple-documentation.db`, `packages.db`, `apple-sample-code.db`, and the smaller per-source files) are user-production state. As of v1.3.0 they ship in rollback journal mode and cupertino opens them read-only on every query / read / serve path (#1194), so a normal `cupertino` invocation cannot write to them. For ad-hoc probing use a SQLite read-only connection (`file:...?mode=ro`) and never issue UPDATE / INSERT / DELETE / DDL against them. The dev copies in `~/.cupertino-dev/` are the experimentation target.

---

## 5. Testing search quality

| File | Gives you |
|---|---|
| `../private/mihaela-agents/Rules/universal/search-quality-eval.md` | The universal IR-evaluation rule. Applies to any project, not just cupertino. Hard prohibitions, metrics (P@k / MAP / MRR / NDCG / R-Precision), qrels paths (TREC pooling vs programmatic), paired Wilcoxon for significance, Phase 1 / Phase 2 split. |
| `docs/design/search-quality-eval.md` | The cupertino-specific specialisation. Eight-class query taxonomy (canonical lookup, framework root, acronym, CamelCase fragment, deprecation-aware, cross-source canonical, prose, symbol-attribute), each with the appropriate metric. **Both success criteria** (good search C1 + anti-hallucination C2). Phased plan including Phase 1.7 agent-end-to-end eval. |
| Memory `feedback_code_changes_as_ideas_for_future.md` | During research / audit / documentation work, frame code direction as ideas for future releases, not patches to land now. |

**Concrete baselines on the v1.2.0 candidate DB (2026-05-20)** (still the reference under v1.3.0: the per-source split changed packaging, not the per-database schema or ranking, so these paired-comparison baselines carry forward):
- `docs/audits/search-quality-baseline-v1.2.0.md` — classes A + B (canonical lookup, framework root): **MRR 0.9467, P@1 perfect on 46/50**. The reference for paired ranking-change comparisons.
- `docs/audits/search-quality-deprecation-baseline-v1.2.0.md` — class E (deprecation-aware): **Swift form wins 30/30 (100%) over NS-prefixed Obj-C form, sign-test p = 0.0078**. Cupertino reliably promotes modern Swift over legacy NS-class for the most user-visible anti-hallucination concern.
- `docs/audits/search-quality-crosssource-baseline-v1.2.0.md` — class F (cross-source canonical): **19/19 OK when the expected source is in top-10, p = 1.9 × 10⁻⁶**. Reveals that HIG and apple-archive content is systematically out-competed by apple-docs at top-1 due to the 6:1 source-weight ratio. This is the intended bias for AI-agent code-generation grounding but has a cost for design-vocabulary queries.
- `docs/audits/search-quality-fragment-baseline-v1.2.0.md` — class D (CamelCase fragment recall, #77): **mean P@1 = 1.0, mean P@5 = 0.92 across 20 fragment queries** (`Grid`, `Decoder`, `Session`, etc.). 14/20 fragments returned 5/5 matches. The `symbol_components` column is working as designed.
- `docs/audits/search-quality-acronym-baseline-v1.2.0.md` — class C (acronym / synonym): **4/22 top-1 (18%)**. `framework_aliases.synonyms` data exists in the schema but does not appear to route bare acronym queries (`NFC`, `wifi`, `bluetooth`, `ml`, `av`) to their canonical framework root. The worst-performing baseline so far; three candidate future directions in the audit doc.
- `docs/audits/search-quality-prose-baseline-v1.2.0.md` — class G (prose / conceptual): **4/15 strict any-top-3 (26.7%)**; estimated **8-10/15 (53-67%) human-adjusted** after honestly reading the misses. Hardest class to evaluate programmatically; the design's §14.3 (Phase 2 TREC-grade pooling) was designed for this case. BM25F `content=1.0` weight is the intentional trade-off that disadvantages prose; the audit notes a `--profile prose` weight-vector option as a candidate future direction.
- `docs/audits/search-quality-symbol-attribute-baseline-v1.2.0.md` — class H (symbol-attribute): **mean P@5 = 0.25**. Bimodal: queries whose attribute name is also a token-rich symbol (`@MainActor`, `protocol`, `Sendable`) score near 1.0; queries that map only to a `doc_symbols.kind` value (`initializer`, `subscript`, `typealias`, `generic constraint`) score 0. Cupertino's default FTS5 search path doesn't consult `doc_symbols` relational metadata; the `SearchByAttribute` code path exists but isn't reached from `cupertino search`. Three candidate future directions documented.

**All six of six §14.2 Phase 1.x classes (A-G) now have documented baselines on v1.2.0.** Last item: §14.4 Phase 1.7 anti-hallucination agent-end-to-end eval — the actual release-blocker test. Design exists at `docs/design/anti-hallucination-eval.md` (drafted 2026-05-20); implementation is the next 1-2 week work item. Until that lands and a first run publishes its baseline, the Criterion 2 (anti-hallucination) claim that motivates cupertino's existence is not yet directly measured.

**Visual dashboard for non-technical readers:** `docs/dashboards/search-quality-v1.2.0.html` — single-page HTML summary of all seven tests with Apple-style design (SF Pro fallback, system colors, card layout, light/dark mode). Plain-English claims, color-coded status (strong / mixed / weak), each card links to the full audit. Open in a browser; no server or build needed.

The relationship between the universal rule and the cupertino design is:
- The **universal rule** says "this is how IR evaluation must be done if it is done."
- The **cupertino design** says "this is how it is done here, for our specific corpus and consumer."

For the second one (anti-hallucination), the actual success measure is **the agent ships correct code** — `docs/design/search-quality-eval.md` §14.4 outlines the Phase 1.7 agent-end-to-end eval that captures this. That doc has not been written yet; when it is, it lives at `docs/design/anti-hallucination-eval.md` and gets linked here.

---

## 6. Behavioural rules baked into Claude memory

Auto-loaded at every Claude session in this project. None of these is optional.

| Memory file | Rule |
|---|---|
| `cupertino_file_based_db_invariant.md` | Cupertino DBs stay file-based embedded SQLite. Never propose server / SaaS / vector-DB. |
| `feedback_code_changes_as_ideas_for_future.md` | Research sessions produce docs / issues, not code patches. |
| `feedback_never_touch_brew_db.md` | `~/.cupertino/*` is read-only production state. |
| `cupertino-competitive-advantages.md` | Two-pass coverage, multi-source, AST-aware, schema-versioned, smart-query, hand-rolled MCP, latest protocol, self-diagnosing, open-weights. The product differentiators. |

Mirror at `mihaela-agents/memories/cupertino/` (committed and pushed; survives a Claude wipe).

---

## 7. How to keep this handbook honest

The handbook is the canonical index. It rots if new docs land without being linked here. Rules to keep it honest:

1. **When you add a database / search-quality doc**, add a link to it in this handbook in the same PR. Reviewers should refuse a docs-only PR that introduces a new database-related artefact without a handbook entry.
2. **When you delete a doc**, remove the link here in the same PR.
3. **When you rename a doc**, update the link here in the same PR.
4. **When a doc is superseded** (e.g., v1 design replaced by v2), update the link to point to the new one and note the old one's status in its own header.
5. **Section structure follows function**, not chronology. §2 "understanding" / §3 "designing new" / §4 "probing" / §5 "testing" / §6 "rules" matches the kinds of questions someone asks. Adding a new section is allowed; folding two sections together because content overlaps is also allowed.

If you are reading this and think a file should be linked from here but isn't, that is the bug. File an issue or land the fix.

---

## 8. Related entry points (non-database)

For completeness, other handbooks / indices that might be relevant when database work touches them:

- `docs/ARCHITECTURE.md` — package structure across the whole codebase.
- `docs/release/v1.2.0-checklist.md` — release-time validation of the bundled `search.db` (per-source counts, schema version, smoke queries).
- `cupertino/CLAUDE.md` — top-level project instructions; auto-loaded.
- `../private/mihaela-agents/Rules/AGENTS.md` — the universal rule index; auto-imported by cupertino's CLAUDE.md.

For everything else, start with `docs/ARCHITECTURE.md`.
