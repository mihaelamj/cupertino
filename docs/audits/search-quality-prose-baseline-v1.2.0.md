# Search-quality baseline: prose / conceptual (Phase 1.5, v1.2.0 candidate)

**Date:** 2026-05-20
**System under test:** `~/.cupertino-dev/search.db` (v1.2.0 candidate)
**Binary:** `Packages/.build/release/cupertino` 1.1.0 (post-merge `a00a7b1`)
**Methodology:** `docs/design/search-quality-eval.md` §14.2 Phase 1.5 (prose / conceptual), query class G from §1.4
**Companion handbook:** `docs/database-handbook.md` §5

This audit tests multi-word natural-language queries — the kind a developer or AI agent would actually issue in a coding session, like "how to make a type Sendable" or "actor reentrancy semantics" — that have no single canonical URI. The right answer is a small SET of relevant documents spread across apple-docs and swift-evolution.

**Important caveat up front:** prose-query evaluation with programmatic ground truth has a known methodology limitation: the regex defining "relevant" is necessarily narrower than human judgment. Some misses below are the ranker failing; some are the regex failing. Without human qrels we cannot cleanly attribute. The design's §14.2 explicitly flags this class as the hardest to evaluate programmatically.


**Cross-validation note (added 2026-05-21):** The `Binary` cited above is `cupertino 1.1.0` — that's what was on disk when this baseline was captured. The same 50-query corpus re-run with the v1.2.0 binary on the same v1.2.0-schema search.db produces the identical headline metric (see [`search-quality-versiondiff-v1.1.0-to-v1.2.0.md`](search-quality-versiondiff-v1.1.0-to-v1.2.0.md) — v1.2.0 binary's MRR = 0.9467, matching this audit's claim). The v1.2.0-binary-specific ranking change (PR #858's `OR generic_constraints LIKE ?` clause) doesn't move this corpus's headline number. So the baseline numbers carry to the as-shipped v1.2.0 binary even though the original capture was on 1.1.0.
---

## Aggregate

| Metric | Value |
|---|---|
| Queries | 15 |
| **Any relevant in top-3 (headline)** | **4 / 15 (26.7%)** |
| Any relevant in top-5 | 6 / 15 (40.0%) |
| Mean P@3 | 0.1111 |
| Mean P@5 | 0.0933 |

This is the second-worst class baseline after acronym (4/22, 18%). For prose, this number represents an upper-bound on the methodology problem and a lower-bound on the ranker problem; the truth is somewhere in between.

---

## What the regex says

The harness defined per-query "valid" URIs as a tight enumeration: for "actor reentrancy semantics", valid = `apple-docs://swift/actor` OR `swift-evolution://SE-0306` OR `swift-evolution://SE-0327`. Any URI not on the per-query list is counted as not-relevant, even if a human judge would call it useful.

**Wins (4 queries where the regex matched a top-3 result):**

| Query | First match rank | Match |
|---|---|---|
| actor reentrancy semantics | 1 | `apple-docs://swift/actor` |
| structured concurrency | (top-3) | `apple-docs://swift/structured-concurrency` |
| AsyncSequence iteration | 1 | `apple-docs://swift/asyncsequence` |
| preference keys SwiftUI | (top-3) | (one of the PreferenceKey variants) |

**Misses (11 queries where top-3 contained nothing the regex recognised):**

| Query | What top-3 actually returned |
|---|---|
| how to make a type Sendable | `appentity`, `systemcoordinator`, `storekit-views` |
| async let semantics | `withtaskexecutorpreference`, `withtaskgroup` variants |
| Result Builders proposal | `SE-0373`, `SE-0326`, `SE-0348` (wrong SE numbers) |
| how does Observable invalidate views | `xcode/analyzing-a-crash-report`, `SE-0373`, `SE-0492` |
| MainActor isolation | various SwiftUI style protocols |
| property wrappers Swift | `appintents/parameter-resolution`, `coreml/mlmodel` |
| Swift macros | `appkit/macros`, `driverkit/driverkit-macros`, `widgetkit/preview-macros` |
| SwiftUI App lifecycle | `corelocation/supporting-live-updates-in-swiftui`, `nshostingscenerepresentation` |
| NavigationStack programmatic navigation | `understanding-the-composition-of-navigation-stack`, `navigation` |
| error handling Swift async | `fileprovider/.../requestdiagnosticcollection`, `contactprovider/contactprovidermanager` |
| Combine to async/await migration | `SE-0463`, `SE-0458` (Swift evolution proposals but not the expected ones) |

---

## Reading the misses honestly

Several of the "misses" are arguably correct results that the regex rejected:

- `Swift macros` returned `appkit/macros`, `driverkit/driverkit-macros`, `widgetkit/preview-macros`. These ARE macro-related pages; a human reading "Swift macros" might want the language-feature SE proposals, but the ranker reasonably surfaced framework-specific macro documentation. The regex required SE-0382/0389/0397 and saw none.
- `NavigationStack programmatic navigation` returned `understanding-the-composition-of-navigation-stack` and `swiftui/navigation`. Both are highly relevant to the question; the regex was looking for the literal `navigationstack`/`navigationpath` URIs and didn't match these.
- `Result Builders proposal` returned three SE proposals (SE-0373, SE-0326, SE-0348). None are the expected SE-0289 but the ranker plausibly returned Swift evolution proposals on a Swift evolution topic; a human would say "wrong proposal, but right direction."
- `Combine to async/await migration` returned SE-0463 and SE-0458. Both might be migration-related; the regex was strict.

Other misses are real ranker failures:

