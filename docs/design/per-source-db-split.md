# Design: Per-Source DB Split (implementation arc)

## Status (2026-05-25)

Draft. Implementation companion to
`docs/design/corpus-structure.md` (the durable contract). This doc
is the *how* and *in-what-order*. corpus-structure is the *what*.

Goal: split the single `search.db` into 6 per-source DBs
(`apple-documentation.db`, `hig.db`, `apple-archive.db`,
`swift-evolution.db`, `swift-documentation.db`,
`apple-sample-code.db`, `swift-packages.db`), rename `samples.db` to
`apple-sample-code.db` and `packages.db` to `swift-packages.db`,
keep swift-book as a view-source co-located in
`swift-documentation.db`. User direction settled 2026-05-25.

---

## 1. Why split

| Maintenance gain | Today (one search.db) | After split |
|------------------|------------------------|-------------|
| Schema bump scope | Touches all sources' rows | Touches one DB |
| Reindex one source | Locks the shared DB | Independent file |
| Corruption blast radius | All sources | One source |
| `sqlite3 <db>` inspection | Needs `WHERE source = ...` everywhere | Already filtered |
| New source = one file | True for code, BUT new source adds rows to shared search.db | One source = one DB file |
| `cupertino setup --source X` | Not meaningful (shared DB) | Real: download just hig.db (~few MB) |

Trade-offs we accept:

- Cross-source `cupertino search "View"` becomes fan-out + merge in
  code instead of one FTS5 query. Code surface grows; per-query
  latency is comparable (we already query 7 sources' rows from one
  DB; we'll query 7 DBs of 1 source's rows each).
- FTS5 dictionaries don't share across DBs. Net disk growth is in
  the low MB, negligible against the ~2.7 GB apple-documentation DB
  dominating bundle size.
- `cupertino setup` ships 7 files instead of 1. Already a manifest
  + zip; the manifest grows from 3 entries to 7.

---

## 2. Architecture: before vs after

### 2.1 Today (post-#1007 source-unification)

```
                CLIImpl.makeProductionSourceRegistry()
                          ↓
              [SourceProvider, SourceProvider, ...]
                          ↓
      ┌───────────────────┴────────────────────┐
      │  destinationDB ∈ {.search, .packages}   │
      └───────────────────┬────────────────────┘
                          ↓
              ┌───────────┴────────────┐
              ↓                        ↓
        search.db                packages.db
   (6 sources writing,         (1 source)
    distinguished by
    `source` column)
                              samples.db
                              (1 source)
```

### 2.2 After this epic

```
                CLIImpl.makeProductionSourceRegistry()
                          ↓
              [SourceProvider, SourceProvider, ...]
                          ↓
              groupedByDestinationDB
                          ↓
   ┌────────┬────────┬────────┬────────┬────────┬────────┬────────┐
   ↓        ↓        ↓        ↓        ↓        ↓        ↓        ↓
apple-    hig.db  apple-   swift-   swift-   apple-   swift-
docu-             archive  evolu-   docu-    sample-  packages
mentation.db      .db      tion.db  mentation.db  code.db   .db
                                    (swift-org +
                                     swift-book
                                     view-source
                                     co-located)
```

Same provider count. Same indexer concretes. One extra dimension
of separation at the bundle + open-handle layer.

---

## 3. Migration order

Each step is a single commit on `feat/per-source-db-split`. The
suite stays green at every commit. Order matters; a later step
depends on earlier ones being in place.

### Step 1 (task #84): Add the new DatabaseDescriptor statics

`Packages/Sources/Shared/Models/Shared.Models.DatabaseDescriptor.swift`:

Add 5 new statics:
```swift
public static let appleDocumentation = DatabaseDescriptor(name: "apple-documentation", schemaVersion: 18)
public static let hig                = DatabaseDescriptor(name: "hig", schemaVersion: 18)
public static let appleArchive       = DatabaseDescriptor(name: "apple-archive", schemaVersion: 18)
public static let swiftEvolution     = DatabaseDescriptor(name: "swift-evolution", schemaVersion: 18)
public static let swiftDocumentation = DatabaseDescriptor(name: "swift-documentation", schemaVersion: 18)
```

Rename:
- `.samples` stays under the same Swift name but its `.name` field flips to `"apple-sample-code"` (file rename happens later in step 6 via the migration shim).
- `.packages` stays under the same Swift name but its `.name` field flips to `"swift-packages"`.

Keep `.search` alive as a deprecated alias for now. No source flips
to a new DB yet; this step only introduces the descriptors. Suite
green: every test still resolves `.search` and writes to search.db.

### Step 2 (task #90): Add CorpusManifest model + per-source YAML files

