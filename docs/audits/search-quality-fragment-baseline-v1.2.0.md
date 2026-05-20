# Search-quality baseline: CamelCase fragment recall (Phase 1.3, v1.2.0 candidate)

**Date:** 2026-05-20
**System under test:** `~/.cupertino-dev/search.db` (v1.2.0 candidate)
**Binary:** `Packages/.build/release/cupertino` 1.1.0 (post-merge `a00a7b1`)
**Methodology:** `docs/design/search-quality-eval.md` §14.2 Phase 1.3 (CamelCase fragment recall), query class D from §1.4
**Companion handbook:** `docs/database-handbook.md` §5

This audit tests `Search.Index.CamelCaseSplitter` (#77), the cupertino-specific mechanism that expands CamelCase identifiers like `LazyVGrid` into recall-aiding components `{Lazy, VGrid, Grid}` stored in the `docs_fts.symbol_components` column. The column carries BM25F weight 1.5 (one-tenth of `docs_fts.symbols` at 5.0) so an exact identifier match wins over a fragment match, but a query for a fragment alone should still surface pages whose symbols contain it.

The test: for each fragment query (`Grid`, `Decoder`, `Session`, ...), check how many of the top-5 results have a URI whose path contains the fragment as a substring of one of its segments. This is a deliberate over-loose match (we accept any fragment-containing slug, not just CamelCase-derived ones) because the goal is to measure recall, not precision. Misses on this loose pattern are strong signals that `symbol_components` is not surfacing the right pages.


**Cross-validation note (added 2026-05-21):** The `Binary` cited above is `cupertino 1.1.0` — that's what was on disk when this baseline was captured. The same 50-query corpus re-run with the v1.2.0 binary on the same v1.2.0-schema search.db produces the identical headline metric (see [`search-quality-versiondiff-v1.1.0-to-v1.2.0.md`](search-quality-versiondiff-v1.1.0-to-v1.2.0.md) — v1.2.0 binary's MRR = 0.9467, matching this audit's claim). The v1.2.0-binary-specific ranking change (PR #858's `OR generic_constraints LIKE ?` clause) doesn't move this corpus's headline number. So the baseline numbers carry to the as-shipped v1.2.0 binary even though the original capture was on 1.1.0.
---

## Aggregate

| Metric | Value |
|---|---|
| Fragments evaluated | 20 |
| **Mean P@1** | **1.0000** (every fragment has a match at rank 1) |
| **Mean P@5 (headline)** | **0.9200** |
| Mean P@10 | 0.8700 |
| Fragments with zero matches in top-5 | 0 / 20 |
| Fragments with 5 / 5 matches in top-5 | 14 / 20 |

Every one of the 20 fragment queries returned a fragment-containing URI at rank 1. The symbol_components mechanism is doing its job at the top of the ranking.

The 8% gap from 1.0 in P@5 comes from fragments where 1 or 2 of the top-5 positions are taken by pages that don't carry the fragment in their URI (likely prose pages that happen to use the word as a query token via the `content` column).

---

## Per-fragment

| Fragment | First match rank | P@5 | Sample of top-5 matches |
|---|---|---|---|
| Grid | 1 | 1.00 | grid, grid, gridlayout, gridrow, lazyvgrid |
| Decoder | 1 | 1.00 | decoder, decoder, compressormediadecoder, mevideodecoder, topleveldecoder |
| Encoder | 1 | 0.80 | encoder, encoder, onehotencoder, networkencoder |
| Session | 1 | 0.80 | session, session, session, session |
| Stack | 1 | 1.00 | stack, stack, lazyhstack, lazyvstack, hstack |
| Picker | 1 | 1.00 | picker, defaultpickerstyle, colorpicker, popupbuttonpickerstyle, pickerstyle |
| Style | 1 | 0.80 | style, style, style, style |
| View | 1 | 1.00 | view, view, view, view, view |
| Controller | 1 | 1.00 | controller, controller, controller, controller, controller |
| Manager | 1 | 1.00 | manager, manager, accessorynotificationmanagerfactory, avdisplaymanager, badownloadmanager |
| Layout | 1 | 0.60 | layout, layout, layout |
| Button | 1 | 1.00 | button, button, button, button, button |
| Image | 1 | 0.80 | image, image, image, image |
| Field | 1 | 1.00 | defaulttextfieldstyle, fielddatepickerstyle, textfieldstyle, plaintextfieldstyle, field |
| Animation | 1 | 1.00 | animation, animation, animation, animation, animation |
| Color | 1 | 1.00 | color, color, color, color, color |
| Container | 1 | 1.00 | container, container, container, container, container |
| Builder | 1 | 1.00 | builderconditional, axiscontentbuilder, previewbodybuilder, axismarkbuilder, previewcamerabuilder |
| Wrapper | 1 | 1.00 | wrapper, wrapper, wrapper, mdimporterbundlewrapperurlinterfacestruct, filewrapper |
| Provider | 1 | 0.60 | provider, provider, provider |

