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

---

### Update 2026-05-19 (afternoon): the full-corpus run gave a better fit

The original three-point fit above was extrapolated from two mini-corpus runs plus the May 18 production point. The 2026-05-19 v1.2.0-prep production reindex (PID 25122, started 08:09 against the post-#779-fix binary) gave 25 dense rate-at-N samples instead of 3. Fitting `rate = c / N^alpha` against those 25 points (log-log regression):

```
rate = 8,106,844 / N^1.126   docs/s
```

i.e. total wall time scales as **N^2.126** — even worse than N^1.9. The principle from §5 is violated harder than the three-point estimate suggested.

Rate-vs-N table (every 10K docs, from log timestamps):

| N (docs) | cumulative wall | docs/s in this window |
|---|---|---|
| 10,100 | 0.6 min | 294 |
| 30,100 | 4.3 min | 70 |
| 50,100 | 12.1 min | 39 |
| 100,100 | 47.0 min | 16 |
| 150,100 | 113.0 min | 13 |
| 200,100 | 192.1 min | 9.7 |
| 250,100 | 300.3 min | 7.4 |

Predicted rate at N=351,509 (end of apple-docs phase): **4.6 docs/s**. Integrated total wall: **~10 h** for apple-docs alone (+~1 h for optional sources and enrichment passes = ~11 h total). The May 18 11h15m baseline wasn't a worst case; it's the steady state.

For the 10× headroom target (4M docs), the new exponent extrapolates to roughly **two months** of indexing, vs the ten days the old fit predicted. The gap between principle and reality is larger than we thought.

**Source data for the update:** the live `cupertino save --docs --base-dir ~/.cupertino-dev` run on the Studio, log at `~/.cupertino-dev/reindex-20260519-080940.log`, sampled every 10,000 indexed docs.

**Mihaela's stance (2026-05-19):** not pursuing this as a perf bug. It's a SQLite FTS5 characteristic: incremental `INSERT INTO docs_fts` cost grows with the table because FTS5 maintains its `*_docsize` / `*_idx` / `*_content` shadow tables in lockstep with each insert, and `INSERT OR REPLACE` on the dedup path pays an additional rewrite cost as the URI index grows. The classical fix is bulk-load (collect rows in a staging table, then re-create the FTS index over the full set), which is a real architectural change to the save pipeline, not a small tweak.

The cost is acceptable because **`cupertino save --docs` only runs when the search.db schema changes** (e.g. v17 → v18 in #789 today; v16 → v17 in #755; etc.) — not on every release. Most cupertino releases reuse the prior bundle unmodified. Users never run save themselves; they pull pre-built bundles via `cupertino setup`. The 11h is paid by the maintainer, once per schema bump, not by users. PRINCIPLES.md §5's "10x headroom" remains the right aspirational ceiling for design discussion, but the gap between aspiration and reality on the indexing-time axis is not blocking anything user-visible right now.

If at some future point a re-index has to happen mid-day under pressure (incident response, hot data refresh), the bulk-load redesign becomes worth filing. Until then, file-and-forget.

The standard SQLite-community mitigations for this exact slowdown shape (FTS5 bulk-load patterns, automerge=0 + optimize, pragma tuning, external-content tables) are written up at [`docs/perf/2026-05-19-fts5-bulk-load-research.md`](perf/2026-05-19-fts5-bulk-load-research.md) so when the time comes the next maintainer doesn't re-derive them from first principles.
