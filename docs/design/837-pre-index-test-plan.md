# Design: Pre-Index Test Plan for #837 — Don't Burn Indexing Cycles on Broken Code

## Status (2026-05-20)

Draft. Companion to `docs/design/per-db-enrichment.md` (which decides
*what* each DB gets enriched with) and `docs/design/post-processor.md`
(which decides *how* the pipeline is structured). This doc decides
*how we prove the code is right before we run a real save*.

---

## 1. Why this document exists

`cupertino save --packages` and `cupertino save --samples` are long.
Packages, post-#837 AST extraction, walks every `.swift` file in every
package under `~/.cupertino-dev/packages/` and runs SwiftSyntax over
each one — minutes to tens of minutes against the production corpus.
A full `cupertino save --docs` is ~12 hours.

If we run any of those against a broken binary, we waste the run.
Every minute spent indexing against bad code is a minute we cannot
recover. The bundle is also large; uploading a wrong bundle to
`cupertino-docs/releases/` is reversible but embarrassing and the
download bandwidth is real.

The economic claim is simple:

> Catching one bug at the unit-test layer costs seconds.
> Catching the same bug after a 12-hour `--docs` run costs 12 hours.
> Catching it after a release upload costs the user community an
> aborted bundle download.

That ratio is why every behaviour the postprocessor pipeline
introduces gets pinned in tests against a synthetic fixture *first*,
before any real-corpus save touches the data.

---

## 2. What "immaculate" means here, precisely

A pre-index code state is immaculate when every one of the following
is true:

1. **Schema migrations land on a tagged version that the binary
   recognizes as current.** No `schemaVersionMismatch` at open time.
2. **Every public method added on the enrichment path has a unit
   test pinning its happy path AND at least one no-op branch.**
3. **Every public `EnrichmentPass` added has a unit test verifying
   its protocol shape** (`identifier`, `target`, `dependsOn`,
   `schemaVersion`, and that `run(database:)` returns a
   correctly-shaped `Result`).
4. **The composition-root path is exercised by an integration test
   that constructs the `LiveRunner` with the real passes against a
   synthetic DB and asserts the per-pass `Result` matches the direct
   method call.**
5. **A mini-corpus end-to-end run produces the expected per-row
   writes.** The real corpus is not yet touched.
6. **The full test suite is green** (`xcrun swift test` returns
   exit 0).

"Immaculate" is binary. If any one of the six is missing, we do not
run a real save.

---

## 3. The mini-corpus principle

A real `cupertino save --packages` against 183 packages takes tens of
minutes. We do not need 183 packages to verify the enrichment writes
are correct. We need **one synthetic package** that exercises:

- one Swift file with one symbol whose name matches an entry in the
  `AppleConstraintsKit.Table` lookup (e.g. `NavigationLink`,
  `Picker`), so the `package_symbols.generic_constraints` write path
  fires;
- one Swift file with one `import SwiftUI` plus one `import
  ThirdPartyHelper`, so the `apple_imports_json` path can verify it
  keeps SwiftUI and drops the third party.

Similarly for samples.db: a one-project, one-file, one-symbol fixture
covers everything the constraint-application path can hit.

The fixture lives in test code as inline string literals (not on
disk) so the test doesn't depend on file-system state.

---

## 4. Per-DB test plan

### 4.1 samples.db

**Subject under test:**

- `Sample.Index.Database.applyAppleStaticConstraints(lookup:enrichmentVersion:)`
  — public actor method, returns `Int` (affected-row count).
- `Enrichment.SamplesAppleConstraintsPass` — wraps the above.
- `LiveSamplesIndexingRunner.run(...)` (composition root) —
  constructs the runner and calls the pass after `builder.indexAll`.

**Fixture:**

- A fresh `Sample.Index.Database` at a tmp path.
- One project: `id = "test"`, one file `Sources/Foo.swift`, one
  symbol named `Picker` of kind `.structDecl`.

**Cases that must pass:**

