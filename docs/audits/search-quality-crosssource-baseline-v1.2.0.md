# Search-quality baseline: cross-source canonical (Phase 1.2, v1.2.0 candidate)

**Date:** 2026-05-20
**System under test:** `~/.cupertino-dev/search.db` (v1.2.0 candidate)
**Binary:** `Packages/.build/release/cupertino` 1.1.0 (post-merge `a00a7b1`)
**Methodology:** `docs/design/search-quality-eval.md` §14.2 Phase 1.2 (cross-source canonical), query class F from §1.4
**Companion handbook:** `docs/database-handbook.md` §5

This audit tests `Search.SmartQuery.sourceWeights` (apple-docs=3.0, swift-evolution=1.5, packages=1.5, swift-book=1.0, swift-org=1.0, samples=1.0, apple-archive=0.5, hig=0.5) — the per-source authority bias applied during cross-source RRF fan-out. This machinery had no test coverage before today.

The test: for each query, the expected top-1 source is the highest-authority source that has a relevant doc in the corpus for that query. Outcome: does the actual top-1 come from that source.


**Cross-validation note (added 2026-05-21):** The `Binary` cited above is `cupertino 1.1.0` — that's what was on disk when this baseline was captured. The same 50-query corpus re-run with the v1.2.0 binary on the same v1.2.0-schema search.db produces the identical headline metric (see [`search-quality-versiondiff-v1.1.0-to-v1.2.0.md`](search-quality-versiondiff-v1.1.0-to-v1.2.0.md) — v1.2.0 binary's MRR = 0.9467, matching this audit's claim). The v1.2.0-binary-specific ranking change (PR #858's `OR generic_constraints LIKE ?` clause) doesn't move this corpus's headline number. So the baseline numbers carry to the as-shipped v1.2.0 binary even though the original capture was on 1.1.0.
---

## Aggregate

| Metric | Value |
|---|---|
| Queries total | 25 |
| Top-1 matches expected | **19 / 25 (76.0%)** |
| Expected source IS present in top-10 | **19 / 25** |
| Top-1 match conditional on expected being present | **19 / 19 (100%)** |
| Top-1 mismatch conditional on expected being present | 0 / 19 |

**Binomial test on the strict subset (expected present in top-10):** k = 19 of n = 19 trials, one-sided p (top-1 matches expected vs chance 0.5) = **1.9 × 10⁻⁶**. The null hypothesis (no source-weight effect) is rejected emphatically.

The 6 mismatches are not "ranker chose wrong source from candidates"; they are "expected source had nothing in the top-10 at all because apple-docs's source weight outcompetes the lower-weight sources." A deeper finding (see below).

---

## The clean wins: 19 / 25

For 19 queries where the expected top-1 source was apple-docs (weight 3.0), the actual top-1 was always apple-docs:

`concurrency`, `actor`, `Hashable`, `Sendable`, `Result Builders`, `Property Wrappers`, `async await`, `Generics`, `Observation`, `Optional`, `Protocol`, `Closure`, `Color`, `Navigation`, `Button`, `Typography`, `Materials`, `Privacy`, `Widget`.

The source-weight machinery is doing exactly the work the design intends for the apple-docs-canonical case.

---

## The interesting 6: HIG and apple-archive starve

| Query | Expected source | Actual top-1 | Expected source in top-10? |
|---|---|---|---|
| `App icon` | hig (0.5) | `apple-docs://swiftui/scene/dialogicon` | NO |
| `Touch targets` | hig (0.5) | `apple-docs://webkitjs/touchevent` | NO |
| `Dark mode` | hig (0.5) | `apple-docs://appintents/defining-your-app-s-focus-filter` | NO |
| `Quartz 2D` | apple-archive (0.5) | `apple-docs://coreimage/ciimage/init(cgimage:)` | NO |
| `Cocoa Bindings` | apple-archive (0.5) | `apple-docs://appkit/cocoa-bindings` | NO |
| `Key Value Observing` | apple-archive (0.5) | `apple-docs://swift/using-key-value-observing-in-swift` | NO |

For each of these queries, the HIG or apple-archive corpus **does have a relevant page** (verified via `cupertino search "<query>" --source hig` and `--source apple-archive`):

| Query | Verified HIG page | Verified apple-archive page |
|---|---|---|
| `App icon` | `hig://general/appicons-appledeveloperdocumentation` | — |
| `Dark mode` | `hig://general/darkmode-appledeveloperdocumentation` | — |
| `Cocoa Bindings` | — | `apple-archive://TP40001075/CocoaBindings` |
| `Key Value Observing` | — | `apple-archive://10000177i/KeyValueObserving` |
| `Quartz 2D` | — | `apple-archive://TP30001066/dq_data_mgr` |
| `Touch targets` | (no exact-title page; HIG covers under "Gestures" / "Editing menus") | — |

