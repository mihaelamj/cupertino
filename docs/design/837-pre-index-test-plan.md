# Design: Pre-Index Test Plan for #837 — Don't Burn Indexing Cycles on Broken Code

## Status (2026-05-20)

Draft. Companion to `docs/design/per-db-enrichment.md` (what each DB
gets enriched with) and `docs/design/post-processor.md` (how the
pipeline is structured). This doc decides *how we prove the code is
right before we run a real save*. Written from first principles —
every load-bearing term is defined before it is used.

---

## 0. What cupertino is, in one paragraph

cupertino is a command-line tool installed via Homebrew (`brew
install cupertino`). It downloads a large pre-built SQLite database
bundle once (~5 GB across three files), then runs locally as a fast
full-text index of Apple's developer documentation. Its primary
consumer is the cupertino MCP (Model Context Protocol) server,
which lets AI coding assistants (Claude, Cursor, etc.) query Apple
docs offline at single-digit-millisecond latency rather than guess
from training data that's months out of date and frequently wrong.
The promise the bundle makes to the assistant is "the answer you
give the user comes from real Apple documentation, not from a
hallucination."

That promise is only as good as the bundle. If the bundle's index
doesn't surface the right doc for a given query, the assistant
falls back to guessing and the cupertino layer adds no value. The
whole motivation for #837 — the change this test plan is gating —
is to improve what fraction of queries land on the right doc.

---

## 1. What cupertino ships

The Homebrew formula installs one binary called `cupertino`. The
binary alone does nothing useful; it knows how to query an index
but has no data. The user runs `cupertino setup` once, which
downloads three SQLite files from
`github.com/mihaelamj/cupertino-docs/releases/download/v<version>/cupertino-databases-v<version>.zip`
and unpacks them into `~/.cupertino/`. Those three files are the
ENTIRE shipped corpus.

The bundle versioning is independent from the binary versioning;
the binary's `Shared.Constants.App.databaseVersion` constant tells
`cupertino setup` which bundle to download. v1.1.0 binaries
download `cupertino-databases-v1.1.0.zip`; v1.2.0 binaries will
download `cupertino-databases-v1.2.0.zip` once it's published.

If the bundle has bugs, every user who runs `cupertino setup`
ships those bugs to their AI assistant. The bundle is hard to
recall once distributed.

---

## 2. The three SQLite files and what each holds

Each of the three files is a separate SQLite database. They are
queried independently by different `cupertino` subcommands. They
share no transactional context.