| # | Input | Expected output |
|---|---|---|
| s1 | lookup has one entry with `docURI: "apple-docs://swiftui/picker"`, `constraints: ["View","Hashable"]` | row's `generic_constraints == "View,Hashable"`, `enrichment_version == 1`, method returns `1` |
| s2 | lookup is `nil` | row untouched (`generic_constraints IS NULL`), method returns `0` |
| s3 | lookup has zero entries | row untouched, method returns `0` |
| s4 | lookup has entries but none match the symbol's name | row untouched, method returns `0` |
| s5 | same lookup, run twice | second run reports the same affected count (SQLite UPDATE-on-same-value still reports rows changed), values are stable |
| s6 | symbol name capitalized differently than URI segment (`NAVIGATIONLINK` vs `navigationlink`) | match still fires (lookup is case-insensitive on the LOWER(name) join key) |

**Why each case matters (first-principles):**

- **s1** proves the happy path actually writes the column. Without
  this, we ship a bundle that has the column but it's NULL for every
  row that should have been enriched, and the user community gets
  zero search-quality benefit.
- **s2** proves the optional-dependency contract: if
  `apple-constraints.json` is missing on the operator's machine, the
  save still completes; it just doesn't enrich. We do not want a
  missing-file crash here.
- **s3, s4** prove the bounds: empty lookup behaves as nil; a lookup
  with no matching entries does not corrupt rows.
- **s5** documents idempotency semantics. If we ever want
  re-runnable enrichment without re-indexing, this test pins what
  the current behaviour is.
- **s6** proves the case folding inside the SQL `WHERE LOWER(name)
  = ?` join key. Without it, real Apple framework types (capitalized
  in source) won't match URI segments (lowercased by Apple's
  pathComponents convention).

**Test file location:** `Packages/Tests/SampleIndexTests/Issue837SamplesAppleStaticConstraintsTests.swift`.

### 4.2 packages.db — constraint application

**Subject under test:**

- `Search.PackageIndex.applyAppleStaticConstraints(lookup:enrichmentVersion:)`.
- `Enrichment.PackagesAppleConstraintsPass`.

**Fixture:**

- A fresh `Search.PackageIndex` at a tmp path.
- One package row in `package_metadata`, one file row in
  `package_files`, one symbol in `package_symbols` named `Picker`.

**Cases:** identical structure to samples (s1–s6 above), substituting
`package_symbols` for `file_symbols`. Names: `p1–p6`.

**Why a parallel set is not redundant:** the SQL is parallel but
written separately; if one of the two methods diverges (different
column names, different binding offsets), only a parallel test set
catches it. We already had a parallel divergence bug class on the
`enrichment_version` column position; this set pins both methods to
the same observable behaviour.

**Test file:** `Packages/Tests/SearchTests/Issue837PackagesAppleStaticConstraintsTests.swift`.

### 4.3 packages.db — apple-imports aggregation

**Subject under test:**

- `Search.PackageIndex.applyAppleImports(lookup:enrichmentVersion:)`.
- `Enrichment.PackagesAppleImportsPass`.

**Fixture:**

- A fresh `Search.PackageIndex` at a tmp path.
- One package row with id `1`.
- Three rows in `package_files` for that package:
  - `module = "SwiftUI"` (Apple)
  - `module = "Combine"` (Apple)
  - `module = "ThirdPartyHelper"` (not Apple)

**Cases:**

| # | Input | Expected output |
|---|---|---|
| i1 | lookup has at least one entry whose `docURI` starts with `apple-docs://swiftui/` and at least one with `apple-docs://combine/` | `package_metadata.apple_imports_json` for that row equals `["Combine","SwiftUI"]` (sorted, lowercased), `enrichment_version` stamped, method returns `1` |
| i2 | lookup is nil | row untouched (`apple_imports_json IS NULL`), method returns `0` |
| i3 | lookup is non-empty but the package has no Apple imports | row untouched, method returns `0` |
| i4 | second package whose only import is `ThirdPartyHelper` | that row's `apple_imports_json` stays NULL even on a fresh run; only the first package gets updated |
| i5 | package with `module = NULL` rows (real packages have these for non-Swift files) | NULL modules are ignored, no crash, no spurious entry in JSON |

**Why each case matters:**

- **i1** is the entire feature: this is what makes
  `cupertino package-search --apple-imports SwiftUI` filterable in
  the next CLI iteration.
- **i2** preserves the no-`apple-constraints.json`-installed
  contract.
