# Cupertino

## Active focus

[#183 — bugs → recrawl → vector → tutor](https://github.com/mihaelamj/cupertino/issues/183). v1.0.0 "First Light" shipped 2026-05-05; current focus is the v1.0.1 bug-fix release.

## v1.0.1 (in flight): close priority-high bugs

6 open bugs assigned to milestone [v1.0.1 (#7)](https://github.com/mihaelamj/cupertino/milestone/7), plus 1 carried over from the v1.0.0 milestone:

- [#199](https://github.com/mihaelamj/cupertino/issues/199) — contentHash and id are non-deterministic
- [#200](https://github.com/mihaelamj/cupertino/issues/200) — URL canonicalization (case + dash/underscore)
- [#202](https://github.com/mihaelamj/cupertino/issues/202) — Crawler missed page-wide references dict
- [#203](https://github.com/mihaelamj/cupertino/issues/203) — Crawler HTML fallback link extraction
- [#237](https://github.com/mihaelamj/cupertino/issues/237) — search --source samples fails when search.db is locked
- [#238](https://github.com/mihaelamj/cupertino/issues/238) — Sample search FTS5 query AND-joins
- [#107](https://github.com/mihaelamj/cupertino/issues/107) (still on v1.0.0 milestone) — `fetch --type package-docs` does not read selected-packages.json

Closed during the v1.0.1 work so far: [#261](https://github.com/mihaelamj/cupertino/issues/261) `cupertino search --source packages` returned 0 results (fixed by [#262](https://github.com/mihaelamj/cupertino/pull/262)).

Live bug list: https://github.com/mihaelamj/cupertino/issues?q=is%3Aopen+is%3Aissue+label%3Abug

Workflow: trunk-based development. Branch from `main` per bug (`fix/<issue>-<topic>`), PR to `main`, squash merge. Auto-delete-on-merge is enabled. When all v1.0.1 bugs are merged on main, cut a `release/v1.0.1` branch, finalize CHANGELOG, tag, ship the database bundle. No long-lived feature branches.

## Phase 2 onwards

See #183. v1.1+ design and academic research review live in `mihaela-blog-ideas/cupertino/research/`. The diagnostic block in MCP responses (Phase 2.1) is the keystone for everything that follows; do not start it until v1.0.1 ships.

## Conventions

See `AGENTS.md` for code style, commit format, and the "ask when unsure" workflow.

## Imported Rules

@../../private/mihaela-agents/Rules/AGENTS.md
