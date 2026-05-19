# SQLite FTS5 bulk-load research (2026-05-19)

A note on what's known and standard in the SQLite community about FTS5 insert throughput at the corpus scale cupertino operates at (351K+ rows). Filed after the 2026-05-19 v1.2.0-prep production reindex measured `rate ∝ 1 / N^1.126`, total wall scaling as N^2.126. The numbers are loud enough to be worth filing the standard mitigations, even if we don't adopt them yet.

Per Mihaela's stance on 2026-05-19, the current approach is **file-and-forget**: not pursuing the optimization until a real time pressure justifies the engineering cost. This note captures the research so when the time comes, the next maintainer doesn't re-derive it from first principles.

Companion to: `docs/fun-facts.md` (the rate-vs-N measurements that motivated this research) and the #779 postmortem at `docs/postmortems/2026-05-18-save-symlink-enotdir.md` (which surfaced the v1.2.0 reindex that produced the data).

## The mechanism (why it's N^2.126, not linear)

FTS5 maintains its inverted index as **multi-level segment trees** in shadow tables (`docs_fts_data`, `docs_fts_idx`, `docs_fts_content`, `docs_fts_docsize`). Each INSERT writes a new level-0 segment. The `automerge` policy (default ON) does roughly 64 work units per insert to compact segments incrementally; the periodic `crisismerge` rewrites entire merged levels when segment count crosses a threshold (default 16).

On wide tokenized rows like cupertino's `docs_fts` (9 columns including `content`, `symbols`, `symbol_components`), each insert produces a large level-0 segment, and as upper levels grow, each `crisismerge` becomes expensive because it rewrites the whole merged level. That's where superlinear scaling enters. It's structural to FTS5's incremental-insert design, not a bug.

