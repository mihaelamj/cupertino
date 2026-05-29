# Release Week (2026-05-28)

Goal: ship a cupertino release this week. Focus is landing the work already done plus the reindexed DBs. New enrichment features (conformance graph, deprecation, availability widening) are explicitly **deferred to post-release** so we do not add schema + re-enrich risk to a release.

> Scope / version still to confirm with the maintainer. Latest release: **v1.2.0 "ironclad" (2026-05-20)**. No version bump, tag, or promote happens without explicit go and an all-green gate.

## Status snapshot

- Branch: `develop` (trunk). 13 modified + 8 new files uncommitted, all from this session.
- **apple-docs reindex in flight on claw mini** (`save --source apple-docs --docs-dir .../cupertino-docs/docs --clear`, ~13h job): correct `--docs-dir`, `apple-constraints.json` present (61,040), so framework + constraints enrichment will be complete. Still in the indexing phase (enrichment audit 0 bytes).
- 7 non-apple-docs sources already reindexed on Studio (`.cupertino-fresh` + the `cupertino-dbs-2026-05-28` snapshot).
- Symbol-graph corpus downloaded (96 MB) + gitignored; constraints pipeline proven end-to-end (regenerates 61,040 / 227 in 6.4 s; samples re-enrich re-stamped 9,045).

## Done this session (shippable, uncommitted on develop)

- **Declarative enrichment-input model (#919 Source Independence Axiom).** `Search.EnrichmentInput` + `SourceDefinition.requiredEnrichmentInputs` + one generic `Search.EnrichmentInputPreflight`; deleted the two hardcoded guards (#1072 apple-constraints + `assertPackageAvailabilityComplete`). `SearchModelsTests` 112/112 incl. the 8 new `Issue919EnrichmentInputPreflightTests`.
- **`cupertino-constraints-gen` empty/degraded-corpus guard.** Hard-fails (exit 1) with help text instead of writing a 0-entry table. Proven against the empty corpus + the happy path.
- **`PackageIndexer` swift-tools fallback** (prior): toolchain stamp survives when `availability.json` is absent.
- **Docs:** `docs/symbolgraph-corpus.md` (the corpus -> apple-constraints.json -> enrichment pipeline), `docs/commands/constraints-gen/`, 3 missing `save` option docs (`--allow-degraded-enrichment`, `--hig-dir`, `--swift-book-dir`), the enrichment-inventory generation matrix, the axiom in `CLAUDE.md`, CHANGELOG entries. Docs-drift checker green (19 cmds, 0 drift). Stray `.DS_Store` removed.

## Release-critical TODO

1. **Land the uncommitted work.** Group into logical commits on `develop` (declarative model; constraints-gen guard; docs). Maintainer pushes / opens the PR (no GitHub push from here). Verify em-dash-clean + AI-attribution-clean in commit subjects + bodies.
2. **Finish the apple-docs reindex on claw** (~ETA from its 13h start). Then verify the output DB: `framework` correct (not `"docs"`), `frameworkRoots > 0`, `generic_constraints` populated, no degraded enrichment. `scp` to Studio.
3. **Assemble the 8-DB snapshot** in `/Volumes/Code/DeveloperExt/private/cupertino-dbs-2026-05-28` (tasks #185-187): 7 reindexed sources from Studio + apple-docs from claw; back up the prior snapshot; verify each DB's counts vs the backup.
4. **Full release gate (must be green):**
   - `xcrun swift build` (all targets) + `xcrun swift test` (full suite). Resolve the `EnrichmentBatteryTests` env-flakiness: it needs the snapshot at `CUPERTINO_DB_DIR` and serial CLI spawns (the CLI layer's cold-3GB-DB opens flake under parallel load); confirm it passes with `CUPERTINO_DB_DIR` set, or skips cleanly when the snapshot is absent.
   - `swiftformat --lint` + `swiftlint` (no NEW violations; the `Save.swift`/`Save.Indexers.swift` length warnings are pre-existing legacy debt).
   - Rule-canon audit, em-dash sweep (content + PR/commit metadata), docs-drift checker, CHANGELOG-on-non-trivial.
5. **CHANGELOG:** finalize the `## Unreleased` section into `## vX.Y.Z (date)` (GATED on go).
6. **Release ceremony (GATED on explicit go + all green):** version bump (`Shared.Constants.App.version`), git tag, promote `develop` -> `main` (FF via a `release/vX.Y.Z` branch head, not develop directly), bundle the per-source DBs -> GitHub Releases, Homebrew formula bump, README sweep (target/package counts), update the #183 roadmap.

## Deferred to post-release (do NOT build this week)

- **Conformance-graph enrichment** (#201): symbol-graphs carry ~108,313 `conformsTo` vs ~8,595 in the DB (a ~12x gap). High value, but a new artifact + pass + schema + apple-docs re-enrich. Post-release.
- **Deprecation flags** (~64,852 markers dropped) and **per-symbol availability precision**: same shape, post-release.
- **Availability widening onto samples/packages**: ruled out as a correctness regression (would inflate per-item floors; packages use `if #available` to stay below). Not building.

## Open questions (for the maintainer)

- Release version + scope: what must be in this week's release?
- The uncommitted work: confirm the commit grouping + that the apple-docs reindexed DB is required for the release (vs shipping the current snapshot).
- `EnrichmentBatteryTests`: fix the CLI-layer skip-gate, or just set `CUPERTINO_DB_DIR` for the local release-gate run and let CI skip?
