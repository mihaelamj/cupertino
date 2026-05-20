# Search-quality baseline: acronym / synonym recall (Phase 1.4, v1.2.0 candidate)

**Date:** 2026-05-20
**System under test:** `~/.cupertino-dev/search.db` (v1.2.0 candidate)
**Binary:** `Packages/.build/release/cupertino` 1.1.0 (post-merge `a00a7b1`)
**Methodology:** `docs/design/search-quality-eval.md` §14.2 Phase 1.4 (acronym / synonym), query class C from §1.4
**Companion handbook:** `docs/database-handbook.md` §5

This audit tests `framework_aliases.synonyms` — the cupertino-specific table that maps colloquial / abbreviated names to canonical framework slugs (`nfc → corenfc`, `wifi → corewlan`, `bluetooth → corebluetooth`, `ml → coreml`, etc.). The expectation: when a developer types the synonym alone as a query, cupertino should route to the canonical framework root via the synonyms table.

The test: 22 (query, expected_canonical_URI) pairs drawn from the `framework_aliases.synonyms` rows present in the v1.2.0 candidate DB. Generic English words that are also synonyms (`data`, `text`) were excluded because their accidental-token-match would dominate regardless of the synonyms mechanism.


**Cross-validation note (added 2026-05-21):** The `Binary` cited above is `cupertino 1.1.0` — that's what was on disk when this baseline was captured. The same 50-query corpus re-run with the v1.2.0 binary on the same v1.2.0-schema search.db produces the identical headline metric (see [`search-quality-versiondiff-v1.1.0-to-v1.2.0.md`](search-quality-versiondiff-v1.1.0-to-v1.2.0.md) — v1.2.0 binary's MRR = 0.9467, matching this audit's claim). The v1.2.0-binary-specific ranking change (PR #858's `OR generic_constraints LIKE ?` clause) doesn't move this corpus's headline number. So the baseline numbers carry to the as-shipped v1.2.0 binary even though the original capture was on 1.1.0.
---

## Aggregate

| Metric | Value |
|---|---|
| Synonyms tested | 22 |
| **Canonical framework at top-1** | **4 / 22 (18.2%)** |
| Canonical in top-5 | 11 / 22 |
| Canonical in top-10 | 13 / 22 |
| Canonical missing from top-10 | 9 / 22 |
| MRR | 0.2562 |

**Binomial test (top-1 == canonical vs chance 0.5):** k = 4 of n = 22, one-sided p = **0.9996**. The null hypothesis (synonyms-mechanism has no effect beyond chance) is not rejected; if anything, the data is consistent with the synonyms-mechanism actively producing worse results than random for top-1 retrieval.

**Compare to the other class baselines on the same DB:**

| Class | Top-1 hit rate |
|---|---|
| A canonical lookup (`search-quality-baseline`) | 46/50 (92%) |
| E deprecation-aware (`search-quality-deprecation`) | 30/30 (100%) |
| F cross-source canonical (`search-quality-crosssource`) | 19/19 conditional (100%) |
| D CamelCase fragment (`search-quality-fragment`) | 20/20 (100%) at any-match |
| **C acronym / synonym (this doc)** | **4/22 (18%)** |

This is the worst-performing class baseline by a wide margin.

---

## The 4 wins

| Query | Top-1 | Why this works |
|---|---|---|
| `wlan` | `apple-docs://corewlan` (rank 1) | `wlan` appears in CoreWLAN's framework identifier directly; FTS5 finds it without needing the synonyms table |
| `mpsgraph` | `apple-docs://metalperformanceshadersgraph` (rank 1) | The synonym `mpsgraph` is a partial-token-match of the framework's identifier; the long compound name's BM25F favours the exact-prefix match |
| `sprite` | `apple-docs://spritekit` (rank 1) | `sprite` is part of `spritekit`; literal substring match |
| `location` | `apple-docs://corelocation` (rank 1) | `location` is part of `corelocation`; literal substring match |

All four wins are explainable by literal-substring or prefix-token matching, not by synonym lookup. The synonyms table may not be contributing to these results at all.

## The 18 misses

| Query | Expected | Actual top-1 | First match rank |
|---|---|---|---|
| `NFC` | corenfc | `apple-docs://authenticationservices/asauthorizationsecuritykeypublickeycredentialdescriptor/transport/nfc` | 3 |
| `wifi` | corewlan | `apple-docs://devicemanagement/wifi` | — |
| `bluetooth` | corebluetooth | `apple-docs://authenticationservices/.../transport/bluetooth` | 4 |
| `telephony` | coretelephony | `apple-docs://hiddriverkit/telephony-enum` | 2 |
| `imageprocessing` | coreimage | (no hit) | — |
| `graphics` | coregraphics | `apple-docs://virtualization/graphics` | — |
| `shareplay` | groupactivities | `apple-docs://uikit/uiactivity/activitytype-swift.struct/shareplay` | 5 |
| `scene` | scenekit | `apple-docs://swiftui/scene` | 7 |
| `video` | corevideo | `apple-docs://applenewsformat/video` | — |
| `av` | avfoundation | `apple-docs://avrouting` | 2 |
| `ml` | coreml | `apple-docs://mlcompute` | 4 |
| `machinelearning` | coreml | `apple-docs://metal/mtlstages/machinelearning` | — |
| `journaling` | journalingsuggestions | `apple-docs://appintents/app-intent-domain-journaling` | 2 |
| `media` | coremedia | `apple-docs://sirikit/media` | — |
| `motion` | coremotion | `apple-docs://gamecontroller/gccontroller/motion` | 6 |
| `spotlight` | corespotlight | `apple-docs://foundation/spotlight` | — |
| `haptics` | corehaptics | `apple-docs://gamecontroller/gccontroller/haptics` | 7 |
| `audio` | coreaudio | `apple-docs://virtualization/audio` | — |

