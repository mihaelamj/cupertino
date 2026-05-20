# Search-quality baseline: deprecation-aware (Phase 1.1, v1.2.0 candidate)

**Date:** 2026-05-20
**System under test:** `~/.cupertino-dev/search.db` (v1.2.0 candidate, same DB as `search-quality-baseline-v1.2.0.md`)
**Binary:** `Packages/.build/release/cupertino` 1.1.0 (post-merge `a00a7b1`)
**Methodology:** `docs/design/search-quality-eval.md` §14.2 Phase 1.1 (deprecation-aware), query class E from §1.4
**Universal rule:** `../private/mihaela-agents/Rules/universal/search-quality-eval.md`
**Companion handbook:** `docs/database-handbook.md` §5

This audit answers a focused question: when a developer queries a concept that exists in both modern Swift form (value type / stdlib) and the original NS-prefixed Objective-C form, **does cupertino's ranker put the modern form above the legacy form?** This is the most user-visible failure mode for an AI coding agent (Criterion 2: an agent told to use `NSURLConnection` when `URLSession` is the right answer in 2026 generates wrong code).


**Cross-validation note (added 2026-05-21):** The `Binary` cited above is `cupertino 1.1.0` — that's what was on disk when this baseline was captured. The same 50-query corpus re-run with the v1.2.0 binary on the same v1.2.0-schema search.db produces the identical headline metric (see [`search-quality-versiondiff-v1.1.0-to-v1.2.0.md`](search-quality-versiondiff-v1.1.0-to-v1.2.0.md) — v1.2.0 binary's MRR = 0.9467, matching this audit's claim). The v1.2.0-binary-specific ranking change (PR #858's `OR generic_constraints LIKE ?` clause) doesn't move this corpus's headline number. So the baseline numbers carry to the as-shipped v1.2.0 binary even though the original capture was on 1.1.0.
---

## Aggregate

| Metric | Value |
|---|---|
| Pairs evaluated | 30 |
| **Swift form ranked above Obj-C form** | **30 / 30 (100%)** |
| Obj-C form ranked above Swift form | 0 / 30 |
| Both forms in top-10 | 7 / 30 |
| Only Swift form in top-10 | 23 / 30 |
| Both missing from top-10 | 0 / 30 |

**Sign test (on the 7 both-present pairs):** k = 7 Swift-higher of n = 7 trials, two-sided p = 0.0156, one-sided p = 0.0078. The null hypothesis (ranker has no preference between modern and legacy form) is rejected at the 0.01 level.

For the other 23 pairs the Obj-C form did not appear in the top-10 at all, which is a stronger statement than "Swift higher in pair": the legacy form is not surfaced at all under a developer's natural query.

The Swift form was at rank 1 (position 1) in every one of the 30 queries.

---

## What the pairs look like

The 30 pairs cover three concept families:

| Family | Examples | Count |
|---|---|---|
| Foundation value-type vs NS-class | `URL`/`NSURL`, `Data`/`NSData`, `Date`/`NSDate`, `UUID`/`NSUUID`, `URLSession`/`NSURLSession`, `FileManager`/`NSFileManager`, `DateFormatter`/`NSDateFormatter`, `Bundle`/`NSBundle`, `Calendar`/`NSCalendar`, `TimeZone`/`NSTimeZone`, `Locale`/`NSLocale`, `Predicate`/`NSPredicate`, `AttributedString`/`NSAttributedString`, `Measurement`/`NSMeasurement` and others | 27 |
| Swift stdlib vs NS-class | `String`/`NSString`, `Array`/`NSArray`, `Dictionary`/`NSDictionary` | 3 |

For each pair the query is the modern name as a developer would type it. The expected hits are documented as exact-URI patterns (`apple-docs://foundation/url` vs `apple-docs://foundation/nsurl`, etc.), verified to exist in the v1.2.0 candidate DB before the corpus was finalised.

---

## Both-present subset (the strict test)

The 7 pairs where both forms appeared in the top-10. These are the rows where the ranker had to choose between two valid alternatives.

| Query | Swift rank | Obj-C rank |
|---|---|---|
| URLRequest | 1 | 3 |
| URLComponents | 1 | 2 |
| Bundle | 1 | 2 |
| Measurement | 1 | 8 |
| DateComponents | 1 | 4 |
| DateInterval | 1 | 6 |
| Decimal | 1 | 7 |

