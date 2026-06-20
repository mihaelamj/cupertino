# Design: Query-side source pluggability

| Field | Value |
|---|---|
| **Status** | draft |
| **Created** | 2026-06-20 |
| **Last revised** | 2026-06-20 |
| **Tracking issue** | [#1223](https://github.com/mihaelamj/cupertino/issues/1223) (declarative pluggability), parent [#919](https://github.com/mihaelamj/cupertino/issues/919) |
| **Target release** | release-after-next (not the next upcoming one) |
| **Companion docs** | `docs/plans/2026-05-22-source-independence-day.md` (index-side plan), `docs/design/per-source-db-split.md`, `docs/design/cupertino-data-engine.md` |

---

## TL;DR

cupertino's sources are pluggable on the **index/registry/bundle** side (a new source is a descriptor + an indexer concrete) but **not** on the **query** side. The MCP serve fan-out (`Services.UnifiedSearchService.searchAll`) hardcodes the eight sources as explicit `async let` calls; the source-identity model is split (a database/descriptor id `apple-documentation` vs a routing id `apple-docs`); and consumers (cupertino-desktop) therefore hardcode a source table to map cupertino's sources to their own model. This design makes the query path **registry-driven** so that *what cupertino reports (`list_sources`) == what it searches (`source: all`) == what `setup` ships* all derive from one source of truth, and it exposes **one source identity per source** so a consumer maps with zero hardcoding. Headline change: `searchAll` iterates the registry's active sources instead of a hardcoded `async let` block, and `list_sources` carries each source's routing id. Target: the release after the next upcoming one.

---

## 1. Context

### 1.1 The problem

"Source Independence Day" (#919) made adding a content source a 2-file PR on the **producer** side. But the **query** side still has central edit-points, surfaced empirically on 2026-06-20 while validating that cupertino-desktop honestly consumes the per-source databases:

- **#1286 (already fixed):** `cupertino serve` searched only 3 of 8 sources because it opened a single `searchIndex` over `apple-documentation.db`. Fixed by giving `UnifiedSearchService`/`DocsSearchService` a `docsIndexBySource` map. But the fix exposed the deeper gap below.
- **`searchAll` hardcodes the source set.** `Services.UnifiedSearchService.searchAll` issues an explicit `async let` per source (six `searchSource(source: <SourcePrefix literal>)` for docs + `searchSamples` + `searchPackagesBucket`). A ninth source would be reported by `list_sources`, shipped by `setup`, and opened by serve — but **silently not searched** under `source: all` until someone edits `searchAll`. That is precisely the failure class of #1286, one level up.
- **Two source-identity spaces.** A source has a database/descriptor id (`apple-documentation`, == filename stem) and a routing id (`apple-docs`, the `SourceDefinition.id` used in `search`/`list_documents`/`list_children`). `list_sources` emits the descriptor id; queries use the routing id. They differ for apple-docs and apple-sample-code (`samples`).
- **Consumers hardcode the source list.** Because the two identities aren't both exposed, cupertino-desktop's `Backend.LocalSubprocess` carries a hardcoded `databaseMapping` of filenames → its `Model.Source`. Adding a source means editing the desktop too.

### 1.2 Why the obvious approaches don't work

- *Leave it hardcoded* — violates the #919 axiom (a new source must touch no central switch) and reproduces the #1286 silent-drop bug whenever a source is added.
- *Per-source MCP tools* (`wwdc_search`, …) — surface explosion; clients would hardcode the tool set instead of the source set.

### 1.3 Why now

The per-source-DB split (#1036) is the reason the query side is now the weakest link: pre-split, one `search.db` made "search everything" trivially correct. Post-split, "search everything" must enumerate the sources, and that enumeration is currently a hardcoded list that can silently diverge from the registry. The embedded engine (`CupertinoDataEngine`) already solved this correctly (its unified `search` iterates `orderedSourceReaders()`); serve and the consumers have not caught up.

---

## 2. Goals

### P0
- **G1**: `source: all` searches exactly the registry's active sources, derived at runtime — adding a source adds it to the fan-out with **zero edits** to `searchAll`. Verified by an end-to-end fake-source test (the #935 pattern): registering a fake source makes it appear in `list_sources`, be searched by `source: all`, and be bundled, with no central-switch edit.
- **G2**: One source identity, exposed once. `list_sources` carries both the descriptor id and the routing `sourceID`, so a consumer maps a cupertino source to its own model **without a hardcoded correspondence table**. Verified: cupertino-desktop drops its `databaseMapping`/`source(forID:)` hardcoding and maps purely by `sourceID`.
- **G3**: The invariant *reported == searched == shipped* holds by construction (all three read the production source registry). Verified by a guard test that the `list_sources` id set, the `searchAll` searched set, and `bundleRequiredDescriptors()` are identical.

### P1
- **G4**: cupertino-desktop consumes the source set + identity from cupertino (Mac via `list_sources`) and from the embedded engine registry (iOS), with no hardcoded source list on either path.
- **G5**: The pre-UI startup setup-check (launch → `Backend.setupStatus()` → route) is well-defined per platform. *(Owner TBD per cross-Mac coordination — see §16; the backend seam this depends on is in scope here.)*

### P2
- **G6**: CLI `cupertino save --<source>` flags and the `docs/commands/.../source.md` pages derive their source list from the registry (the index-side polish items #5/#6 in the source-independence plan).

---

## 3. Non-goals

- **NG1**: Adding new content sources (WWDC #58, Swift Forums #89, Tech Talks #273). *This design makes adding them cheap; it does not add them.*
- **NG2**: The index/producer-side edit-points (`IndexerRegistry` dict, `makeDefaultStrategies`, `SourceRegistry.all`). *Owned by the existing `docs/plans/2026-05-22-source-independence-day.md` (#932–#935); this doc is the query-side complement.*
- **NG3**: The desktop UI itself (views, navigation). *Only the Backend seam + the pre-UI routing decision are in scope.*
- **NG4**: Re-ranking / fusion algorithm changes. *The fusion math is unchanged; only the set of inputs becomes dynamic.*

---

## 4. Requirements

### 4.1 Functional

| ID | Requirement | Verified by |
|---|---|---|
| F1 | `UnifiedSearchService.searchAll` enumerates sources from the injected registry-derived set, not literals | new `Issue<NNN>SearchAllRegistryDrivenTests` (fake source is searched) |
| F2 | `list_sources` rows carry `sourceID` (routing) + `id` (descriptor) + `filename` + `present` + `schemaVersion` | extend `Issue1277ListSourcesToolTests` |
| F3 | `searchAll` searched-id set == `list_sources` id set == `bundleRequiredDescriptors()` set | new invariant guard test |
| F4 | cupertino-desktop maps a source via `sourceID` only; no `databaseMapping` literal | desktop test: drop `databaseMapping`, map from `list_sources` |
| F5 | iOS `LocalEmbedded` reports `.catalogNotInstalled`/`.ready` from `engine.sourceIDs` | desktop `LocalEmbedded` setupStatus test |

### 4.2 Non-functional

| ID | Requirement | Target | Current state |
|---|---|---|---|
| N1 | Adding a source: files touched on the query path | 0 (registry append only) | `searchAll` + desktop `databaseMapping` = 2 edit-points |
| N2 | serve startup cost of opening N per-source DBs read-only | unchanged (already opens all per #1286) | all docs DBs opened read-only at serve start |

---

## 5. Design Overview

One registry (`makeProductionSourceRegistry().allEnabled`) is the single source of truth. Three consumers read it instead of hardcoding: the inventory (`list_sources`), the unified fan-out (`searchAll`), and the bundle (`setup`). Each source carries one identity record exposed to clients.

```
                 makeProductionSourceRegistry().allEnabled
                 (provider: definition.id=routing, destinationDB=descriptor, searchRoute)
                              |
        ┌─────────────────────┼──────────────────────────┐
        v                     v                           v
  list_sources          searchAll (source: all)       setup / bundle
  (inventory:           (fan out over the SAME         (extract the SAME
   id + sourceID +       active set, route each via     descriptor set)
   filename + present)   provider.searchRoute,
                         RRF-fuse)
        |                     |
        v                     v
  cupertino-desktop maps by sourceID (Mac) / engine.sourceIDs (iOS) — no hardcode
```

---

## 6. Detailed Design

### 6.1 Registry-driven `searchAll`

*Goal: the unified fan-out searches the registry's active sources, not a literal list.*

*Input:* the query + the per-source readers serve already builds (`docsIndexBySource`, `sampleDatabase`, `packagesSearcher`), plus each provider's `searchRoute` (already wired into `CompositeToolProvider.searchToolRoutesByID`).

*Output:* the same `Services.Formatter.Unified.Input` bucketed result, but bucketed over a dynamic set.

*Body:* replace the eight explicit `async let`s with an iteration over the active sources. Each source's `searchRoute` (`.docs` / `.hig` / `.samples` / `.packages` / future) decides which reader/bucket it goes to — the same dispatch `CompositeToolProvider.handleSearch` already uses for the single-source path. The result buckets become a `[sourceID: [Search.Result]]` map the formatter renders, rather than the fixed `docResults/higResults/...` fields. (The formatter's fixed fields are the second hardcode to dissolve; see §6.3.)

The embedded engine is the reference implementation: `CupertinoDataEngine.search(source: nil)` already does `for (id, reader) in orderedSourceReaders() { ... }` + `fuseResults`. serve's `searchAll` should converge to the same shape.

### 6.2 The source-identity record + `list_sources`

*Goal: expose one identity per source so consumers never hardcode.*

`Search.SourceInventoryItem` gains `sourceID` (the routing id = `provider.definition.id`), keeping `id` (descriptor) + `filename` + `present` + `schemaVersion`. `CLIImpl.activeSourceInventory` iterates `allEnabled` providers (not just `destinationDB` descriptors) so each row carries both ids. (This is the change that was prototyped and reverted on 2026-06-20 pending this design.) Empirically, `provider.definition.id` equals the desktop's `Model.Source.scheme` for all eight sources (including `samples`), so the desktop maps by `sourceID` with no correspondence table.

### 6.3 The unified formatter input

*Goal: stop the formatter from hardcoding one field per source.*

`Services.Formatter.Unified.Input` currently has fixed `docResults`, `higResults`, `swiftEvolutionResults`, … fields. A registry-driven fan-out produces a `[sourceID: bucket]` map; the formatter iterates it (using `displayName`/emoji from the registry) instead of naming each field. This is the change that lets a new source render with no formatter edit.

### 6.4 Consumer mapping (cupertino-desktop)

*Mac:* `Backend.LocalSubprocess.listSources()`/`setupStatus()` call `list_sources`, map each present row by `sourceID` → `Model.Source(rawValue:)` (scheme match), and drop `databaseMapping` (kept only, if at all, as a last-resort offline fallback). `setupStatus` needs only the counts (`installed`/`expected`) — no mapping.

*iOS:* `Backend.LocalEmbedded` already lists via `engine.sourceIDs`; add a `setupStatus()` override returning `.catalogNotInstalled` when the engine has no readable sources, `.ready` otherwise.

*Pre-UI:* on launch, the presentation layer calls `Backend.setupStatus()` and routes: Mac CLI-absent → install-cupertino prompt (`.cliNotInstalled`); Mac CLI-present but partial → `cupertino setup` prompt (`.needsSetup`); iOS no catalog → in-app download (`.catalogNotInstalled`); else → browser. *(Owner TBD per coordination — §16.)*

---

## 8. Algorithms / Protocols

RRF fusion is unchanged; only the input set becomes dynamic. The one subtlety: per-source RRF weights (`makeSmartQuerySourceWeights`) must be keyed by `sourceID` and default sensibly for a source with no declared weight, so a newly-registered source fuses with a neutral weight rather than being dropped or dominating.

---

## 10. Reliability & Failure Modes

| Failure mode | Detection | Mitigation |
|---|---|---|
| A registered source has no per-source DB on disk | `present == false` in the inventory; reader open fails | source contributes nothing (empty bucket), reported as degraded; the rest of the fan-out is unaffected (already the #1286 behavior) |
| A source's `searchRoute` has no handler | dispatch falls through to `.unified` | log + skip that source's bucket; guard test that every active source's route resolves |
| `list_sources` consumed by an older client without `sourceID` | field absent | additive field; older clients ignore it, desktop keeps a scheme-match fallback for one release |
| Registry and bundle drift (source registered but not shipped) | F3 invariant guard fails in CI | the guard test blocks the drift |

---

## 13. Testing Strategy

- **Unit:** `searchAll` over a stub registry of 2 fake sources returns both buckets (registry-driven, not literal).
- **Integration (hermetic):** the #935-style fake-source end-to-end — register a fake source via the composition root, assert it appears in `list_sources`, is searched by `source: all`, and is in `bundleRequiredDescriptors()`, with a grep guard that `searchAll` contains no per-source literal.
- **Invariant guard (CI):** `Set(list_sources ids) == Set(searchAll searched ids) == Set(bundleRequiredDescriptors ids)`.
- **Desktop:** `LocalSubprocess` maps from a `list_sources` fixture by `sourceID` (no `databaseMapping`); `LocalEmbedded.setupStatus` from `engine.sourceIDs`.

---

## 14. Rollout & Migration

- **Sequencing (target: release-after-next):**
  1. cupertino: add `sourceID` to `list_sources` (additive, ships first; desktop can consume once released).
  2. cupertino: registry-drive `searchAll` + the formatter input map (behind the existing per-source readers; no wire change).
  3. cupertino-desktop: consume `sourceID`, drop `databaseMapping`; add iOS `LocalEmbedded.setupStatus`.
  4. Prove with the fake-source end-to-end test; then the index-side polish (G6).
- **Backward compatibility:** `sourceID` is additive to the `list_sources` JSON; the desktop keeps a scheme-match fallback for one release so a desktop built against new cupertino still works against an older installed binary.
- **No schema bump** (no DB change). The `databaseVersion` is untouched.

---

## 15. Alternatives Considered

### 15.1 Keep `searchAll` hardcoded
**Considered:** leave the eight `async let`s; just keep them in sync by hand.
**Rejected:** reproduces the #1286 silent-drop bug for every future source; violates the #919 axiom.
**Cost paid:** none given up; this is the status quo we're removing.

### 15.2 Per-source MCP tools
**Considered:** one tool family per source (`wwdc_search`, `wwdc_read`, …).
**Rejected:** MCP surface explosion; clients hardcode the tool set; "search everything" becomes a client-side fan-out.
**Cost paid:** loses the (illusory) per-source customizability of bespoke tools.

### 15.3 Desktop maps the two oddball descriptor ids
**Considered:** desktop hardcodes `apple-documentation→appleDocs`, `apple-sample-code→samples`; other six match by scheme.
**Rejected:** the user's explicit steer — the consumer should ask cupertino, not hardcode; a 2-entry table still drifts when a source is added.
**Cost paid:** the `sourceID` approach needs a cupertino release before the Mac app benefits (accepted).

### 15.4 Make `Model.Source` exactly cupertino's id space
**Considered:** drop the desktop's parallel `Model.Source` and use cupertino's source ids verbatim.
**Rejected (for now):** larger desktop-domain refactor; out of scope. `Model.Source` is already open (`rawValue`-based), so `sourceID` mapping is enough.
**Cost paid:** a thin mapping layer remains in the desktop (acceptable, and it's by `sourceID`, not hardcoded).

---

## 16. Open Questions & Risks

### Open

| ID | Question | Tracking |
|---|---|---|
| Q1 | Who wires the pre-UI startup setup-check — the Studio (desktop) agent, or this design? | cross-Mac coordination (`.agent-handoffs/1286-…md`); G5 |
| Q2 | Does the `searchRoute` enum already cover every active source, or does a source without an explicit route need a default bucket? | verify against `CompositeToolProvider.searchToolRoutesByID` |
| Q3 | Should `sourceID` replace `id` in the CLI `list-sources` text output, or appear alongside? | minor; decide at impl |

### Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Dissolving the formatter's fixed per-source fields touches a lot of call sites | med | med | do it in a dedicated step with the formatter's existing tests as the guard |
| R2 | A cupertino release is needed before the desktop sees `sourceID` | high | low | additive field + desktop scheme-match fallback for one release |
| R3 | RRF weight defaulting for an unweighted new source skews ranking | low | med | neutral default weight + an eval check when a real new source lands |

---

## 17. Future Work

- Adding the first real new source (WWDC transcripts #58) is the acceptance demonstration of this design — do it immediately after, as the proof.
- Fold the index-side polish (CLI `--<source>` flags, doc `source.md` pages) into the same registry derivation (G6).

---

## 19. References

### Internal
- `docs/plans/2026-05-22-source-independence-day.md`: the index/producer-side plan (#932–#935); this doc is its query-side complement.
- `docs/design/per-source-db-split.md`: why each source is its own DB (#1036).
- `docs/design/cupertino-data-engine.md`: the embedded engine whose `search` is the registry-driven reference implementation.
- `docs/PRINCIPLES.md`: source-independence axiom (CLAUDE.md "Source Independence Day").

### Roadmap
- [#1223](https://github.com/mihaelamj/cupertino/issues/1223): epic — declarative pluggability (parent of this design).
- [#919](https://github.com/mihaelamj/cupertino/issues/919): epic — declarative source + DB pluggability.
- [#1286](https://github.com/mihaelamj/cupertino/issues/1286): the serve fan-out fix that surfaced this (shipped).
- [#935](https://github.com/mihaelamj/cupertino/issues/935): the end-to-end fake-source 2-file-PR proof (pattern reused for G1).
