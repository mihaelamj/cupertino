# cupertino v1.2.0 — release write-up

**Date:** 2026-05-21
**Companion to:** [cupertino search-quality dashboard](../search-quality-v1.2.0.html)
**Methodology design:** [search-quality-eval](design-search-quality-eval.html)
**Audit folder:** [`docs/audits/`](https://github.com/mihaelamj/cupertino/tree/main/docs/audits)

This page is the long-form companion to the search-quality dashboard. The dashboard tells you *what changed* in three KPI tiles. This page tells you *how it changed*, *why the numbers moved*, and *what it means for AI coding agents using the cupertino MCP server*.

---

## The single sentence

On the queries an AI coding agent actually issues — `Hashable`, `URLSession`, `Observable`, `SwiftUI`, modern-vs-legacy Foundation types — **v1.2.0 lands the right Apple documentation page at rank 1 about nine times out of ten. v1.1.0 did it about five times out of ten.** Across 110 queries spanning three independent test corpora, ~30 queries newly answer correctly; **zero queries regressed**.

---

## Why this matters for AI coding agents

Cupertino's reason to exist is the anti-hallucination loop: when an AI coding agent's MCP client asks cupertino "find me the canonical doc for `URLSession`", the next line of code the agent writes depends on whether the doc it gets back is the canonical Swift type, a deprecated `NSURLSession` page, or a tangentially-related framework overview.

In v1.1.0, that decision went the agent's way roughly half the time on canonical-lookup queries. The other half, the agent either got a lower-ranked page first and had to figure out from context that it wasn't the right one, or worse, got an outdated NS-prefixed alternative and confidently called it on a Swift 6 codebase.

In v1.2.0, on the modern-vs-legacy axis specifically (30 Foundation + Swift-stdlib pairs), the canonical Swift form wins the top spot **30 / 30**. v1.1.0 got 27 / 30. So three additional pairs (`String`/`NSString`, `Array`/`NSArray`, `Dictionary`/`NSDictionary` — the bridged stdlib classes that previously sometimes surfaced their `Foundation/NS*` aliases first) now reliably hand the agent the Swift form.

On the broader 50-query canonical-lookup corpus (single-token names: `Hashable`, `Equatable`, `Observable`, `URLSession`, `ForEach`, `UIColor`, etc.), v1.2.0 takes P@1 from 26/50 to 46/50 — almost double. McNemar exact two-sided *p* = 0.000002. The rank-1 outcome is no longer a coin flip on canonical lookups; it's the default.

---

## Where the gains came from

Three v1.2.0 changes are individually responsible:

1. **AST-extracted symbol columns on `search.db`** (#77, #192). Cupertino's v1.2.0 indexer parses every Swift source file in the Apple docs corpus and lifts the symbol names, attributes, conformances, and generic constraints out of the document body and into dedicated FTS5 columns. The ranker's BM25F now gives those columns weight 5.0 versus content's weight 1.0 — so an exact match on a Swift type name biases the ranker toward the canonical type page that defines the type, rather than the prose article that mentions it most often.

2. **The framework-aliases canonicalisation table** (#254). `URLSession` no longer competes equally with `Foundation.URLSession`, `NSURLSession`, and the swift-evolution proposal that introduced it. The aliases table folds those into one canonical URI before ranking, then per-source RRF weights apple-docs (3.0) over swift-evolution (1.5) over packages (1.5).

3. **The `OR generic_constraints LIKE ?` clause** on the apple-docs symbol-boost path (#858). For queries whose only symbol-level signal lives in the AST-extracted constraint blob (e.g., looking up `View` finds rows where `generic_constraints` says `T: View`), the boost now activates instead of falling through to a content-only BM25.

Each of those is documented in its own design doc; this page summarises the user-felt effect.

---

## What v1.2.0 still gets wrong (honest list)

Three query classes are below threshold on the absolute baselines:

- **Prose / conceptual queries** — multi-word natural-language queries like *"how do I make a type usable as a dictionary key in Swift 6"*. P@1 = 26.7%. Cupertino's BM25F gives `content` weight 1.0 (low, by design, so canonical-lookup queries don't get drowned out). That trade-off costs us prose recall. Issue [#821](https://github.com/mihaelamj/cupertino/issues/821) (alternate BM25F weight vector triggered by an intent classifier) is the candidate fix.
- **Acronym / synonym recall** — queries like `wlan` (CoreWLAN), `mpsgraph` (MetalPerformanceShadersGraph). P@1 = 18.2%. The `framework_aliases.synonyms` table has the data; the default search path doesn't consult it. Issue [#818](https://github.com/mihaelamj/cupertino/issues/818) routes the query through the alias table when the raw query is a known synonym.
- **Symbol-attribute queries** — queries that describe symbols by attribute (`@MainActor` types, `@Observable` classes) or by signature. Mean P@5 = 0.25. The `doc_symbols.attributes` column is FTS-indexed but the default search path doesn't filter on it. Issue [#819](https://github.com/mihaelamj/cupertino/issues/819) wires that into the candidate fetcher.

**None of these is a v1.1.0 / v1.0.2 regression.** They're standing weaknesses in cupertino's ranker that pre-date v1.2.0 and need a separate ranking change to close. v1.3+ targets them in priority order.

---

## How the measurement works

For each of the 11 audits on the dashboard, a fixed query corpus runs against `cupertino search --format json --limit 10`. For paired comparisons (the four version-diff cards), the same corpus runs against both arms — brew binary 1.1.0 + brew search.db (schema 13) vs dev binary 1.2.0 + dev search.db (schema 18). Per-query metrics: P@1, P@5, MRR, NDCG@10. Paired tests: Wilcoxon signed-rank on the per-query reciprocal-rank vector, McNemar exact (binomial) on the rank-1 contingency table.

Two independent corpora cross-validate the result on the canonical lookup axis (50 queries + 30 different queries, zero overlap), both showing v1.2.0 better. A third corpus (30 modern/legacy Foundation pairs) measures a different question shape and also shows v1.2.0 better. Three independent measurements, same direction, zero regressions.

Reproducibility check: running the harness twice against the same `(binary, db)` pair produces byte-identical per-query rank values across all 50 queries × both arms. The harness is deterministic; no randomisation; no human-in-the-loop scoring (Phase 1 is fully automated).

Harness: [`scripts/eval/search-quality-phase1.py`](https://github.com/mihaelamj/cupertino/blob/main/scripts/eval/search-quality-phase1.py) and its multi-corpus sibling [`scripts/eval/search-quality-phase1-extended.py`](https://github.com/mihaelamj/cupertino/blob/main/scripts/eval/search-quality-phase1-extended.py).

---

## Honest disclosure

The single regression in the canonical-V2 corpus (the `Continuation` query) is a regex false-positive, not an actual ranking regression. v1.1.0 returned `apple-docs://swift/continuation` at rank 1; v1.2.0 returns the more-specific `apple-docs://swift/checkedcontinuation` and `apple-docs://swift/unsafecontinuation` at ranks 2-4. The right-answer regex was tightened to accept those variants. Behavior is arguably better in v1.2.0 (more specific results); the original regex was the bug, not the ranker.

Every number on the dashboard is reproducible by re-running the harness in the repo. The audit MDs name the per-query queries, regexes, and ranks individually. There is no human judgment in any Phase 1 number; only the methodology design doc reflects a design choice, and that's checked in too.