| File | Primary table | What a row represents | Approx. size | Built by |
|---|---|---|---|---|
| `search.db` | `docs_metadata` (+ `doc_symbols`) | One Apple documentation page (HIG section, framework reference, etc.) + its extracted symbol declarations | ~2.7 GB | `cupertino save --docs` (≈12 hours) |
| `samples.db` | `projects` (+ `files` + `file_symbols`) | One Apple sample-code project (e.g. an Xcode-downloadable demo app) + each of its `.swift` files + each declared symbol | ~160 KB metadata + extracted symbols | `cupertino save --samples` (≈minutes) |
| `packages.db` | `package_metadata` (+ `package_files` + `package_symbols` — added in #837) | One open-source Swift Package Manager package on GitHub + each of its files + each declared symbol | ~943 MB | `cupertino save --packages` (≈minutes) |

`search.db` is the headline. `samples.db` and `packages.db` are
secondary indexes the user explicitly opts into with separate CLI
flags. Pre-#837, only `search.db` had per-symbol semantic
annotation; the other two carried text only.

---

## 3. What "enrichment" means, in plain terms

When the indexer first walks a Swift file, it can extract the
*literal* text of each symbol declaration:

```swift
struct Picker<Label, SelectionValue, Content> { ... }
```

The extractor sees the names `Label`, `SelectionValue`, `Content`.
It does NOT see what each one is constrained to be — Apple's
public source code declares those constraints elsewhere
(usually in a `.swiftmodule` header inside the SDK, or in the
authoritative SwiftUI source). The literal text of the declaration
above does not say `Label: View` even though that's the truth.

"Enrichment" is the second pass over the database that annotates
each symbol row with that authoritative truth. After enrichment,
the row for `Picker` carries:

```
generic_constraints = "View,Hashable,View"
```

meaning Picker's three generic parameters are constrained to those
three protocols. The literal source text didn't say this; the
authoritative table did.

The reason this matters: when an AI coding assistant searches for
"a SwiftUI view that picks an item", the query is constraint-shaped
("View"), not name-shaped ("Picker"). Without enrichment, no rank
signal connects "View" to `Picker`'s row. With enrichment, the
constraint column carries "View" and the FTS5 ranker matches.

The same logic applies to samples (a sample showing `NavigationLink`
should surface for queries about destination views) and packages
(a SwiftPM package that imports `Combine` should surface for queries
about reactive Apple-platform helpers).

---

## 4. Where the constraint data physically comes from

There is a separate Swift Package living next to cupertino on
disk:

```
/Volumes/Code/DeveloperExt/public/cupertino-symbolgraphs/
```

It is its own repo at `github.com/mihaelamj/cupertino-symbolgraphs`.
Its sole product is a binary called `cupertino-symbolgraphs-gen`
which:

1. shells out to `xcrun swift symbolgraph-extract` for every Apple
   framework slug present in cupertino's documentation corpus
   (SwiftUI, UIKit, Combine, Foundation, … ~225 frameworks);
2. parses each `.symbols.json` output to extract every public
   type's generic-constraint clause;
3. emits one JSON file — `apple-constraints.json` — keyed by a
   URI derived from each type's Apple-docs path (e.g.
   `apple-docs://swiftui/picker` → `["View","Hashable","View"]`);
4. publishes that JSON as a GitHub Release artifact pinned to the
   active Swift version (currently `v0.1.1`).

When `cupertino save` runs on the operator's machine, it loads
`apple-constraints.json` from the same directory the target DB
lives in, materialises it into an `AppleConstraintsKit.Table`
object (which conforms to the `Search.StaticConstraintsLookup`
protocol), and passes it into the indexer. Each enrichment pass
asks the table "is there an entry for this docURI?" and if so
writes the constraints array to the row.

If the JSON file is absent on the operator's machine the
enrichment is silently skipped — the bundle still builds; it just
doesn't carry the constraint annotations.

---

## 5. What a successful enrichment write looks like, at the SQL level

Concrete example, samples.db. Before the
`samples-apple-constraints` pass runs:

```
sqlite> SELECT name, generic_constraints, enrichment_version FROM file_symbols WHERE name = 'Picker' LIMIT 1;
Picker|<NULL>|<NULL>
```

After the pass runs (lookup contains
`apple-docs://swiftui/picker → ["View","Hashable","View"]`):

```
sqlite> SELECT name, generic_constraints, enrichment_version FROM file_symbols WHERE name = 'Picker' LIMIT 1;
Picker|View,Hashable,View|1
```

The two newly-populated columns are exactly what the test plan
verifies. `enrichment_version = 1` records which pass version
wrote the row, so a future pass that uses a different lookup format
can detect already-enriched rows without scanning every value.

For packages.db's `apple_imports_json` column the shape is
different — it's a JSON array of module names rather than a
constraint list:

```
sqlite> SELECT owner||'/'||repo, apple_imports_json FROM package_metadata WHERE id = 1;
pointfreeco/swift-composable-architecture|["combine","swiftui"]
```

That column lets a future query filter packages by which Apple
frameworks they touch ("show me SwiftUI helpers"), again a signal
that wasn't surface-discoverable from the existing file-content
FTS index.

---

## 6. What the user actually experiences

The same query, asked of an AI assistant, against the same
question:

> "How do I make a navigation flow where the destination view
>  depends on a runtime selection?"

