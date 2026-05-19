# Cupertino fun facts

A casual collection of things we noticed while building cupertino that aren't quite incidents (those go in `docs/postmortems/`) and aren't quite design decisions (those go in `docs/design/`) — but are interesting enough to keep around.

---

## 2026-05-19: `cupertino save` indexing throughput is near-quadratic

While building a 10% mini-corpus to lock the #779 regression, c2 ran three end-to-end Apple-docs indexing measurements at different corpus sizes on the same Studio with the same binary:

| Corpus | Docs indexed | Wall time | Throughput |
|---|---|---|---|
| 4.5% mini | 18,844 | 2m18s | **137 docs/s** |
| 10% mini | 41,565 | 9m01s | **77 docs/s** |
| 100% prod | ~351,500 | ~11h | **~8.7 docs/s** |

A power-law curve fit across the three points lands at `T ∝ N^1.9` — near-quadratic, not linear, not logarithmic.

**Why it's a fun fact and not just a number:**

`docs/PRINCIPLES.md` §5 ("10× headroom") commits to:

> Per-row work at the door is `O(log N)` or `O(1)` against the URI index. No `O(N)` scans during normal import.

The empirical N^1.9 is loudly inconsistent with that goal. Something downstream of the door — almost certainly SQLite index maintenance on a non-incrementally-built FTS5 table, or cross-framework relation walks during AST extraction — is doing work proportional to N per insert. At small N the constant factor wins; at production N it dominates.

The 10× design target is 4M docs. At the current curve that extrapolates to roughly **10 days** of indexing for the 10× corpus, vs the ~4.6 days a linear projection (11h × 10) would predict. The principle is violated; the size of the gap shows up clearly only when you sample three points across two decades of N.

**Where to fix when we get to it:**

Probably one of:
- FTS5 table bulk-load vs incremental insert (build → reindex pattern shaves a large multiplicative factor)
- `INSERT OR REPLACE` cost on the dedup hot path (an `ON CONFLICT DO NOTHING` micro-optimization)
- AST extractor's symbol-relation walks if they're touching previously-indexed rows for each new doc

None of which is in scope for the #779 fix. Filed as a fun fact pending a real perf-investigation issue.

**Source data:** validation runs on the `feat/779-mini-corpus-setup` branch, 2026-05-19, against `~/.cupertino/docs/` on the Studio. Coordinated via the `c1`/`c2` claude-chat collab; the three throughput data points are captured in chat at `2026-05-19T04:01:30`, `04:24:50`, and the production figure was the existing `cupertino save --docs` 11h baseline from the v1.2.0 reindex (#779 crash log committed at `docs/audits/issue-779-reindex-crash-20260518.log`).