`Packages/Sources/Shared/Models/Shared.Models.CorpusManifest.swift`
(new): the Decodable Swift type matching the YAML schema in
`corpus-structure.md` §3. No Yams dependency yet (defer decision per
corpus-structure §8 open questions); for step 2 the manifests live
on disk as YAML but are NOT loaded by the binary. CI's
`check-source-manifests.sh` (new script) validates them against the
schema using shell + `yq`.

Add `docs/sources/<id>/manifest.yaml` for each of the 7 sources.
Each file is hand-written, reviewed in the PR. The capabilities
matrix from corpus-structure §3.5.6 is the source of truth for
what each manifest declares.

Step 2 is a docs-only commit. Suite green trivially.

### Step 3 (task #94): Capabilities-driven dispatcher (read-only consumption)

The CLI dispatcher learns to read the capabilities matrix from the
production registry (NOT from the YAML; the matrix mirrors into
each `SourceProvider`'s `capabilities` property as a hardcoded Swift
value matching the YAML, with CI cross-check). For each subcommand:

```swift
let required: Set<Search.Capability> = .symbolsSearch
let candidates = registry.allEnabled.filter {
    !required.isDisjoint(with: $0.capabilities.searchers)
}
```

Subcommand routing falls back to candidates' destinationDBs. At
this step the destinationDB is still `.search` for the 5 splittable
sources; the dispatcher works but fan-out is degenerate (one DB).
Suite green.

### Step 4 (task #86): Flip destinationDB, source by source

One commit per source. Order: smallest to largest, so a failure on
the first one is easy to inspect.

1. `swift-evolution` (smallest row count, easiest fixtures)
2. `apple-archive`
3. `hig`
4. `swift-documentation` (swift-org + swift-book via view-source)
5. `apple-documentation` (last, largest, most fixture surface)

For each: flip `destinationDB` in the `<X>Source.swift` definition,
re-run the per-source target shape pin tests (`Issue1008` through
`Issue1023`), re-run `Issue1033AllSourcesRoundtripTests`. The
roundtrip tests already iterate the registry, so they pick up the
flip automatically.

### Step 5 (task #85): IndexBuilder per-DB fan-out

`Search.IndexBuilder.buildIndex(strategies:env:)` learns to group
strategies by `provider.destinationDB`, open the matching DB once,
ingest all strategies for that DB, close. Sketch:

```swift
let grouped = Dictionary(grouping: strategies) { strategy in
    registry.entry(for: strategy.source)!.destinationDB
}

await withTaskGroup(of: Void.self) { group in
    for (descriptor, strategies) in grouped {
        group.addTask {
            let db = try await openDB(descriptor: descriptor)
            for strategy in strategies {
                try await ingest(strategy, into: db)
            }
            await db.disconnect()
        }
    }
}
```

Suite green per-source: each per-source target's shape pin asserts
the source writes to ITS DB now, not search.db.

### Step 6 (task #91): Migration shim for existing users

A user with an existing `~/.cupertino/search.db` from `cupertino
setup` v1.2.x has the old schema. On upgrade, the binary detects
the legacy DB and splits it once into 6 per-source DBs.

Shim runs in `cupertino setup` and `cupertino save` first-run flow:

1. Detect legacy `search.db` (filename + presence of multiple
   distinct `source` values in `docs_metadata`).
2. For each canonical source-id, open the legacy DB, `SELECT * WHERE
   source = ?`, write into the new `<id>.db` with the same schema.
3. Verify per-source row counts match.
4. Rename legacy `search.db` to `search.db.legacy-pre-per-source-split`
   (keep for one release; cleanup in v1.4.x).
5. Print a one-line summary per source: `[apple-documentation] split:
   379,124 rows -> apple-documentation.db (1.2 GB)`.

The migration is one-shot, idempotent (no-op if new DBs already
exist with the right schema version), reversible up to step 5.

### Step 7 (task #89): cupertino setup / doctor / search no-filter

`cupertino setup`: bundle manifest grows from 3 file entries to 7.
GitHub Releases ship 7 zips per release tag instead of 1. Download
order: smallest to largest so cancellation costs the user only
unfinished work. Manifest format change is forward-compatible (old
binaries reading the new manifest fail with a clear error pointing
at upgrading).

`cupertino doctor`: per-DB section repeats 7 times. Per-source
capability matrix displayed inline.

`cupertino search` (no `--source` filter): fan-out across all
search-capable DBs, merge results with the
`searchProperties.searchQuality` + `rankWeight` weights from each
DB's manifest. Verify against v1.2.0 baseline (MRR 0.9467).

### Step 8 (task #92): Tests

- Extend `Issue1033AllSourcesRoundtripTests`: the per-source
  roundtrip pin asserts the row lands in the PROVIDER'S DB, not in
  search.db.