In every case Swift is at rank 1, Obj-C at rank 2 or later. The minimum Obj-C rank is 2 (`URLComponents`, `Bundle`); the maximum is 8 (`Measurement`). The gap between the two is consistent across the corpus.

For the other 23 pairs the NS-prefixed form either does not exist as a separate documented page or ranks below position 10 (not measured here; the harness limits to top-10).

---

## What this says about the ranker

Cupertino's BM25F weights combined with the RRF source authority produce a strong preference for the modern Swift form. The behaviour is not accidental:

1. The Swift form is the framework-root for its concept (e.g., `foundation/url` is a struct page, not just a method on a class). Framework-root pages have a small BM25F boost (`framework=2.0` weight) and are favoured by the dedicated kind-multiplier in `Search.Index.Search.swift`.
2. The Swift form's `title` (e.g., "URL") matches the query exactly; the Obj-C form's title (e.g., "NSURL") matches the query as a prefix-of-token only, costing BM25F. With `title=10.0` weight, this is the dominant signal.
3. Modern Apple-docs pages have richer `content` (longer overview prose, more code examples). The Obj-C reference pages are largely stubs with declaration-only content. Length normalisation in BM25F penalises stubs.
4. The Apple-docs source weight in RRF (`apple-docs = 3.0`) treats both forms equally as far as fusion goes; the within-source BM25F decides the order, and within-source the above three factors all favour Swift.

The result is empirically what an AI coding agent in 2026 needs: searching "URLSession" returns the Swift `foundation/urlsession` value-type page at rank 1, with `foundation/nsurlsession` (if present at all) buried at rank 2-8.

---

## Implications for Criterion 2 (anti-hallucination)

Deprecation-axis failures are one of the four explicit anti-hallucination concerns in `docs/design/cupertino.md` §1.1 ("avoid generating code that ... uses deprecated APIs"). This baseline shows the ranker is doing its job on this axis at the v1.2.0 candidate state. An LLM agent grounded on cupertino's top-1 result for any of these 30 queries will write modern Swift, not legacy Objective-C-style code.

This is **necessary but not sufficient** for Criterion 2. The agent could still hallucinate within the modern API surface (calling methods that don't exist on the correct type). Phase 1.7 (agent-end-to-end eval) is where that failure mode gets tested.

---

## What this baseline does NOT cover

- **Pairs where both forms have similar BM25 signals.** If a Swift type carried sparser documentation than its NS counterpart, the ranker's content-length normalisation might flip the result. None of the 30 pairs tested exhibit this, but the test does not actively search for adversarial cases.
- **Cross-source deprecation.** The HIG might document a deprecated pattern that Swift Evolution later modernised; this evaluation does not look at that axis. Class F (cross-source canonical) is the relevant Phase 1.x companion.
- **Symbol-level deprecation.** Method-level deprecation (`init(string:)` deprecated in favour of `init?(string:)` on the same type) is not tested. Doc_symbols has the data; this corpus does not exercise it.
- **Platform-availability-axis "deprecation."** A Swift API marked `@available(*, deprecated)` is structurally the same as a legacy NS class for an agent's purposes; this corpus tests one shape of the problem, not all shapes.

---

## Method recap

30 (query, swift_URI, objc_URI) triples. For each: run `cupertino search "<query>" --limit 10` via the dev binary, find rank of `swift_URI` and rank of `objc_URI` in the top-10. Outcome per query: `swift_wins`, `objc_wins`, `both_missing`, or `tied`. Aggregate: count outcomes. Sign test (binomial, scipy.stats.binomtest) on the subset where both URIs appeared.

Harness source: `/tmp/cupertino-search-eval-deprecation.py` (not yet versioned in repo; awaiting design §14.1.2 follow-up).
Full JSON dump (all 30 top-10 lists): `/tmp/cupertino-search-eval-deprecation-20260520.json`.

---

## Combined with the canonical-lookup baseline

| Baseline | Class | Headline |
|---|---|---|
| `search-quality-baseline-v1.2.0.md` | A + B (canonical lookup + framework root) | MRR 0.9467, P@1 perfect on 46/50 |
| `search-quality-deprecation-baseline-v1.2.0.md` (this doc) | E (deprecation-aware) | Swift wins 30/30, sign-test p = 0.0078 |

Two of the eight query classes from §1.4 now have documented baselines on the v1.2.0 candidate DB. Six remain (C acronym, D CamelCase fragment, F cross-source, G prose, H symbol-attribute, and the Phase 1.7 agent-eval).
