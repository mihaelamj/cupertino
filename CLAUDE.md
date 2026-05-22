# Cupertino

## Active focus

[#183 — bugs → recrawl → vector → tutor](https://github.com/mihaelamj/cupertino/issues/183). Shipped: v1.0.0 "First Light" (2026-05-05), v1.0.1 (2026-05-08), v1.0.2 (2026-05-11), v1.1.0 (2026-05-14), **v1.2.0 "ironclad" (2026-05-20)**. Live search-quality dashboard: https://cupertino.aleahim.com/.

## v1.2.0 (shipped 2026-05-20)

The "ironclad" round. 107 CHANGELOG entries; +762 net new tests since v1.1.0 (2218 / 303 suites green); 0 open bug-labeled issues at tag time. First release to ship documented search-quality baselines: Phase 1 canonical lookup, Phase 1.1 deprecation-aware, Phase 1.2 cross-source, Phase 1.3 CamelCase fragment, Phase 1.4 acronym/synonym, Phase 1.5 prose/conceptual, Phase 1.6 symbol-attribute, Phase 1.7 agent-end-to-end, plus the Phase 1.8 version-diff audit pairing v1.0.2 against v1.2.0 via McNemar. Audits at `docs/audits/search-quality-*-v1.2.0.md`. Headlines:

- **Concurrent-save infrastructure:** #253 SaveSiblingGate + #722 `--force-replace` recovery flag with typed-confirmation gate
- **MCP surface:** #226 platform filter on 4 AST tools + #665 `search_generics` (12th MCP tool) + platform filter on `search_generics`
- **Schema bumps:** packages.db v2→v3 (#225 Part A `swift_tools_version`), search.db v15→v18 (#225 Part B + #789 drop redundant packages tables)
- **Indexer hardening:** #113 `doc://` → `https://` rewriter + audit-count, #668 `docs_structured` coverage, #669 inheritance fallback, #673 ironclad phases E/F/G/H
- **Save pipeline robustness:** #779 `optionalDir` resolves symlinks before FileManager URL-variant APIs + per-strategy `do/catch` keeps enrichment passes running if one strategy throws; #786 `Shared.Utils.FileSystem` wrappers at 6 call sites
- **Observability:** #780 / #781 per-line ISO 8601 timestamps + startup invocation banner in CLI logs
- **Triage discipline:** `scripts/check-canonical-db-shape.sh` smoke check + `scripts/check-pre-index.sh` pre-flight validation gate (#794)
- **Documented design + architecture:** `docs/design/cupertino.md` rewrite + `docs/architecture/database.md` + `docs/database-handbook.md` single entry point

Upgrade path: `cupertino setup` to download the v1.2.0 bundle. The new bundle was indexed against the post-#779 binary against `cupertino-docs@v1.2.0` (post-Claw-merge: 414,807 source files, +2,285 new pages + 498 richer overwrites from Claw mini's 5.5-day crawl, 153 React-SPA-404 poison files filtered at the merge boundary; 13-category poison audit zero-matches on the merged corpus).

## v1.1.0 (shipped 2026-05-14)

Bundle rebuilt against the post-cleanup corpus (`cupertino-docs@v1.1.0`): 285,735 documents across 420 frameworks, 0 poison rows under all 13 audit categories, includes 43 markdown gap-fillers converted to canonical `StructuredDocumentationPage` JSON, benefits from the crawler-side JS-fallback gate (PR #432). Same SQLite schema as v1.0.x (`user_version` 13).

## v1.0.2 (shipped 2026-05-11)

First v1.0.x release with a re-indexed bundle. `databaseVersion` jumps from `1.0.0` to `1.0.2`. The v1.0.0 / v1.0.1 bundles carried 61,257 case-axis duplicate clusters covering 122,522 rows (~30% of `docs_metadata`) because pre-#283 `URLUtilities.filename(_:)` hashed the raw case-preserving URL. The v1.0.2 bundle is clean (277,640 documents across 402 frameworks, `GROUP BY LOWER(url) HAVING COUNT > 1` returns zero). v1.0.2's planned work (#199, #203, #277) folds in.

Closed:

- [#283](https://github.com/mihaelamj/cupertino/issues/283): URL case canonicalization (reopens #200 with the correct query). `URLUtilities.filename(_:)` now canonicalizes the URL before hashing. Re-indexed bundle ships at v13.
- [#276](https://github.com/mihaelamj/cupertino/issues/276): dedup verification after #199 + #200 (closed by the v1.0.2 reindex)
- [#277](https://github.com/mihaelamj/cupertino/issues/277): crawler stores under request URL not response.url (folded in)
- [#203](https://github.com/mihaelamj/cupertino/issues/203): HTML fallback link augmentation (folded in)
- [#199](https://github.com/mihaelamj/cupertino/issues/199): contentHash determinism (validated empirically; not a bundle-DB concern)

Upgrade path: `cupertino setup` to download the v1.0.2 bundle. v12 DBs are rejected at open with "rebuild required" message. No in-place migration ships (an earlier draft was deleted before tag).

## v1.3.x (next)

Carried-over backlog: [#514](https://github.com/mihaelamj/cupertino/issues/514) WAL throughput measurement on the docs workload (samples-workload measurement landed via PR #515); [#410](https://github.com/mihaelamj/cupertino/issues/410) split search.db; [#708](https://github.com/mihaelamj/cupertino/issues/708) / [#709](https://github.com/mihaelamj/cupertino/issues/709) / [#715](https://github.com/mihaelamj/cupertino/issues/715) / [#719](https://github.com/mihaelamj/cupertino/issues/719) search-quality cluster (all closed as false positives this round, refile if real); [#713](https://github.com/mihaelamj/cupertino/issues/713) fastlane + [#714](https://github.com/mihaelamj/cupertino/issues/714) tuist external sources; [#624](https://github.com/mihaelamj/cupertino/issues/624) test-everything skill.

Live bug list: https://github.com/mihaelamj/cupertino/issues?q=is%3Aopen+is%3Aissue+label%3Abug

Workflow: trunk-based development. Branch from `main` per bug (`fix/<issue>-<topic>`), PR to `main`, squash merge. Auto-delete-on-merge is enabled. No long-lived feature branches.

## Phase 2 onwards

See #183. v1.1+ design and academic research review live in `mihaela-blog-ideas/cupertino/research/`. The diagnostic block in MCP responses (Phase 2.1) is the keystone for everything that follows; do not start it until the v1.3.x backlog above is drained.

## Conventions

See the imported `mihaela-agents/Rules/AGENTS.md` (resolved below) for code style, commit format, and the "ask when unsure" workflow. No local `AGENTS.md` at the repo root — the canonical rules live in the private rules repo.

## Principles

See `docs/PRINCIPLES.md` for the engineering principles the import + indexer paths stand on (lossless URIs, collisions handled at the door, no content lost at the door, garbage filtered at input, 10x scale headroom, correctness first).

## Pluggability invariant (load-bearing)

**Each content source must be 100% pluggable, not 80% with caveats.** Adding a new source (WWDC transcripts #58, Swift Forums #89, Tech Talks #273, anything later) is a declarative PR that touches no existing concretes. Target shape: 2 files (a descriptor + an indexer concrete) with zero edits to any existing source's code, zero edits to a static registry dictionary, zero edits to a closed enum.

Same standard for databases: adding a new DB (if a future source ships as its own SQLite, not as another source in `search.db`) is one `Distribution.DatabaseHealthCheck` conformer + one list append at the composition root.

This invariant is the load-bearing goal of the `#919` declarative source + DB pluggability epic. It is NOT optional polish. Do not declare any plug-in / descriptor / registry refactor "done" until the end-to-end 2-file PR claim is empirically proven (a fake source plugs in via a test fixture, the existing 8 source concretes are untouched, and the full test + audit suite stays green).

Status today (2026-05-22): partial. The `#248` + `#251` arcs (PRs #920 to #929 + #930) collapsed source identity to one constant per source and lifted the `Distribution.SetupService` / `Doctor` / `InstalledVersion` surfaces onto descriptors. Still hardcoded: the `IndexerRegistry` static `[String: any Search.SourceIndexer]` dictionary in `SearchSQLite/Search.SourceIndexer.swift` is the remaining edit-point per new source; lifting it to composition-root injection is the next structural cut.

## Database and search quality

See `docs/database-handbook.md` for the canonical entry point to everything about cupertino's database design, schema, indexer pipeline, probing, and search-quality evaluation. Start there for any database / FTS5 / ranking / eval question — it indexes every related artefact (architecture doc, design docs, audit methodology, universal IR rule, memory invariants) and prescribes the cold-start bootstrap order. If a database-related doc is not linked from the handbook, it is undiscoverable; the fix is to add it there in the same PR.

## Issue body hygiene

Issue tracker discipline is documented in `docs/audits/methodology.md` under "Issue body hygiene". Short version: every issue body carries a `## Status (YYYY-MM-DD)` block at the top; no line numbers in references (use symbol names); every backtick-quoted file path must exist in the repo at write time (not the literal text `'backtick-quoted-path'`, but any path in actual backticks); cross-references in blocker phrasing must be to OPEN issues. `scripts/check-issue-body-staleness.sh` (run nightly by `.github/workflows/issue-body-staleness.yml`) is the mechanical backstop. When a PR renames a file, the author runs the script's `--check=renamed` mode and updates any matched issue bodies in the same PR.

## Imported Rules

@../../private/mihaela-agents/Rules/AGENTS.md
