# Search-quality baseline: v1.2.0 candidate `search.db`

**Date:** 2026-05-20
**System under test:** `~/.cupertino-dev/search.db` (v1.2.0 candidate, 352,712 documents across 420 frameworks, schema `user_version = 18`, built by `cupertino save --docs` on 2026-05-19)
**Binary:** `Packages/.build/release/cupertino` 1.1.0 (develop tip + #779 fix + #802 FileSystem wrapper, post-merge `a00a7b1`)
**Methodology:** `docs/design/search-quality-eval.md` Phase 1 (single-system mode, no Phase 2 human judging)
**Universal rule:** `../private/mihaela-agents/Rules/universal/search-quality-eval.md`
**Companion handbook:** `docs/database-handbook.md` §5

This audit records the v1.2.0 candidate database's standing on Criterion 1 (good search) restricted to query classes **A (canonical lookup)** and **B (framework-root)** per the design's §1.4 taxonomy. It is an absolute baseline; future ranking changes are measured against this single-system snapshot using the same harness in paired mode. The classes C-H from the taxonomy are out of scope per design §3 (NG6).


**Cross-validation note (added 2026-05-21):** The `Binary` cited above is `cupertino 1.1.0` — that's what was on disk when this baseline was captured. The same 50-query corpus re-run with the v1.2.0 binary on the same v1.2.0-schema search.db produces the identical headline metric (see [`search-quality-versiondiff-v1.1.0-to-v1.2.0.md`](search-quality-versiondiff-v1.1.0-to-v1.2.0.md) — v1.2.0 binary's MRR = 0.9467, matching this audit's claim). The v1.2.0-binary-specific ranking change (PR #858's `OR generic_constraints LIKE ?` clause) doesn't move this corpus's headline number. So the baseline numbers carry to the as-shipped v1.2.0 binary even though the original capture was on 1.1.0.
---

## Aggregate

| Metric | Value |
|---|---|
| N queries | 50 |
| Right answer at rank 1 (P@1 perfect) | **46 / 50** (92%) |
| Right answer not in top 10 | **1 / 50** |
| MRR | **0.9467** |
| P@1 | 0.9200 |
| P@5 | 0.3280 |
| NDCG@10 | 1.7385 |

P@5 looks low next to MRR. Reason: the 50 queries each have exactly one canonical right answer in this design, so P@5 has a ceiling of 0.2 per query if at most one match is in the top 5. The observed 0.328 reflects queries whose right-answer regex also matches lower-ranked sibling URIs (e.g., the framework-root patterns like `apple-docs://swiftui($|/[^/]*$)` legitimately match many pages). The metric is correctly reported but it is not the headline number.

NDCG@10 > 1 is possible here for the same reason (multi-match patterns sum gains). Per design §8.2 this is a known accounting quirk and the metric remains useful for paired comparison, just not as an absolute on the [0,1] scale.

**Headline number is MRR = 0.9467.** A new ranking change has to maintain or improve this on the same 50-query corpus to claim no regression.

---

## Sub-perfect cases (4 of 50)

The four queries that did not yield a top-1 match. Each is informative.

| Query | First-relevant rank | Top-1 returned | Note |
|---|---|---|---|
| `SwiftUI View` | not in top 10 | `apple-docs://clockkit/swiftui-templates` | Two-word query. `View` token bound to `swiftui-templates` URI dominates over the canonical `apple-docs://swiftui/view`. Probable cause: the query text `SwiftUI View` ranks pages with both tokens highly, and clockkit/swiftui-templates contains both, while swiftui/view contains them less prominently in the indexed body. Realistic regression class for users typing two-word lookups for framework-rooted concepts. |
| `Combine Publisher` | 2 | `apple-docs://combine` | Top-1 is the framework root; the canonical `combine/publisher` page is at rank 2. Defensible result for a two-word query naming both the framework and the protocol; an LLM consumer reading top-2 sees what it needs. |
| `CoreData` | 3 | `apple-docs://foundation/cocoaerror/code/coredata` | Top-1 is the `CocoaError.Code.coreData` enum case, not the Core Data framework root. Probable cause: `framework_aliases` table maps `coredata` → CoreData but the framework root isn't winning the BM25F tie. The two preceding hits are deep API pages that contain the literal token `coredata`. |
| `MapKit` | 2 | `apple-docs://mapkitjs/mapkit` | Top-1 is the JavaScript variant (`mapkitjs`) instead of the native `mapkit` framework. Probable cause: `mapkitjs/mapkit` contains the token in both framework and path positions; native `mapkit` only in the framework position. Source-authority weights should bias toward native; they don't here. |

None of these is a regression vs the brew baseline (the paired pilot run on 2026-05-20 had the same outcomes); they are pre-existing ranking artefacts of the current BM25F + RRF configuration. Each is a candidate for a per-class follow-up evaluation per `docs/design/search-quality-eval.md` §14.2 (specifically class B framework-root for `SwiftUI View`, `Combine Publisher`, `MapKit`; class C acronym/synonym for `CoreData`).

---

## Method recap

50 canonical-lookup queries each paired with a right-answer URI regex. For each query, `cupertino search "<query>" --limit 10` was invoked via the develop-tip binary with `cupertino.config.json` set to `baseDirectory: ~/.cupertino-dev`. Top-10 URIs were extracted from stdout in document order. Per-query MRR, P@1, P@5, NDCG@10 computed against the regex. No statistical test reported (single-system mode); the harness's paired Wilcoxon path is exercised only in comparison mode.

Harness source: `/tmp/cupertino-search-eval-new-only.py` (not yet versioned in the repo; move to `scripts/eval/` per design §14.1 follow-up).
Full JSON dump (all 50 top-10 lists): `/tmp/cupertino-search-eval-new-only-20260520.json`.

---

## What this baseline does NOT measure

Per `docs/design/search-quality-eval.md` §1.5 (the two-criteria framing):

- **Criterion 1 classes C-H** (acronym, CamelCase fragment, deprecation-aware, cross-source canonical, prose, symbol-attribute). Each needs its own corpus and metric.
- **Criterion 2** (anti-hallucination): does an LLM agent given cupertino's top-K results actually produce correct Swift? This is the actual success measure; this baseline is at best a precondition. The Phase 1.7 agent-eval (design §14.4, not yet written) is where Criterion 2 gets measured.

A MRR-0.9467 baseline is necessary but not sufficient for high-quality agent grounding. An agent can still hallucinate even when the right doc is at rank 1.

---

## How to use this baseline

When evaluating a future ranking change (BM25F weight tweak, new tokenizer, schema change), re-run the same 50-query corpus on both the unchanged binary/DB and the changed binary/DB, use the paired-comparison mode (`/tmp/cupertino-search-eval.py` as written), and report the delta against this baseline.

A regression on MRR vs this 0.9467 mark, or on the P@1 perfect count of 46/50, demands explanation before the change ships. A regression in any of the 4 sub-perfect cases above is also worth noticing (they are where the current ranker is fragile).
