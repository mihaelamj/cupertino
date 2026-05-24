# Source Independence Day: ordered execution plan

**Filed**: 2026-05-22. **Status**: open, executing. **Umbrella**: [#919](https://github.com/mihaelamj/cupertino/issues/919). **Critical-path issues**: [#932](https://github.com/mihaelamj/cupertino/issues/932), [#933](https://github.com/mihaelamj/cupertino/issues/933), [#934](https://github.com/mihaelamj/cupertino/issues/934), [#935](https://github.com/mihaelamj/cupertino/issues/935).

## What "Independence Day" means

Adding a new content source (WWDC transcripts [#58](https://github.com/mihaelamj/cupertino/issues/58), Swift Forums [#89](https://github.com/mihaelamj/cupertino/issues/89), Tech Talks [#273](https://github.com/mihaelamj/cupertino/issues/273), or any future source) is a 2-file PR (a descriptor + an indexer concrete) with **zero edits to existing source concretes**, **zero edits to any static registry dictionary**, and **zero edits to any closed enum**.

That is the load-bearing goal of #919. It is not "mostly pluggable with a few hardcoded edits left". The plan below names every remaining hardcoded edit-point and the step that removes it.

## State on 2026-05-22 (post-#931)

Done (will not need to touch again for a new source):

- `Shared.Constants.SourcePrefix.*`: one constant per source id. Adding a new source = +1 line here. ✅
- `Search.Source` struct is open (was a closed enum). Any `rawValue` constructs; `isRegistered` is the door check. ✅
- `Search.SourceDefinition` value type + `Search.SourceProperties` are extensible without enum exhaustiveness pain. ✅
- `Shared.Models.DatabaseDescriptor` value type drives the DB surface (#920/#921/#922). ✅
- `Distribution.DatabaseHealthCheck` strategy seam drives Doctor's per-DB sections (#931). Adding a new DB = 1 conformer + 1 append. ✅
- `Distribution.SetupService.Outcome` carries `databases: [DatabasePlacement]` (#921). ✅
- Indexer concretes' `sourceID` fields, `IndexerRegistry` keys, and strategy literal-compare sites all read from `SourcePrefix.*` constants (#923/#925/#926). ✅

Still hardcoded (the edit-points this plan removes):

1. `Packages/Sources/SearchSQLite/Search.SourceIndexer.swift`: `IndexerRegistry` static `[String: any Search.SourceIndexer]` dict. Edit-point per new source: 1 dict key + 1 indexer concrete declaration.
2. `Packages/Sources/SearchStrategies/Search.MakeDefaultStrategies.swift`: `makeDefaultStrategies(...)` factory hardcodes 6 strategy concretes. Edit-point per new source: 1 append.
3. `Packages/Sources/SearchModels/Search.SourceDefinition.swift`: `Search.SourceRegistry.all: [Search.SourceDefinition]` static list. Edit-point per new source: 1 `SourceDefinition` literal.
4. No end-to-end TDD scenario proves the 2-file claim. The "100% pluggable" assertion has not been empirically demonstrated; today it is an architectural assertion only.

Plus downstream consumer polish (after the critical path lands):

5. CLI `cupertino save --<source>` per-source flags hardcode the source list.
6. `docs/commands/<cmd>/option (--)/source.md` doc pages hardcode the source list.

## Ordered critical-path execution

Each step is a separate PR with its own critic loop (2-iteration minimum per the post-#931 discipline). Each step's "removes edit-point" claim must be paired with a test that proves the edit-point can no longer reach the touched code.

### Step 1 ([#932](https://github.com/mihaelamj/cupertino/issues/932)): `IndexerRegistry` composition-root injection

**Removes edit-point #1.**

**Pattern**: replace the static `[String: any Search.SourceIndexer]` dict with constructor-injected `[any Search.SourceIndexer]` on the consumer (`Search.IndexBuilder` or wherever the registry is consumed). The composition root in CLI assembles the list.

**Files touched**:

- `Packages/Sources/SearchSQLite/Search.SourceIndexer.swift`: remove `IndexerRegistry.all` static dict (or reduce to a thin lookup over the injected list).
- `Packages/Sources/SearchSQLite/Search.Index.swift`: the actor that owns the dict-on-actor relocation per #932; takes the list at init.
- `Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift`: composition root assembles `[any Search.SourceIndexer]` from the 7 existing concretes.
- `Packages/Tests/CLITests/`: new test pinning the composition-root list as the sole assembly point + a fake indexer test proving SearchSQLite need not be edited.

**Estimate**: ~1 day. Largest single-PR scope in this arc.

**Unlock**: a new source's indexer concrete can live in its own package; SearchSQLite stops being an edit-point per source.

### Step 2 ([#933](https://github.com/mihaelamj/cupertino/issues/933)): `Search.makeDefaultStrategies` factory dissolved

**Removes edit-point #2.**

**Pattern**: mirror of Step 1, applied to strategies. Consumer takes `strategies: [any Search.SourceIndexingStrategy]` at init. Composition root assembles the 6 production strategies.

**Files touched**:

- `Packages/Sources/SearchStrategies/Search.MakeDefaultStrategies.swift`: remove the factory or downgrade it to a test default.
- `Packages/Sources/SearchAPI/`: consumer's init signature changes.
- `Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift`: composition root extends the assembly to include strategies.
- `Packages/Tests/CLITests/`: fake strategy test.

**Estimate**: ~½ day. Mechanical follow-on to Step 1.

**Unlock**: a strategy lives next to its source's indexer (in the source's package), not centrally in `SearchStrategies`.

### Step 3 ([#934](https://github.com/mihaelamj/cupertino/issues/934)): `Search.SourceRegistry.all` dissolved

**Removes edit-point #3.**

**Pattern**: replace the static list with constructor-injected `[Search.SourceDefinition]` on each consumer of the registry. The consumers today are the ranking path, `SourcePropertiesRegistry`, and the `Search.Source.displayName` / `emoji` lookup paths.

**Subtle constraint**: `Search.Source.appleDocs`, `.samples`, etc. (the 8 static-constant accessors) are convenience, not the registry. Keep them. What changes is where the `[SourceDefinition]` lookup TABLE lives.

**Files touched**:

- `Packages/Sources/SearchModels/Search.SourceDefinition.swift`: `SourceRegistry.all` no longer the production source of truth.
- `Packages/Sources/SearchSQLite/Search.Index.Search.swift`: ranking path takes the descriptor list at init.
- `Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift`: composition root assembles `[Search.SourceDefinition]`.
- `Packages/Tests/SearchModelsTests/`, `Packages/Tests/CLITests/`: pin the data-driven lookup surface.

**Estimate**: ~½ day.

**Unlock**: descriptor list is no longer a hardcoded edit-point.

### Step 4 ([#935](https://github.com/mihaelamj/cupertino/issues/935)): end-to-end TDD scenario

**Removes edit-point #4 (the empirical-proof gap).**

**Pattern**: build a fake source (e.g. `FakeWWDCTranscripts`) with a fake corpus fixture (~3 JSON documents). Write an integration test that:

1. Constructs the full pipeline at a test composition root: fake descriptor + fake indexer + fake strategy.
2. Indexes the fixture corpus into an in-memory or `tmp`-dir search.db.
3. Asserts `Search.Index.search` returns the fixture documents for known queries.
4. Asserts the fake source's identity round-trips through descriptor lookup + the rank path.

**Critical proof**: the PR adding the fake source touches **zero** existing source concretes. The diff stat against the existing source surface is `+0 / -0`.

**Files touched**: new test files only.

**Estimate**: ~½ day if Steps 1-3 land cleanly.

**Unlock**: the "2-file PR" claim becomes empirically verified, not just architecturally plausible. The plan can be closed.

## Downstream polish (after critical path lands)

Not on the critical path; can land in any order, by anyone.

### Step 5: CLI surface generalisation

Replace per-source `@Flag`s on `cupertino save` (`--apple-docs`, `--samples`, `--hig`, etc.) with a single `--source <id>` `@Option(parsing: .upToNextOption)` that takes any registered source. Help text iterates the composition-rooted descriptor list. Same treatment for `cupertino fetch` and `cupertino cleanup`.

Files touched: CLI command files + per-option doc pages (`scripts/check-docs-commands-drift.sh` enforces these).

### Step 6: Source-name documentation auto-generation

Replace hardcoded source lists in `docs/commands/<cmd>/option (--)/source.md` with a generated page sourced from the composition-root descriptor list, or replace the list with "see `cupertino list-sources`".

## What the "2-file PR adds a new source" looks like after the critical path

```text
new package: Packages/Sources/WWDCTranscriptsSource/
  - WWDCTranscripts.SourceDescriptor.swift   (carries `Search.SourceDefinition`)
  - WWDCTranscripts.Indexer.swift            (the `Search.SourceIndexer` concrete)
  - WWDCTranscripts.Strategy.swift           (the `Search.SourceIndexingStrategy` concrete, optional)

edits to CLI composition root (1 file):
  - import WWDCTranscriptsSource
  - append `WWDCTranscripts.SourceDescriptor.descriptor` to the assembled `[Search.SourceDefinition]`
  - append `WWDCTranscripts.Indexer()` to the assembled `[any Search.SourceIndexer]`
  - append `WWDCTranscripts.Strategy()` to the assembled `[any Search.SourceIndexingStrategy]`
```

3 new files in a new package + 4-line edit to one CLI file. **Honest scope**: not literally "2 files" (Step 5's CLI generalisation gets it closer). But every edit is at the composition root: no existing source's code is touched, no closed enum is extended, no static dict is appended-to. That is the load-bearing claim.

## Exit criteria for closing this plan

- [ ] #932 merged (Step 1)
- [ ] #933 merged (Step 2)
- [ ] #934 merged (Step 3)
- [ ] #935 merged (Step 4): empirical proof landed
- [ ] `docs/research/pluggability-analysis-2026-05-22.md` updated with the post-Independence-Day measurement
- [ ] #919 closed with a summary comment quoting this plan's exit-state

When all 5 boxes are ticked, source pluggability is "100%" by the definition this plan opens with.
