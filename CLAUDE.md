# Cupertino

## Active focus

[#183 — bugs → recrawl → vector → tutor](https://github.com/mihaelamj/cupertino/issues/183). v1.0.0 "First Light" shipped 2026-05-05, v1.0.1 shipped 2026-05-08, v1.0.2 shipped 2026-05-11.

## v1.0.2 (shipped 2026-05-11)

First v1.0.x release with a re-indexed bundle. `databaseVersion` jumps from `1.0.0` to `1.0.2`. The v1.0.0 / v1.0.1 bundles carried 61,257 case-axis duplicate clusters covering 122,522 rows (~30% of `docs_metadata`) because pre-#283 `URLUtilities.filename(_:)` hashed the raw case-preserving URL. The v1.0.2 bundle is clean (277,640 documents across 402 frameworks, `GROUP BY LOWER(url) HAVING COUNT > 1` returns zero). v1.0.2's planned work (#199, #203, #277) folds in.

Closed:

- [#283](https://github.com/mihaelamj/cupertino/issues/283): URL case canonicalization (reopens #200 with the correct query). `URLUtilities.filename(_:)` now canonicalizes the URL before hashing. Re-indexed bundle ships at v13.
- [#276](https://github.com/mihaelamj/cupertino/issues/276): dedup verification after #199 + #200 (closed by the v1.0.2 reindex)
- [#277](https://github.com/mihaelamj/cupertino/issues/277): crawler stores under request URL not response.url (folded in)
- [#203](https://github.com/mihaelamj/cupertino/issues/203): HTML fallback link augmentation (folded in)
- [#199](https://github.com/mihaelamj/cupertino/issues/199): contentHash determinism (validated empirically; not a bundle-DB concern)

Upgrade path: `cupertino setup` to download the v1.0.2 bundle. v12 DBs are rejected at open with "rebuild required" message. No in-place migration ships (an earlier draft was deleted before tag).

## v1.0.3 (next)

Open follow-ups from the #283 audit: [#284](https://github.com/mihaelamj/cupertino/issues/284) crawler error-page filter (45 rows of 403/502 content in the old bundle), [#285](https://github.com/mihaelamj/cupertino/issues/285) dash/underscore URI canonicalization (31 clusters / 62 rows, low priority). Plus carried-over [#236](https://github.com/mihaelamj/cupertino/issues/236) WAL on local DBs, [#241](https://github.com/mihaelamj/cupertino/issues/241) help-text audit, [#253](https://github.com/mihaelamj/cupertino/issues/253) concurrent `save` detection.

Live bug list: https://github.com/mihaelamj/cupertino/issues?q=is%3Aopen+is%3Aissue+label%3Abug

Workflow: trunk-based development. Branch from `main` per bug (`fix/<issue>-<topic>`), PR to `main`, squash merge. Auto-delete-on-merge is enabled. No long-lived feature branches.

## Phase 2 onwards

See #183. v1.1+ design and academic research review live in `mihaela-blog-ideas/cupertino/research/`. The diagnostic block in MCP responses (Phase 2.1) is the keystone for everything that follows; do not start it until v1.0.3 ships.

## Conventions

See the imported `mihaela-agents/Rules/AGENTS.md` (resolved below) for code style, commit format, and the "ask when unsure" workflow. No local `AGENTS.md` at the repo root — the canonical rules live in the private rules repo.

## Principles

See `docs/PRINCIPLES.md` for the engineering principles the import + indexer paths stand on (lossless URIs, collisions handled at the door, no content lost at the door, garbage filtered at input, 10x scale headroom, correctness first).

## Issue body hygiene

Issue tracker discipline is documented in `docs/audits/methodology.md` under "Issue body hygiene". Short version: every issue body carries a `## Status (YYYY-MM-DD)` block at the top; no line numbers in references (use symbol names); every `'backtick-quoted-path'` must exist in the repo at write time; cross-references in blocker phrasing must be to OPEN issues. `scripts/check-issue-body-staleness.sh` (run nightly by `.github/workflows/issue-body-staleness.yml`) is the mechanical backstop. When a PR renames a file, the author runs the script's `--check=renamed` mode and updates any matched issue bodies in the same PR.

## Imported Rules

@../../private/mihaela-agents/Rules/AGENTS.md