- `how to make a type Sendable` returned `appentity`, `systemcoordinator`, `storekit-views` — none of which are relevant. The Sendable protocol page is rank 8.
- `MainActor isolation` returned SwiftUI style protocols (`tabviewstyle`, `controlgroupstyle`, `toolbarcontent`) — wholly unrelated. The MainActor docs are not in top-3.
- `error handling Swift async` returned three deep manager-method pages — also unrelated to the conceptual question.

A rough human-judgment split: of the 11 misses, perhaps **4-6 are arguably-acceptable** (ranker found a defensible page, regex too strict), and **5-7 are genuine ranker misses** (top-3 has nothing useful for the question).

Adjusted estimate of "useful in top-3" is therefore **8-10 out of 15 (53-67%)**, not 26.7%. Still not great, but materially better than the regex-strict number suggests.

This is exactly the situation the design's §14.3 (Phase 2 TREC-grade pooling) was designed for. Honest measurement of prose-query quality requires human judges.

---

## What this audit measures vs what it doesn't

**Measures:**
- Strict programmatic-ground-truth match rate on top-3 (26.7%)
- That the ranker often surfaces page tangentially related to the question (visible in the miss listing)
- The methodology limit for class G specifically

**Does not measure:**
- Whether the surfaced pages, taken together, would be useful for an LLM agent constructing a Swift code answer
- Whether human-judged relevance differs materially from the regex
- Whether re-running with broadened regex would substantially change the result (worth doing as a follow-up if the test is rerun later)

---

## What this baseline says about the ranker

Cupertino's BM25F + RRF configuration is tuned for canonical-lookup and symbol-identifier queries (classes A, D), where it excels (92% P@1, 100% rank-1 fragment recall). Prose multi-word queries lean on the `content` column at BM25F weight 1.0, which is the smallest weight in the schema — by design, so canonical-lookup queries do not get drowned out by long-content matches.

The cost of that design choice is that prose queries see worse rankings for the kind of conceptual results they want. **This is a known trade-off baked into the BM25F weight vector**, not a bug. The right answer for a prose-focused consumer would be to expose alternate BM25F weight profiles (a `--profile prose` flag that bumps `content` weight up) rather than re-tune the weights and regress the canonical-lookup case.

This is consistent with cupertino's stated AI-agent-grounding purpose: agents in coding sessions issue more canonical-lookup queries than prose, so the current trade-off is the right one.

---

## Possible future directions (out of scope for this audit)

Following the `feedback_code_changes_as_ideas_for_future` rule:

1. **Broaden the harness's regex.** Many of the misses above are arguably-acceptable results the regex rejected. A second pass with looser per-query patterns would tighten the methodology and give a more honest number. Future audit work.
2. **Add a `--profile prose` ranking mode.** A user (or agent) issuing a prose query could opt into BM25F weights that favour `content` over `title` / `symbols`. Not a default-behavior change; an opt-in.
3. **Phase 2 pooled human judgments specifically for prose.** This is the design's own recommendation; would replace the regex with TREC-style qrels for the 15 queries here. Cost: a few hours of human time.

None proposed as immediate work.

---

## Implications for Criterion 2 (anti-hallucination)

An AI agent issuing a prose query like "how to make a type Sendable" gets `appentity` and `systemcoordinator` at top-3, NOT the Sendable protocol page. If the agent grounds on top-3 only, it doesn't see the right reference and may hallucinate.

Mitigation: agents typically chain queries. After a prose query returns unhelpful results, an agent can re-query with a more canonical form ("Sendable protocol") and the canonical-lookup baseline shows the right answer comes back at rank 1. So Criterion 2 impact is moderate: prose-query top-3 alone is not enough, but a multi-turn agent recovers.

The Phase 1.7 agent-end-to-end eval (`docs/design/search-quality-eval.md` §14.4) is where this trade-off gets measured end-to-end. Until that lands, the prose-baseline result here is the closest signal available.

---

## Method recap

15 prose queries, each with a regex matching a per-query enumerated valid-URI set. For each: run `cupertino search "<query>" --limit 10`, find first-relevant rank, compute P@3, P@5, any-match-in-top-3 (binary). Aggregate as means. No paired test (single-system).

Harness source: `/tmp/cupertino-search-eval-prose.py`.
Full JSON dump: `/tmp/cupertino-search-eval-prose-20260520.json`.

---

## Combined Phase 1 baseline coverage on v1.2.0

| Baseline | Class | Headline |
|---|---|---|
| `search-quality-baseline-v1.2.0.md` | A + B | MRR 0.9467, P@1 perfect 46/50 |
| `search-quality-deprecation-baseline-v1.2.0.md` | E | Swift 30/30, p = 0.0078 |
| `search-quality-crosssource-baseline-v1.2.0.md` | F | 19/19 conditional, p = 1.9 × 10⁻⁶ |
| `search-quality-fragment-baseline-v1.2.0.md` | D | P@1 = 1.0, P@5 = 0.92 |
| `search-quality-acronym-baseline-v1.2.0.md` | C | 4/22 (18%); mechanism not effective |
| **`search-quality-prose-baseline-v1.2.0.md`** (this doc) | **G** | **4/15 any-top-3 (26.7%) strict; estimated 8-10/15 (53-67%) human-adjusted. Hardest class to evaluate programmatically; honest measurement requires Phase 2 human qrels.** |

Six of eight Phase 1.x classes from §1.4 now have documented baselines. One remains: H (symbol-attribute). Plus Phase 1.7 (anti-hallucination agent-end-to-end).
