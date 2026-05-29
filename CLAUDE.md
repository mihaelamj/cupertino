# Cupertino

## Active focus

[#183](https://github.com/mihaelamj/cupertino/issues/183), bugs → recrawl → vector → tutor (canonical roadmap, update on every release/epic/scope change per its built-in protocol).

Latest release: **v1.2.1 (2026-05-23)**, a maintenance release (architectural cleanup + Source Independence Day; zero schema delta, reuses the v1.2.0 bundle). Prior bundle release: **v1.2.0 "ironclad" (2026-05-20)**. Live search-quality dashboard: https://cupertino.aleahim.com/. Live bug list: https://github.com/mihaelamj/cupertino/issues?q=is%3Aopen+is%3Aissue+label%3Abug.

Release archive (per-version notes, audits, McNemar diffs, bundle-rebuild details) lives in `CHANGELOG.md` and `docs/audits/`. Do not reproduce it here.

## Source Independence Day (active, post-#931)

**Each content source must be 100% pluggable, not 80% with caveats.** Adding a new source (WWDC transcripts [#58](https://github.com/mihaelamj/cupertino/issues/58), Swift Forums [#89](https://github.com/mihaelamj/cupertino/issues/89), Tech Talks [#273](https://github.com/mihaelamj/cupertino/issues/273), any future source) must be a PR that touches no existing source concrete, no static registry dictionary, no closed enum. Same standard for databases: adding a new DB is one `Distribution.DatabaseHealthCheck` conformer + one list append.

**The axiom, stated as a rule to read every session:** a new source touches **no existing source concrete, no static registry dictionary, no closed enum, no central switch**. A closed enum is allowed only when a new source *reuses* its cases without adding one.

**Corollary (guards and preflights):** any "this source needs input file X" rule (missing `apple-constraints.json`, missing per-package `availability.json`, any future enrichment input) must be a declaration the source *carries* (`SourceDefinition.requiredEnrichmentInputs`), enforced by ONE generic composition-root preflight iterating every active source. A literal-filename `if` in central save logic is a per-source edit-point, i.e. an axiom violation. Never add a hardcoded per-source guard; express it declaratively. (The producer tool `cupertino-constraints-gen` is axiom-neutral: not a content source, so a localized guard there is fine.)

This is the load-bearing goal of the [#919](https://github.com/mihaelamj/cupertino/issues/919) declarative source + DB pluggability epic. Do not declare any plug-in / descriptor / registry refactor "done" until the end-to-end 2-file PR claim is empirically proven.

**Ordered critical path** (full doc at `docs/plans/2026-05-22-source-independence-day.md`):

1. **[#932](https://github.com/mihaelamj/cupertino/issues/932)**: `IndexerRegistry` composition-root injection (drops the `SearchSQLite/Search.SourceIndexer.swift` static dict)
2. **[#933](https://github.com/mihaelamj/cupertino/issues/933)**: `Search.makeDefaultStrategies` factory dissolved (drops `SearchStrategies` as a per-source edit-point)
3. **[#934](https://github.com/mihaelamj/cupertino/issues/934)**: `Search.SourceRegistry.all` dissolved into composition-root `[Search.SourceDefinition]`
4. **[#935](https://github.com/mihaelamj/cupertino/issues/935)**: end-to-end TDD scenario with a fake source proving the 2-file PR claim

Done so far (will not re-edit per new source): `SourcePrefix.*` constants (#923/#925/#926); `Search.Source` open struct (#924); `DatabaseDescriptor` value type (#920); `Distribution.SetupService.Outcome` descriptor-keyed list (#921); `Doctor.printSchemaVersions` descriptor-keyed iteration (#922); `Distribution.DatabaseHealthCheck` strategy seam covering Doctor's 3 sibling per-DB sections (#931).

## Workflow

Two-Claude pair workflow (settled 2026-05-15). `develop` is the trunk: feature PRs target `develop`, squash-merge enabled, auto-delete-on-merge. `main` is the release branch: `develop` is FF-pushed to `main` on promote (release prep). Never PR develop directly to main. Branch from `develop` per issue: `fix/<issue>-<topic>`. The external-PR-to-main guard (#761) enforces this from the GitHub side.

## Conventions

`mihaela-agents/Rules/AGENTS.md` (imported at the bottom of this file) carries code style, commit format, GoF + DI rules, and the "ask when unsure" workflow. No local `AGENTS.md` at the repo root.

## Principles

`docs/PRINCIPLES.md` carries the engineering principles the import + indexer paths stand on: lossless URIs, collisions handled at the door, no content lost at the door, garbage filtered at input, 10x scale headroom, correctness first.

## Database and search quality

`docs/database-handbook.md` is the canonical entry point to cupertino's database design, schema, indexer pipeline, probing, and search-quality evaluation. Start there for any database / FTS5 / ranking / eval question. The handbook indexes every related artefact (architecture doc, design docs, audit methodology, universal IR rule, memory invariants) and prescribes the cold-start bootstrap order. If a database-related doc is not linked from the handbook, it is undiscoverable; the fix is to add it there in the same PR.

## Issue body hygiene

Issue tracker discipline is documented in `docs/audits/methodology.md` under "Issue body hygiene". Every issue body carries a `## Status (YYYY-MM-DD)` block at the top; no line numbers in references (use symbol names); every backtick-quoted file path must exist in the repo at write time; cross-references in blocker phrasing must be to OPEN issues. `scripts/check-issue-body-staleness.sh` (run nightly by `.github/workflows/issue-body-staleness.yml`) is the mechanical backstop. When a PR renames a file, run the script's `--check=renamed` mode and update matched issue bodies in the same PR.

## Imported Rules

@../../private/mihaela-agents/Rules/AGENTS.md