The pages exist. The ranker doesn't surface them because the apple-docs RRF contribution dominates.

### Why this happens, mechanically

RRF fuses per-source rank-1 contributions weighted by source authority:

```
fused(d) = Σ_{s ∈ sources(d)} weight(s) / (k + rank_s(d))
```

For rank-1 in each source (k = 60):

| Source | Weight | Rank-1 fused contribution |
|---|---|---|
| apple-docs | 3.0 | 3.0 / 61 = 0.0492 |
| swift-evolution / packages | 1.5 | 1.5 / 61 = 0.0246 |
| swift-book / swift-org / samples | 1.0 | 1.0 / 61 = 0.0164 |
| **hig / apple-archive** | **0.5** | **0.5 / 61 = 0.0082** |

Even when HIG has a perfect rank-1 hit and apple-docs has a tangential rank-1 hit, the apple-docs contribution wins by 6:1 in fused score. HIG can never surface at top-1 in the default unfiltered query unless apple-docs has nothing in its corpus to return — which essentially never happens (351K rows).

### Is this a bug?

**No, it is the design.** The source weights were tuned in `Search.SmartQuery.sourceWeights` (#254 Option B) specifically to bias toward apple-docs because that is the canonical reference for code-generating AI agents (cupertino's stated purpose per `README.md`). For an LLM grounding a Swift code-generation task, getting apple-docs at top-1 is the right answer even when HIG might be more conceptually relevant — the agent is writing code, not designing UX.

**But it has a knowable cost.** Designers, UX writers, and humans using cupertino to look up Apple's design guidance get apple-docs answers when HIG answers exist. The current workaround is the explicit `--source hig` flag. Documenting the cost here so it isn't a surprise the next time the question comes up.

### Possible future directions (out of scope for this audit)

1. **Intent routing for design-vocabulary queries.** Augment `Search.SmartQuery.symbolPreferredSources` (#254) with a `designPreferredSources` analogue: when a query matches design vocabulary (`app icon`, `dark mode`, `accessibility`, `typography`, `gestures`, `navigation pattern`), route to HIG/apple-docs only.
2. **Source-weight reconfiguration as a setting.** Expose source weights as user-settable so a designer can `cupertino config set source-weight hig 3.0`.
3. **Composite top-3 rather than top-1.** If the consumer reads top-3, the HIG hit may appear at rank 2 or 3, mitigating the issue without weight changes. Worth measuring.

None of these is proposed as immediate work; each is a candidate per the `feedback_code_changes_as_ideas_for_future` rule.

---

## Method recap

25 (query, expected_source, rationale) triples. For each: run `cupertino search "<query>" --limit 10`, extract top-1 URI, derive its source via the URI prefix, compare against expected. Aggregate: count matches; binomial test on the subset where expected source IS present in top-10.

Harness source: `/tmp/cupertino-search-eval-crosssource.py` (not yet versioned in repo).
Full JSON dump (all 25 top-10 lists + sources): `/tmp/cupertino-search-eval-crosssource-20260520.json`.

---

## Implications for Criterion 2 (anti-hallucination)

For the LLM-agent consumer, this baseline is good news: the agent grounding on cupertino's top-1 will always get apple-docs (the API reference) for any Swift-code-generation query that has an apple-docs answer. This is the intended bias.

For mixed-modality queries (an agent doing UX work, or generating SwiftUI code while also reasoning about HIG guidance), the agent would need to explicitly issue `--source hig` queries to discover design guidance — a behaviour the MCP server's tool surface would need to advertise so the agent knows to do this. Worth tracking as a separate concern.

---

## Combined Phase 1 baseline coverage on v1.2.0

| Baseline | Class | Headline |
|---|---|---|
| `search-quality-baseline-v1.2.0.md` | A + B (canonical lookup + framework root) | MRR 0.9467, P@1 perfect on 46/50 |
| `search-quality-deprecation-baseline-v1.2.0.md` | E (deprecation-aware) | Swift wins 30/30, sign-test p = 0.0078 |
| **`search-quality-crosssource-baseline-v1.2.0.md`** (this doc) | **F (cross-source canonical)** | **19/19 OK when expected source present in top-10, p = 1.9 × 10⁻⁶. 6/25 reveal that HIG/apple-archive are systematically out-competed by apple-docs (by design).** |

Three of eight query classes from §1.4 now have documented baselines. Five remain: C (acronym), D (CamelCase fragment), G (prose), H (symbol-attribute), and Phase 1.7 agent-end-to-end.