Every miss is a literal-token match against a deeper path that happens to contain the query word. The canonical CoreX framework is either far down the ranking (rank 2-7) or absent from the top-10 entirely.

---

## What this baseline says

The `framework_aliases` table exists in the schema and contains 22 rows with a populated `synonyms` column (verified directly via `SELECT identifier, synonyms FROM framework_aliases WHERE synonyms IS NOT NULL`). The DATA is there.

But the ranking layer does not appear to consult `framework_aliases.synonyms` when scoring matches against a bare acronym query. The query `NFC` finds the literal-token `nfc` in `authenticationservices/.../transport/nfc` and ranks it at position 1 by BM25F because that page's `content` happens to contain the token in a deep authentication-flow paragraph. The `corenfc` framework root, which the synonyms table says is the canonical answer for `nfc`, is at rank 3 — likely retrieved via the framework-identifier-substring path, not the synonyms path.

This is **not necessarily a bug.** The synonyms table may be intentionally consulted only by `--framework <slug>` resolution (mapping `--framework nfc` to `corenfc` for explicit filtering), not by free-text query ranking. The code paths to verify are:

- `Search.Index.SearchByAttribute` for filter-time use
- `Search.Index.Search.swift` for query-time use
- `Search.Index.CountsAndAliases.swift` for alias-management
- `Search.SmartQuery` / `Search.CandidateFetcher` for cross-source synonym handling

A code reading would clarify whether the synonyms are wired into BM25F scoring at all, or only into framework-name normalisation at filter time.

---

## Possible future directions (out of scope for this audit)

Following the `feedback_code_changes_as_ideas_for_future` rule, three candidate paths, in increasing complexity:

1. **Boost canonical framework root in the rewrite path.** When a bare query (no `--framework`) matches a `framework_aliases.synonyms` entry, append the canonical framework slug to the query as an OR clause: `nfc OR corenfc`. This should pull the canonical framework root up. Small surgical change in the SmartQuery layer.

2. **Per-source authority boost when the query matches a synonym.** When the query matches a synonyms entry, give the matching framework a temporary RRF source-weight bonus. Larger change but follows the existing source-weight pattern.

3. **Document synonym usage in the CLI help.** The current `cupertino search` help doesn't mention that `--framework` arguments accept synonyms. If the synonyms are filter-only, this should be made discoverable so users know to type `--framework nfc` rather than expecting bare-query synonym routing.

None is proposed as immediate work. The baseline exists so that any future change to the synonyms mechanism is measured against this 18% top-1 baseline as the regression starting point.

---

## Implications for Criterion 2 (anti-hallucination)

For the AI agent consumer: if the agent issues a bare `NFC` query expecting the CoreNFC framework reference, it gets an authentication-services deep page instead. The agent that grounds on top-1 will be looking at a transport-property documentation page rather than the framework introduction, which gives the agent the wrong context for generating CoreNFC API calls.

**However**, this is partially mitigated by the way agents typically construct queries: an agent looking for CoreNFC will more likely issue `CoreNFC` or `Core NFC` (the full framework name) rather than `NFC` alone. The canonical-lookup baseline already showed `CoreNFC` likely ranks the framework root at top-1.

The acronym path is more relevant for a HUMAN consumer typing `NFC` interactively. For the agent consumer, the impact is bounded.

---

## Method recap

22 (synonym, canonical_URI) pairs, all drawn from `framework_aliases.synonyms` rows in the v1.2.0 candidate DB (excluding `data` and `text` as too-generic). For each: run `cupertino search "<synonym>" --limit 10`, find rank of the canonical framework URI. Aggregate: count top-1 hits, in-top-5, in-top-10, MRR. Binomial test on top-1 hit rate vs chance.

Harness source: `/tmp/cupertino-search-eval-acronym.py` (not yet versioned in repo).
Full JSON dump: `/tmp/cupertino-search-eval-acronym-20260520.json`.

---

## Combined Phase 1 baseline coverage on v1.2.0

| Baseline | Class | Headline |
|---|---|---|
| `search-quality-baseline-v1.2.0.md` | A + B (canonical lookup, framework root) | MRR 0.9467, P@1 perfect on 46/50 |
| `search-quality-deprecation-baseline-v1.2.0.md` | E (deprecation-aware) | Swift wins 30/30, p = 0.0078 |
| `search-quality-crosssource-baseline-v1.2.0.md` | F (cross-source canonical) | 19/19 conditional, p = 1.9 × 10⁻⁶ |
| `search-quality-fragment-baseline-v1.2.0.md` | D (CamelCase fragment) | P@1 = 1.0, P@5 = 0.92 |
| **`search-quality-acronym-baseline-v1.2.0.md`** (this doc) | **C (acronym / synonym)** | **4/22 top-1 (18%). framework_aliases.synonyms exists but does not appear to route bare acronym queries to canonical framework. Worst-performing class.** |

Five of eight Phase 1.x classes from §1.4 now have documented baselines. Three remain: G (prose), H (symbol-attribute), Phase 1.7 (anti-hallucination agent-end-to-end).
