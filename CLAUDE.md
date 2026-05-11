# Cupertino

## Active focus

[#183 — bugs → recrawl → vector → tutor](https://github.com/mihaelamj/cupertino/issues/183). v1.0.0 "First Light" shipped 2026-05-05, v1.0.1 shipped 2026-05-08, v1.0.3 shipped 2026-05-11. The v1.0.2 tag was skipped (folded into v1.0.3).

## v1.0.3 (shipped 2026-05-11)

First v1.0.x release with a re-indexed bundle. `databaseVersion` jumps from `1.0.0` to `1.0.3`. The v1.0.0 / v1.0.1 bundles carried 61,257 case-axis duplicate clusters covering 122,522 rows (~30% of `docs_metadata`) because pre-#283 `URLUtilities.filename(_:)` hashed the raw case-preserving URL. The v1.0.3 bundle is clean (277,640 documents across 402 frameworks, `GROUP BY LOWER(url) HAVING COUNT > 1` returns zero). v1.0.2's planned work (#199, #203, #277) folds in.

Closed:

- [#283](https://github.com/mihaelamj/cupertino/issues/283): URL case canonicalization (reopens #200 with the correct query). `URLUtilities.filename(_:)` now canonicalizes the URL before hashing. Re-indexed bundle ships at v13.
- [#276](https://github.com/mihaelamj/cupertino/issues/276): dedup verification after #199 + #200 (closed by the v1.0.3 reindex)
- [#277](https://github.com/mihaelamj/cupertino/issues/277): crawler stores under request URL not response.url (folded in)
- [#203](https://github.com/mihaelamj/cupertino/issues/203): HTML fallback link augmentation (folded in)
- [#199](https://github.com/mihaelamj/cupertino/issues/199): contentHash determinism (validated empirically; not a bundle-DB concern)

Upgrade path: `cupertino setup` to download the v1.0.3 bundle. v12 DBs are rejected at open with "rebuild required" message. No in-place migration ships (an earlier draft was deleted before tag).

## v1.0.4 (next)

Open follow-ups from the #283 audit: [#284](https://github.com/mihaelamj/cupertino/issues/284) crawler error-page filter (45 rows of 403/502 content in the old bundle), [#285](https://github.com/mihaelamj/cupertino/issues/285) dash/underscore URI canonicalization (31 clusters / 62 rows, low priority). Plus carried-over [#236](https://github.com/mihaelamj/cupertino/issues/236) WAL on local DBs, [#241](https://github.com/mihaelamj/cupertino/issues/241) help-text audit, [#253](https://github.com/mihaelamj/cupertino/issues/253) concurrent `save` detection.

Live bug list: https://github.com/mihaelamj/cupertino/issues?q=is%3Aopen+is%3Aissue+label%3Abug

Workflow: trunk-based development. Branch from `main` per bug (`fix/<issue>-<topic>`), PR to `main`, squash merge. Auto-delete-on-merge is enabled. No long-lived feature branches.

## Phase 2 onwards

See #183. v1.1+ design and academic research review live in `mihaela-blog-ideas/cupertino/research/`. The diagnostic block in MCP responses (Phase 2.1) is the keystone for everything that follows; do not start it until v1.0.4 ships.

## Conventions

See `AGENTS.md` for code style, commit format, and the "ask when unsure" workflow.

## Imported Rules

@../../private/mihaela-agents/Rules/AGENTS.md
