# Search-quality version diff: v1.1.0 → v1.2.0 (deprecation pairs)

**Date:** 2026-05-21
**Status:** Strong
**Headline:** modern-wins rate 90.00% → 100.00%
**Corpus:** 30 (modern, legacy) Foundation + Swift-stdlib pairs harvested from `docs/audits/search-quality-deprecation-baseline-v1.2.0.md`
**Arm A:** v1.1.0 (brew) — `/opt/homebrew/bin/cupertino` × `/Users/mmj/.cupertino/search.db` (v13, 285,735 docs)
**Arm B:** v1.2.0 (dev) — `/Volumes/Code/DeveloperExt/public/cupertino/Packages/.build/release/cupertino` × `/Users/mmj/.cupertino-dev/search.db` (v18, 352,712 docs)
**Methodology:** `docs/design/search-quality-eval.md` Phase 1.1 (Class C deprecation-aware, paired-comparison mode)
**Harness:** `scripts/eval/search-quality-phase1-extended.py`

For each (query, modern_uri, legacy_uri) triple: run `cupertino search "<query>" --limit 10`, classify the outcome as `modern_wins` (modern rank < legacy rank), `legacy_wins`, `tied`, `modern_only` (only modern in top-10), `legacy_only`, or `both_missing`. The Class C concern is that the ranker should prefer the modern Swift form on every pair; an agent grounded on `cupertino search "URL"` should land on `apple-docs://foundation/url` (Swift struct), not `apple-docs://foundation/nsurl` (legacy ObjC class).

---

## Aggregate

| Outcome | v1.1.0 (brew) | v1.2.0 (dev) | Delta |
|---|---|---|---|
| modern wins | 9 | 11 | +2 |
| modern only (in top-10) | 18 | 19 | +1 |
| **modern preferred (wins + only)** | **27 / 30** | **30 / 30** | **+3** |
| legacy wins | 0 | 0 | +0 |
| legacy only | 0 | 0 | +0 |
| tied | 0 | 0 | +0 |
| both missing | 3 | 0 | -3 |

**Headline:** modern-preferred rate 90.00% → 100.00% (Δ +10.00%).

---

## Per-query transitions

| Transition | Count | Queries |
|---|---|---|
| A loses → B wins (improvement) | 3 | `URL`, `Data`, `Dictionary` |
| A wins → B loses (regression) | 0 | — |
| Both win (concordant +) | 27 | — |
| Both lose (concordant −) | 0 | — |

A zero "regression" column with a positive "improvement" column is the clean-win shape.

---

## Pipeline

```mermaid
flowchart TD
    Q["30 (modern_query, modern_regex, legacy_regex) triples<br/>harvested from search-quality-deprecation-baseline-v1.2.0.md"]:::input
    Q --> H[search-quality-phase1-extended.py]

    BA["Arm A: brew cupertino 1.1.0<br/>+ ~/.cupertino/search.db (schema 13)"]:::arm
    BB["Arm B: dev cupertino 1.2.0<br/>+ ~/.cupertino-dev/search.db (schema 18)"]:::arm
    H -->|"cupertino search 'URL' --limit 10"| BA
    H -->|"cupertino search 'URL' --limit 10"| BB

    BA --> SA["for each pair:<br/>modern_rank (1st match of modern_regex in top-10)<br/>legacy_rank (1st match of legacy_regex)"]
    BB --> SB["for each pair:<br/>modern_rank<br/>legacy_rank"]

    SA --> OA["classify outcome:<br/>modern_wins / legacy_wins / modern_only /<br/>legacy_only / tied / both_missing"]
    SB --> OB["classify outcome:<br/>same six categories"]

    OA --> AGGA["arm A: count modern-preferred = modern_wins + modern_only"]
    OB --> AGGB["arm B: count modern-preferred"]

    AGGA --> PAIR["paired transitions:<br/>a_lose_b_win (improvement)<br/>a_win_b_lose (regression)<br/>both_win / both_lose"]:::stat
    AGGB --> PAIR

    PAIR --> MD["this audit MD<br/>(dashboard glob picks up)"]:::out

    classDef input fill:#0a84ff,stroke:#0040cc,color:#fff
    classDef arm fill:#5856d6,stroke:#3634a3,color:#fff
    classDef stat fill:#ff9500,stroke:#c4730a,color:#fff
    classDef out fill:#34c759,stroke:#1f7a3a,color:#fff
```