- Add `PerDBSchemaStampGuard` tests mirroring the existing
  `Issue635SchemaStampGuard` pattern for samples + packages, but
  per-DB.
- Add a fan-out test asserting `cupertino search "View"` returns
  results from every search-capable source.
- Add a migration test against a synthetic legacy search.db fixture.

### Step 9 (task #93): Open PR back to develop, rebuild on Claw mini

Once all steps green locally:
1. Push branch (already done in step 1's commit).
2. Open PR `feat/per-source-db-split` -> develop. Single PR per
   user direction.
3. CI runs the full battery + the new fan-out + migration tests.
4. Rebuild on Claw mini (internal SSD only; ~12h overnight per
   memory) to produce the 7 bundle files.
5. Validate against v1.2.0 baseline.
6. Squash-merge to develop.

---

## 4. Per-DB schema policy

Each per-source DB carries a copy of the existing search.db schema
(v18 at split time): `docs_metadata` + FTS5 mirror + `doc_symbols` +
indexes. The `source` column stays for the view-source case
(swift-documentation distinguishes swift-org / swift-book rows by
URL prefix tag); for the 5 single-source DBs the column is
degenerate but kept for schema uniformity and so Issue1033
roundtrip tests survive without per-DB branching.

Post-split schema bumps proceed per-DB. A bump on
apple-documentation.db doesn't force a bump on hig.db. The schema
version table in each DB tracks its own version.

---

## 5. Query-time merge

`cupertino search "<query>"` (no `--source` filter):

1. Resolve query intent (heuristic: capital-letter run = symbol, all
   lowercase = prose, leading `SE-` = proposal, etc.).
2. Match intent to a set of capability-required searchers.
3. Filter registry by `capabilities.searchers`.
4. For each candidate provider, open its `destinationDB`, run the
   structured FTS5 query, collect ranked results.
5. Merge across DBs: normalize ranks within each DB's result set to
   [0, 1], scale by the source's `searchQuality` + `rankWeight`,
   sort the merged list, return top-k.

Latency budget: same as today's single-DB query because the per-DB
queries run in parallel. The merge step is a k-way sort of
~7 × 50 = 350 items, sub-millisecond.

---

## 6. Bundle layout (cupertino setup)

GitHub Releases per tag carry 7 zip files:

```
cupertino-bundle-v1.3.0-apple-documentation.db.zip   ~1.2 GB
cupertino-bundle-v1.3.0-hig.db.zip                    ~6 MB
cupertino-bundle-v1.3.0-apple-archive.db.zip          ~30 MB
cupertino-bundle-v1.3.0-swift-evolution.db.zip        ~12 MB
cupertino-bundle-v1.3.0-swift-documentation.db.zip    ~40 MB
cupertino-bundle-v1.3.0-apple-sample-code.db.zip      ~80 MB
cupertino-bundle-v1.3.0-swift-packages.db.zip         ~250 MB
```

Plus a `manifest.json` listing tag, per-DB checksums, schema
versions. `cupertino setup` downloads all 7 by default;
`cupertino setup --source X` downloads only X's DB.

---

## 7. Rollback

The PR is one PR. If something breaks after merge to develop, the
revert is one PR back. The migration shim's one-shot nature means a
user who has migrated past step 6 needs the kept `.legacy` file to
roll back; the shim print line tells them where it is.

Pre-merge: each commit on the branch is independently revertable.
The destinationDB flip per source (step 4) is the highest-risk
group of commits; if one source's flip breaks something, only that
commit reverts, not the whole branch.

---

## 8. Out of scope (deferred)

- Per-DB enrichment passes (`docs/design/per-db-enrichment.md` is
  the doc for that; depends on this epic landing).
- `cupertino diff` across snapshots (use git on the cupertino-docs
  corpus repo per `corpus-as-git-time-series` memory).
- Symmetric symbol extraction on packages.db (stage 2 in
  per-db-enrichment.md, v1.3.x or later).
- Vector / embedding DBs as a per-source addition (Mihaela's #183
  roadmap covers this; out of scope here).

---

## References

- Companion durable contract: `docs/design/corpus-structure.md`
- Output-shape spec: `docs/design/per-db-schema-spec.md`
- Enrichment design: `docs/design/per-db-enrichment.md`
- Memory: `cupertino-per-source-db-names-agreed`,
  `feedback_sources_100pct_pluggable`,
  `cupertino_file_based_db_invariant`,
  `cupertino_search_quality_baseline_v1_2_0`
- Pluggability rule: `mihaela-agents/Rules/swift/gof-di-rules.md`
- Tracking: this branch (`feat/per-source-db-split`); PR to be filed
  after step 8.