| Bundle state | Search lands on… | What the assistant tells the user |
|---|---|---|
| No enrichment | Three middling matches, none of which is `NavigationLink` — its row's text says "init(value:label:)" with no mention of "destination view" | "I'm not sure, here's a guess based on training data…" (likely outdated SwiftUI 3 API) |
| With enrichment | `NavigationLink`'s row's `generic_constraints` carries `"View"` so the query "destination view" matches and `NavigationLink` ranks #1 | "Use NavigationLink with a Destination view; here's the current SwiftUI 5 signature…" (verbatim from the actual Apple doc page) |

That delta is the entire user-visible benefit of #837. If the
enrichment column is NULL after a save, the bundle ships zero of
that benefit. If the column is populated but with wrong values,
the bundle ships *worse* rankings than no enrichment at all.

---

## 7. Why this document exists

Three relevant cost numbers:

| Operation | Wall-clock cost on the Studio |
|---|---|
| Run one xcrun swift test against a synthetic fixture | ~0.05 s |
| Run `cupertino save --samples` against the full sample-code corpus (~330 projects, ~33k Swift files) | ~5-15 min |
| Run `cupertino save --packages` against the full SwiftPM corpus (~183 packages, ~20 k files) | ~10-30 min |
| Run `cupertino save --docs` against the full Apple-docs corpus (~414 k pages) | ~12 hours |
| Build the binary release artifact + upload bundle zip + bump Homebrew formula | ~30 min hands-on + 1-2 h cert/audit |
| Recall a bad bundle once 200 brew users have run `cupertino setup` against it | not actually possible; users have to manually `cupertino setup` again |

The implication: catching one bug at the unit-test layer costs
0.05 s. Catching the same bug after the 12-hour `--docs` save
costs 12 hours plus the operator's morning. Catching it after a
brew release ships costs the user community their next
`cupertino setup`.

Every test in §9 below is calibrated to that ratio. If running the
unit test would catch a bug that would otherwise surface only
after a real save, the unit test is worth writing.

---

## 8. What "immaculate" means here, precisely

A pre-index code state is immaculate when every one of the
following is true. "Immaculate" is binary; if any one is missing,
we do NOT run a real save against real data.

1. **Schema migrations land on the version the binary expects.**
   Open a v3 packages.db with the v1.2.0 binary; the binary reads
   `PRAGMA user_version`, sees `3`, runs the in-place ALTER
   migration to v4, and a subsequent `PRAGMA user_version` reads
   `4`. No `Search.Error.schemaVersionMismatch` thrown. Same for
   samples.db's wipe-and-rebuild path.

2. **Every new public method on the enrichment path is unit-tested
   for at least one happy-path case AND one no-op case.** The
   happy-path test asserts that a known row goes from NULL to a
   specific value after the pass runs. The no-op test asserts
   that nil/empty inputs leave rows untouched.

3. **Every new `EnrichmentPass` is tested for protocol shape.**
   `identifier` matches the agreed string. `target` is the right
   `.search` / `.samples` / `.packages` enum case. `dependsOn`
   is the expected list. `run(database:)` returns a
   `EnrichmentModels.Result` whose `passIdentifier` matches the
   pass and whose `rowsAffected` matches the underlying
   method's return value.

4. **The composition-root path is exercised by an integration
   test.** This test constructs the `Enrichment.LiveRunner` with
   the same pass set the production binary constructs, runs it
   against a synthetic DB seeded with one row, and asserts the
   row was written. This catches wiring bugs (wrong pass
   registered, wrong target enum, wrong order) that pure unit
   tests miss.

5. **A mini-corpus end-to-end run produces the expected per-row
   writes against real-shape data.** This is the `--samples`
   equivalent of #794's `scripts/check-pre-index.sh` (which
   already covers `--docs`). A one-project / one-file / one-symbol
   fixture runs through the entire `cupertino save --samples`
   path and is queried with sqlite3 to confirm
   `file_symbols.generic_constraints` was populated.

6. **The full test suite is green.** `xcrun swift test` exits 0
   with at least 2367 tests across at least 336 suites. Every
   new test is additive; we never delete a test to make the gate
   pass.

---

## 9. Per-DB test plan

### 9.1 The mini-corpus principle

We do NOT need 330 sample projects to verify enrichment writes
correctly. We need one synthetic project that exercises:

- one Swift file with one declared symbol whose name matches an
  entry in `apple-constraints.json`'s lookup. The smallest
  meaningful fixture is one `struct Picker` declaration.

That one fixture proves the entire write path end-to-end. Whether
the path scales to 330 projects is a separate concern handled by
the existing concurrency tests and the `scripts/setup-mini-corpus.sh`
gate (#779 / #794). The pre-index gate this doc covers is
correctness of the new write, not throughput.

Same principle for packages.db: one synthetic package with one
Swift file and one declared symbol covers the constraint-application
path; one synthetic package with three module names in
`package_files` (one Apple, one Apple, one not) covers the
apple-imports-aggregation path.

### 9.2 samples.db — constraint application

**Code under test:**

- `Sample.Index.Database.applyAppleStaticConstraints(lookup:enrichmentVersion:)`
  in `Packages/Sources/SampleIndex/Sample.Index.Database.swift`.
- `Enrichment.SamplesAppleConstraintsPass` in
  `Packages/Sources/Enrichment/Enrichment.SamplesAppleConstraintsPass.swift`.

**Fixture:** a fresh in-memory `Sample.Index.Database` seeded
with one project (`id = "test"`), one Swift file
(`Sources/Foo.swift`), one symbol (`name = "Picker"`,
`kind = .structDecl`).

**Cases. Every case below has a "why" that ties it back to a real
failure mode the production save would have hit:**

| # | Input | Expected DB state | Why this case is in the gate |
|---|---|---|---|
| s1 | lookup = `[apple-docs://swiftui/picker → ["View","Hashable"]]`, version = 1 | row's `generic_constraints` = `"View,Hashable"`, `enrichment_version` = 1, return value = 1 | proves the happy-path write actually fires; without this the bundle ships every row NULL and the user gets zero benefit |
| s2 | lookup = nil, version = 1 | row unchanged (`generic_constraints` NULL, `enrichment_version` NULL), return value = 0 | proves the missing-`apple-constraints.json` operator scenario is graceful — no crash, no half-applied write |
| s3 | lookup = empty array | row unchanged, return value = 0 | proves the bounds case; protects against a future zero-entry table |
| s4 | lookup has entries but none match the symbol's name | row unchanged, return value = 0 | proves rows for non-Apple types aren't corrupted by unrelated lookup entries |
| s5 | run case s1 twice in succession | second run reports the same row-count (SQLite UPDATE-on-same-value still counts the row as changed), final values match the first run | documents idempotency: re-running the pass against the same DB at the same version is safe |
| s6 | symbol name = `NAVIGATIONLINK` (all caps), lookup URI = `apple-docs://swiftui/navigationlink` (lowercase) | match still fires, row gets written | proves the case-folding inside `WHERE LOWER(name) = ?` — real Apple types are capitalized in source but URI segments are lowercased by Apple's pathComponents convention |

**Test file location:**
`Packages/Tests/SampleIndexTests/Issue837SamplesAppleStaticConstraintsTests.swift`.

### 9.3 packages.db — constraint application

**Code under test:**

- `Search.PackageIndex.applyAppleStaticConstraints(lookup:enrichmentVersion:)`
  in `Packages/Sources/Search/PackageIndex.swift`.
- `Enrichment.PackagesAppleConstraintsPass` in
  `Packages/Sources/Enrichment/Enrichment.PackagesAppleConstraintsPass.swift`.

**Fixture:** a fresh `Search.PackageIndex` seeded with one
package (`package_metadata` row with id = 1), one file
(`package_files` row), one symbol (`package_symbols` row with
`name = "Picker"`).

**Cases:** identical structure to §9.2 cases s1-s6, against
`package_symbols` instead of `file_symbols`. Identifiers p1-p6.

**Why a parallel set isn't redundant:** the SQL is written
separately in two files. If `applyAppleStaticConstraints` on
`PackageIndex` ever diverges from the samples version (different
column name, different binding offset, different transaction
boundaries), only running the parallel set catches it. The cost is
six tiny tests; the benefit is catching a class of bug we've
already seen elsewhere in the codebase.

**Test file:**
`Packages/Tests/SearchTests/Issue837PackagesAppleStaticConstraintsTests.swift`.

### 9.4 packages.db — apple-imports aggregation

**Code under test:**

- `Search.PackageIndex.applyAppleImports(lookup:enrichmentVersion:)`.
- `Enrichment.PackagesAppleImportsPass`.

**Fixture:** one package row (id = 1); three rows in
`package_files` for that package:
- `module = "SwiftUI"` (Apple)
- `module = "Combine"` (Apple)
- `module = "ThirdPartyHelper"` (not Apple)

**Cases:**

| # | Input | Expected | Why |
|---|---|---|---|
| i1 | lookup has entries whose docURIs start with `apple-docs://swiftui/` and `apple-docs://combine/` | row 1's `apple_imports_json` = `["combine","swiftui"]` (sorted, lowercased), `enrichment_version` = 1, return = 1 | the headline feature: this is what makes `cupertino package-search --apple-imports SwiftUI` filterable in a follow-up CLI iteration |
| i2 | lookup = nil | row 1's `apple_imports_json` stays NULL, return = 0 | matches the missing-JSON-file operator scenario |
| i3 | lookup non-empty but package has no Apple imports | row 1 stays NULL, return = 0 | proves the per-package scoping doesn't bleed |
| i4 | second package whose only file's module is `ThirdPartyHelper` | that row's `apple_imports_json` stays NULL even on a fresh run | proves a package with zero Apple imports does not get spurious `[]` JSON written; NULL means "untouched", `[]` would mean "explicitly checked and found nothing" |
| i5 | `package_files` rows with `module = NULL` mixed in (real corpora have these for README / images / Package.resolved) | NULL modules are ignored, no crash, no spurious entries in JSON, no transaction abort | proves the SQL `WHERE module IS NOT NULL AND module != ''` filter |

**Test file:**
`Packages/Tests/SearchTests/Issue837PackagesAppleImportsTests.swift`.

### 9.5 AST extraction round-trip (packages.db)

The AST extraction path in `Search.PackageIndex.insertFile` already
landed (#844). It runs SwiftSyntax over every `.swift` file during
`cupertino save --packages` and writes per-symbol rows into
`package_symbols`.

**Cases:**

- Feed the literal string `import SwiftUI\nstruct MyView: View {
  var body: some View { Text("hello") } }` through
  `PackageIndex.insertFile`. Assert `package_symbols` ends up with a
  row whose `name = "MyView"`, `kind = "structDecl"`, `is_public = 0`.

**Why:** without this lock, a future SwiftSyntax library upgrade
could silently change the kind label (e.g. `structDecl` →
`struct`), the symbol name extraction (`MyView<T>` →
`MyView`), or skip declarations entirely. We'd only notice after
the real save populates `package_symbols` with the wrong shape,
which then propagates into the bundle.

**Test file:**
`Packages/Tests/SearchTests/Issue837PackageSymbolsExtractionTests.swift`.

### 9.6 Composition-root integration

Unit tests in §9.2-9.5 pin the methods + passes in isolation. None
of them prove the composition root in `CLIImpl.Command.Save.Indexers`
constructs the right pass set with the right lookup, in the right
order. That wiring is the place where real save runs would surface
bugs we can't catch from unit tests alone.

**Cases:**

- Construct an `Enrichment.LiveRunner` with the SAME passes the
  composition root constructs:
  - for samples: `[SamplesAppleConstraintsPass]`
  - for packages: `[PackagesAppleConstraintsPass,
    PackagesAppleImportsPass]`
- Run against a synthetic DB seeded with one row per relevant
  table.
- Assert the runner's returned `[Result]` array has the right
  length, the right `passIdentifier` per element, and the right
  `rowsAffected` per element.

**Test file:**
`Packages/Tests/EnrichmentTests/Issue837CompositionRootIntegrationTests.swift`.

### 9.7 Schema migration round-trip

Pin v3 → v4 migration for both DBs.

**packages.db v3 → v4 (in-place ALTER + CREATE TABLE):**

- Seed a v3 packages.db (no `apple_imports_json`, no
  `enrichment_version`, no `package_symbols` table); the existing
  v2→v3 test pattern in `Issue225SwiftToolsVersionIntegrationTests`
  is the template.
- Open the seeded DB with the v1.2.0 `Search.PackageIndex` actor.
- Assert: `PRAGMA user_version` is now `4`, the two new columns
  exist on `package_metadata`, `package_symbols` exists with the
  expected 16 columns + 4 indexes, original v3 rows are intact.
- Re-run the migration: idempotent (no errors, no double-creation).

**samples.db v3 → v4 (wipe-and-rebuild):**

- Seed a v3 samples.db.
- Open with v1.2.0; assert the wipe-and-rebuild policy ran (no v3
  data leftover, fresh tables at v4).
- Assert: `file_symbols.generic_constraints` and
  `file_symbols.enrichment_version` exist on the fresh schema.

**Why:** users who installed v1.1.0 and ran `cupertino setup`
have a v3 bundle on disk. When they `brew upgrade cupertino` and
the binary jumps to v1.2.0, the migration is what bridges them
without forcing a fresh `cupertino setup`. If the migration breaks,
brew users are stuck.

**Test files:**
- `Packages/Tests/SearchTests/Issue837PackagesV4MigrationTests.swift`
- `Packages/Tests/SampleIndexTests/Issue837SamplesV4MigrationTests.swift`

---

## 10. Acceptance gate

Before any operator types `cupertino save --samples` or
`cupertino save --packages` against the real Studio corpus to
produce the v1.2.0 bundle:

- [ ] All test files listed in §9.2-9.7 exist and are committed
  to main.
- [ ] `cd Packages && xcrun swift test` exits 0.
- [ ] Full-suite count is at or above the current 2367 tests /
  336 suites. Every new test is additive; no test was deleted to
  make the gate pass.
- [ ] `scripts/check-pre-index.sh` (the existing #794 gate that
  runs a 10%-mini-corpus end-to-end `--docs` save) is run and
  green. It re-verifies the search.db enrichment path; the new
  samples + packages paths are exercised by §9.2-§9.6 unit +
  integration tests.
- [ ] A human visually inspects the `before` and `after` row
  values of one fixture row from §9.2 (samples) and one from
  §9.3 (packages). The values printed by sqlite3 match the
  inputs the test fed in. This is the "did the test actually
  exercise what it claimed to" sanity-check.
- [ ] The branch's PR is in `mergeStateStatus: CLEAN` on GitHub.

Only after every box is checked do we run the real-corpus saves.

---

## 11. What this doc does NOT cover

- The full 12-hour `--docs` save. That's the eventual gate for
  search.db's enrichment writes; #514 already tracks the related
  WAL throughput measurement and was deferred to v1.3.x.
- The bundle assembly (zip file structure), the GitHub Release
  upload, the v1.2.0 git tag, the Homebrew formula bump in
  `mihaelamj/homebrew-tap`. Those are release-mechanics gated by
  a separate user "go", already covered by the existing
  release-prep workflow and the `docs/audits/release-readiness-v1.2.0.md`
  ship checklist.
- Search-quality re-measurement against the v1.2.0 bundle after
  enrichment lands. That's a follow-up Phase 1.9 audit (paired
  Wilcoxon / McNemar against the v1.2.0 pre-enrichment baseline),
  not part of the pre-index correctness gate this doc defines.

---

## 12. References

- `docs/design/per-db-enrichment.md` — what each DB gets.
- `docs/design/post-processor.md` — pipeline structure.
- `scripts/check-pre-index.sh` (#794) — the existing pre-flight
  script for `--docs`. This doc is the samples + packages
  counterpart.
- `docs/audits/release-readiness-v1.2.0.md` — full release-prep
  checklist that this gate plugs into.
- Tracking issues: #837 (umbrella), #847 (samples tests), #848
  (packages tests), #849 (migration tests).