- **i3, i4** prove the SQL `WHERE module IS NOT NULL AND module !=
  ''` filter and the per-package scoping don't bleed.
- **i5** prevents a NULL-string crash on real corpora where many
  `package_files` rows are README / images / Package.resolved with
  no module.

**Test file:** `Packages/Tests/SearchTests/Issue837PackagesAppleImportsTests.swift`.

### 4.4 AST extraction round-trip (packages.db)

The AST path in `PackageIndex.insertFile` already landed (#844). It
needs a regression-lock test that a known input string produces a
known set of `package_symbols` rows. Without this, a SwiftSyntax
upgrade can silently change the extraction result and we'd only
notice after a real save.

**Fixture:** in-memory Swift source like:

```swift
import SwiftUI
struct MyView: View {
    var body: some View { Text("hello") }
}
```

passed via `insertFile` to a fresh `PackageIndex`.

**Cases:**

- `package_symbols` has at least one row with `name == "MyView"`,
  `kind == "structDecl"`, `is_public == 0`.
- The `package_files` row for this file has `module = "SwiftUI"` or
  whatever the file classifier returns.

**Test file:**
`Packages/Tests/SearchTests/Issue837PackageSymbolsExtractionTests.swift`.

### 4.5 Composition-root integration

After 4.1–4.4 are green at the unit level, one integration test per
DB constructs the real `Enrichment.LiveRunner` with the production
pass set and asserts the runner returns the expected per-pass
`Result` shape.

**Why:** unit tests can pass while the wiring at the composition root
mis-orders passes or skips one. The integration test pins the wiring
the production binary actually executes.

**Test file:** `Packages/Tests/EnrichmentTests/Issue837CompositionRootIntegrationTests.swift`.

### 4.6 Schema migration round-trip

Pin v3 → v4 migration for both DBs (`#849`).

- packages.db: seed a v3 DB, open with the v4 binary, assert
  `PRAGMA user_version == 4`, new columns + new `package_symbols`
  table exist, pre-existing v3 data is intact.
- samples.db: seed a v3 DB, assert the wipe-and-rebuild policy ran
  (no v3 leftovers), fresh v4 schema is in place.

**Test file:** `Packages/Tests/SearchTests/Issue837PackagesV4MigrationTests.swift`
and `Packages/Tests/SampleIndexTests/Issue837SamplesV4MigrationTests.swift`.

---

## 5. Acceptance gate

Before any operator runs `cupertino save --samples` or `cupertino
save --packages` against a real corpus to produce the v1.2.0 bundle:

- [ ] All test files in §4.1–§4.6 exist and are committed to main.
- [ ] `xcrun swift test` from `Packages/` exits 0.
- [ ] The full suite count is at or above the current 2367 / 336
  (every new test is additive; no test was deleted to make the gate
  pass).
- [ ] `scripts/check-pre-index.sh` (the #794 gate that already runs
  the 10% mini-corpus end-to-end save) is run and green. That gate
  re-verifies the search.db path; the new enrichment paths are
  exercised by §4.1–§4.5.
- [ ] One human visually inspects the diff of one test-fixture row
  before-and-after enrichment (one row, not all) as a final
  sanity-check that the read-back values match the lookup input.

Only after every box is checked do we burn the real-corpus save run.

---

## 6. What this doc does NOT cover

- The 11h `--docs` save itself. That's the eventual gate for
  search.db; #514 already tracks the related WAL measurement and was
  deferred to v1.3.x.
- The bundle assembly + upload + tag + brew formula bump. Those are
  release-mechanics, gated by a separate user "go", already covered
  by the existing release-prep workflow.
- Search-quality re-measurement after the new enrichment lands.
  That's a follow-up Phase 1.9 audit, not part of the pre-index
  gate.

---

## 7. References

- `docs/design/per-db-enrichment.md` — what each DB gets.
- `docs/design/post-processor.md` — how the pipeline is structured.
- `scripts/check-pre-index.sh` (#794) — the pre-flight script we
  already rely on for search.db. This doc is its samples + packages
  counterpart.
- Tracking issues: #837 (umbrella), #847 (samples tests), #848
  (packages tests), #849 (migration tests).