Sources: [Fedor Indutny's FTS5 internals notes](https://darksi.de/13.sqlite-fts5-structure/), the [annotated merging-algorithm gist](https://gist.github.com/indutny/ae44fd93dde2736205609d19a21b87cc), and Dan Kennedy's [trigram-perf thread response](https://sqlite.org/forum/info/3a398a3dbf3a95efd2d2e5d50f7c18571a4135b92aae7c3eaa04367cdfbb5037) on the SQLite forum.

## The standard escape hatches, in cost order

### A. Pragma stack tuning (cheapest, ~10 LOC)

The community-canonical bulk-load pragmas, per [phiresky's tuning post](https://phiresky.github.io/blog/2020/sqlite-performance-tuning/):

```sql
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 30000000000;     -- 30 GB virtual, harmless if unused
PRAGMA cache_size = -262144;        -- 256 MB
PRAGMA wal_autocheckpoint = 0;      -- disable during bulk load
PRAGMA journal_size_limit = -1;     -- unlimited during bulk load
-- on finish:
PRAGMA wal_checkpoint(TRUNCATE);
```

What cupertino has today (`Search.Index.swift` connection-open):
- `journal_mode = WAL`
- `synchronous = NORMAL`
- `journal_size_limit = 67108864` (64 MB), **too low for 351K rows**; forces mid-load checkpoints that interleave with FTS segment writes

Missing: `temp_store`, `mmap_size`, `cache_size`, `wal_autocheckpoint` handling. Estimated gain from adding these: 30-50%.

### B. `automerge=0` + chunked transactions + `optimize` (~50 LOC)

Disable automerge for the bulk-load window, batch inserts in 5K-row transactions (fewer COMMITs means fewer level-0 segments), call `optimize` at the end:

```sql
INSERT INTO docs_fts(docs_fts, rank) VALUES('automerge', 0);
-- ... bulk insert all rows in 5K-row transactions ...
INSERT INTO docs_fts(docs_fts) VALUES('optimize');
```

Sources: [sqlite-users mailing list](https://sqlite-users.sqlite.narkive.com/FsHtboS0/sqlite-properly-bulk-inserting-into-fts5-index-with-external-content-table), [sqlite.work production write-up](https://sqlite.work/optimizing-fts5-external-content-tables-and-vacuum-interactions/).

Estimated gain over A alone: 2-3× additional.

### C. `'rebuild'` after bulk-loading metadata (medium architectural)

Documented in [SQLite FTS5 §6.12](https://www.sqlite.org/fts5.html). Deletes the FTS index entirely and reconstructs it from the content table:

```sql
INSERT INTO docs_fts(docs_fts) VALUES('rebuild');
```

`simonw/sqlite-utils` ships this as the canonical CLI verb (`sqlite-utils rebuild-fts`). The trade-off: requires populating `docs_metadata` + `docs_structured` BEFORE building the FTS index, so the save pipeline becomes two-phase (insert metadata → bulk-build FTS). During the bulk-build window, FTS searches return empty. Acceptable if save is offline.

Estimated total wall reduction: ~5×.

### D. External-content FTS5 (largest architectural)

Restructure the schema so `docs_fts` is content-less and references `docs_metadata` for the actual row content:

```sql
CREATE VIRTUAL TABLE docs_fts USING fts5(
    uri, source, framework, language, title, content, summary, symbols, symbol_components,
    content='docs_metadata',
    content_rowid='rowid',
    tokenize='porter unicode61'
);
```

Then bulk-load via a single `INSERT INTO docs_fts(rowid, uri, ...) SELECT id, uri, ... FROM docs_metadata`. The sqlite-users mailing list describes this as "very fast." Storage halves (content stored once, not twice). Trade-off: `'rebuild'` requires the regular-content shape, so external-content removes one escape hatch. Plus query semantics on contentless tables differ slightly (less convenient `bm25()` access).

Estimated total wall reduction: 5-10×.

## The minimal-effort high-leverage move

If we ever pursue this, **A + B together** (~60 LOC across `Search.Index.swift` and the source strategies):

- Connection-open: add `temp_store`, `mmap_size`, `cache_size`, `wal_autocheckpoint=0`, raise `journal_size_limit`
- Save start: `INSERT INTO docs_fts(docs_fts, rank) VALUES('automerge', 0);`
- Per-strategy doc loop: wrap in 5K-row chunked transactions
- Save end: `INSERT INTO docs_fts(docs_fts) VALUES('optimize');` + `PRAGMA wal_checkpoint(TRUNCATE);`

Likely outcome: 11h → 2-3h. Risk: low; all PRAGMAs and FTS5 commands are documented and behavior-preserving. The only behavioral change is that FTS search inside the save window is degraded (concurrent search clients would see stale results until `optimize` returns). Acceptable for our use case because save is offline.

Change C (external-content) is the order-of-magnitude move beyond that. Schema change → migration → all the FTS5-touching code re-tested. Not worth it unless A+B aren't enough.

## What the literature doesn't have

No widely-cited rows-per-second insert benchmark for FTS5 at 1M+ rows. Most production write-ups focus on query-side performance, not insert. If cupertino ever measures + publishes A+B before-and-after numbers on a 351K-row corpus, we'd be establishing reference data nobody else has put out.

## Why not pursue this now

Mihaela's stance (2026-05-19): `cupertino save --docs` only runs on schema bumps (not per-release), users never run save themselves (they pull pre-built bundles via `cupertino setup`), so the 11h cost is paid by the maintainer once per schema bump. The cost is annoying but not user-facing.

When the calculus would change:

- A mid-day re-index ever becomes a pressure event (incident response, hot data refresh, urgent corpus fix needed before a release window)
- Schema bumps become frequent enough that 11h-per-bump compounds noticeably
- The 10x scale headroom target (4M docs) becomes a real engineering goal, at which point the N^2 extrapolation projects to ~two months of indexing, which IS user-facing
- We add a new source that requires re-indexing existing rows (e.g., a global ranker tweak)

Until one of those happens: keep this note, link from `docs/fun-facts.md`, walk away.

## Sources

- [SQLite FTS5 official docs (§6.1, 6.2, 6.8, 6.9, 6.12, 6.14)](https://www.sqlite.org/fts5.html)
- [sqlite-users mailing list: bulk-inserting into FTS5 with external content](https://sqlite-users.sqlite.narkive.com/FsHtboS0/sqlite-properly-bulk-inserting-into-fts5-index-with-external-content-table)
- [SQLite forum: FTS5 trigram slow on insert (Dan Kennedy)](https://sqlite.org/forum/info/3a398a3dbf3a95efd2d2e5d50f7c18571a4135b92aae7c3eaa04367cdfbb5037)
- [SQLite forum: FTS5 external content tables](https://sqlite.org/forum/info/df8f0e2d22534373)
- [Fedor Indutny: Structure of FTS5 Index in SQLite](https://darksi.de/13.sqlite-fts5-structure/)
- [Indutny: Notes on FTS5 Merging Algorithm](https://gist.github.com/indutny/ae44fd93dde2736205609d19a21b87cc)
- [phiresky: SQLite performance tuning](https://phiresky.github.io/blog/2020/sqlite-performance-tuning/)
- [sqlite.work: Optimizing FTS5 External Content Tables and VACUUM Interactions](https://sqlite.work/optimizing-fts5-external-content-tables-and-vacuum-interactions/)
- [simonw/sqlite-utils #155: rebuild-fts CLI verb](https://github.com/simonw/sqlite-utils/issues/155)
- [PDQ: Improving bulk insert speed in SQLite](https://www.pdq.com/blog/improving-bulk-insert-speed-in-sqlite-a-comparison-of-transactions/)
- [Microsoft.Data.Sqlite: Bulk insert](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/bulk-insert)
- [Alex Garcia: Hybrid FTS + vector search with SQLite](https://alexgarcia.xyz/blog/2024/sqlite-vec-hybrid-search/index.html)
- [Simon Willison: Hybrid full-text + vector search with SQLite](https://simonwillison.net/2024/Oct/4/hybrid-full-text-search-and-vector-search-with-sqlite/)
