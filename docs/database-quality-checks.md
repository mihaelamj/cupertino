# Database semantic-quality checks

A per-source database can have the right **schema**, pass `PRAGMA integrity_check`, open read-only, and report a confident document count from `save` — and still ship **rotten content**. This doc is the methodology and the mechanical gate for catching that class of defect, which schema/integrity checks sail straight past.

> **Run before publishing any database bundle:** `scripts/check-db-quality.sh [~/.cupertino]`. It is a release gate. If it exits non-zero, do not publish.

## The incident that created this (2026-06-21)

A re-crawl + rebuild of `hig.db` looked perfectly healthy:

- `cupertino save --source hig` reported **"177 documents"**.
- `PRAGMA integrity_check` = **ok**.
- schema = **18** (matches binary).

Yet the shipped v1.3.0 `hig.db` held **346 rows, of which 173 were `…-appledeveloperdocumentation` placeholder duplicates** — the "Apple Developer Documentation" JS-disabled stub pages the [#284](https://github.com/mihaelamj/cupertino/issues/284) js-fallback filter exists to reject. They sat in `docs_structured` (inflating `list-frameworks` counts) while never entering `docs_fts` — so search never returned them, which is exactly why the rot went unnoticed for releases.

The re-crawl exposed **two compounding bugs** that let junk persist across a rebuild:

1. **`cupertino save --clear` rebuilds the FTS but NOT `docs_structured`.** After `save --clear`, hig's `docs_fts` was a clean 177 but `docs_structured` still held all 350 rows (177 fresh + 173 stale junk). `--clear` is not sufficient to remove stale rich-data rows.
2. **`cupertino fetch --start-clean` does NOT wipe the output corpus directory.** It ignores the saved crawl *session* but leaves orphaned files on disk. When a crawler's filename convention changes, the old files accumulate: swift-evolution's corpus became **917 files = 429 old `NNNN-slug.md` + 488 new `SE-NNNN.md`**, and the "559 crawled vs 488 saved" gap was this pollution, not lost proposals.

Net consequence: re-crawling and re-saving a source does **not** by itself clean it. You must wipe both layers.

## The invariant

> For every docs-schema database, `docs_structured` and `docs_fts` hold the **same population** — ratio ≈ 1.00. A row that is **counted** (`docs_structured`) but **not searchable** (`docs_fts`) is junk by construction: either a placeholder stub or a stale row a non-clean rebuild left behind.

Measured 2026-06-21:

| Database | structured | fts | ratio | verdict |
|---|---:|---:|---:|---|
| apple-documentation.db | 363,562 | 363,566 | 1.00 | clean |
| swift-evolution.db | 487 | 487 | 1.00 | clean |
| swift-org.db | 469 | 469 | 1.00 | clean |
| apple-archive.db | 368 | 368 | 1.00 | clean |
| swift-book.db | 43 | 43 | 1.00 | clean |
| **hig.db (rotten)** | **346** | **173** | **2.00** | **173 junk** |

`scripts/check-db-quality.sh` enforces ratio ≤ 1.02, plus two exact-pattern detectors for the specific junk shape:

- URIs ending in a known placeholder suffix (`-appledeveloperdocumentation`).
- Titles equal to the placeholder string `Apple Developer Documentation`.

Both pattern lists live at the top of the script; extend them as new placeholder shapes are found.

## The guaranteed-clean rebuild recipe

Because neither `save --clear` nor `fetch --start-clean` fully resets state, a clean rebuild of a source must wipe **both** the corpus directory **and** the database file:

```sh
rm -rf  ~/.cupertino/<source>/        # wipe corpus dir (defeats fetch accumulation)
cupertino fetch --source <source> --start-clean
rm -f   ~/.cupertino/<source>.db      # wipe DB (forces docs_structured to rebuild)
cupertino save  --source <source>
scripts/check-db-quality.sh           # prove it — must exit 0
```

`<source>` is the canonical registry id: `hig`, `swift-evolution`, `swift-book`, `swift-org`, `apple-archive`, `apple-docs`. The destination DB filenames are mapped by the registry (e.g. `hig` → `hig.db`, `apple-docs` → `apple-documentation.db`).

## Semantic coverage analysis (when a count changes)

A count drop on a rebuild is **not** automatically a regression, and a count rise is **not** automatically progress. Distinguish *real* content from *junk* before trusting a delta. The 2026-06-21 hig analysis is the worked example:

1. **Junk-dupe accounting** — split the old count into real vs placeholder:
   ```sql
   SELECT COUNT(*)                                                  AS total,
          SUM(uri LIKE '%-appledeveloperdocumentation')            AS junk,
          SUM(uri NOT LIKE '%-appledeveloperdocumentation')        AS clean
   FROM docs_structured;
   ```
   hig: total 346 = 173 clean + 173 junk. The DB was half placeholders.

2. **Topic-level coverage diff** — compare the *real* topic sets (last URI path segment), not raw counts:
   - topics in old-clean missing from new crawl → **0** (no real content lost)
   - topics new in the fresh crawl → **+4** (`design-principles`, `gyro-and-accelerometer`, `snippets`, `spatial-interactions`)

   So 346 (173 real + 173 junk) → 177 (174 real, 0 junk, +4 topics). The "drop" was the junk leaving; real coverage went *up*.

3. **Content-quality validation** — confirm the survivors are real pages, not new stubs:
   - file/byte size distribution (placeholder stubs are tiny: < 300 B)
   - count of pages whose first heading / title is the placeholder string
   - spot-check that core topics carry full bodies (hig: typography 43 KB, color 27 KB, buttons 20 KB)

What does **not** indicate rot (verified benign 2026-06-21): all-empty `abstract`/`overview` columns for swift-evolution / apple-archive / hig (those sources carry their body text in `docs_fts`, not the structured columns — schema-fit, not loss), and duplicate titles in swift-org (104: "Install Swift" ×12 → distinct per-OS install guides) and apple-archive (81: "Revision History" ×38 → per-guide boilerplate sections).

## When to run

- **Always** before `cupertino-rel databases` / publishing a bundle (release gate).
- After **any** re-crawl or `save`, against `~/.cupertino`.
- After staging a bundle, against the staged copies — junk in a `.backup` snapshot ships too.

## See also

- `docs/database-handbook.md` — canonical index for all database docs.
- `docs/PRINCIPLES.md` — "garbage filtered at input", "no content lost at the door".
- [#284](https://github.com/mihaelamj/cupertino/issues/284) — the js-fallback placeholder-rejection filter these placeholders evade when they reach `docs_structured` by another path.