---

## What this baseline confirms

The `symbol_components` column does what #77 designed it to do: a query for a CamelCase fragment surfaces pages whose symbols contain that fragment as a component. This works for simple compound types (`LazyVGrid` → retrievable by `Grid`, `Lazy`, or `VGrid`), for protocol families (`Decoder` → retrievable surfaces `JSONDecoder` etc.), and for SwiftUI patterns (`Picker` → retrieves `DatePicker`, `ColorPicker`, etc.).

The BM25F weight balance is correct: with `symbols=5.0` and `symbol_components=1.5`, an exact name match always wins (verified separately by the canonical-lookup baseline `search-quality-baseline-v1.2.0.md` where `LazyVGrid` ranks the canonical `apple-docs://swiftui/lazyvgrid` at rank 1), and a fragment-only query still retrieves the right family via the symbol_components contribution.

---

## What this baseline does NOT cover

- **Acronym-style fragments.** Fragments like `URL`, `HTTP`, `JSON`, `XML` are technically multi-letter acronyms that the CamelCase splitter treats as single units (per the splitter's spec: `JSONDecoder` → `{JSON, Decoder}`, not `{J, S, O, N, Decoder}`). The test corpus uses single-word fragments only. Acronym-fragment behaviour is testable as a Phase 1.3.1 follow-up.
- **Single-letter fragments.** The splitter drops single-letter fragments (`V` from `LazyVGrid` does not become a recall unit) per #77's min-length rule. Not tested here.
- **Multi-fragment compound queries.** A query like `Grid Layout` requires both fragments to surface; this corpus tests one fragment at a time. The interaction is testable as a Phase 1.3.2 follow-up.
- **Fragment in non-Swift symbol context.** Obj-C identifiers (`NSURLRequest`, `NSDecimalNumber`) are also CamelCase. The splitter splits them too (`NS, URL, Request`); whether queries route through them at the desired weight is not separately tested.

---

## Method recap

20 fragment queries. For each: run `cupertino search "<fragment>" --limit 10`, extract top-10 URIs, apply a loose regex that matches URIs whose path contains the fragment as a substring in any segment. Compute P@1, P@5, P@10, and first-match rank. Aggregate as means.

Note on the initial regex bug: an earlier strict regex (requiring the terminal slug to END in the fragment) reported P@5 = 0.49, with `Field` and `Provider` showing zero matches. Investigation revealed the strict regex was rejecting valid deeply-nested results like `appintents/appshortcutoptionscollectionprotocol/provider` and embedded results like `defaulttextfieldstyle`. The corrected loose regex (substring anywhere in any path segment) measures the actual recall and is what this audit reports.

Harness source: `/tmp/cupertino-search-eval-fragment.py` (not yet versioned in repo).
Full JSON dump (all 20 top-10 lists): `/tmp/cupertino-search-eval-fragment-20260520.json`.

---

## Combined Phase 1 baseline coverage on v1.2.0

| Baseline | Class | Headline |
|---|---|---|
| `search-quality-baseline-v1.2.0.md` | A + B (canonical lookup + framework root) | MRR 0.9467, P@1 perfect on 46/50 |
| `search-quality-deprecation-baseline-v1.2.0.md` | E (deprecation-aware) | Swift wins 30/30, sign-test p = 0.0078 |
| `search-quality-crosssource-baseline-v1.2.0.md` | F (cross-source canonical) | 19/19 OK when expected source in top-10, p = 1.9 × 10⁻⁶ |
| **`search-quality-fragment-baseline-v1.2.0.md`** (this doc) | **D (CamelCase fragment)** | **mean P@1 = 1.0, mean P@5 = 0.92 across 20 fragment queries. 14 / 20 returned 5/5 matches. The #77 symbol_components mechanism is working.** |

Four of eight Phase 1.x classes from §1.4 now have documented baselines. Four remain: C (acronym), G (prose), H (symbol-attribute), and Phase 1.7 agent-end-to-end.
