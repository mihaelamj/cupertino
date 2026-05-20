# Design: Per-DB Enrichment Across cupertino's Three Read DBs

## Status (2026-05-20)

Draft. Tracks the per-DB scope of #837. Companion to
`docs/design/post-processor.md` (which defines the pipeline shape) —
this doc decides *what* each DB actually gets enriched with.

---

## Problem

`#837` says all three of cupertino's read DBs (search.db, samples.db,
packages.db) should go through the postprocessor pipeline so search
quality benefits from cupertino-symbolgraphs data is applied evenly.
The pipeline shape is already designed (`post-processor.md`). What
isn't decided yet: **for each DB, what does the enrichment actually
write, and to which column?**

This matters because the three DBs have very different schemas:

| DB | Primary table | Symbol-shaped table? | Constraint-shaped column? |
|---|---|---|---|
| search.db | `docs_metadata` | `doc_symbols` (with `generic_constraints`) | Yes — written by the existing `applyAppleStaticConstraints` pass |
| samples.db | `projects` + `files` | `file_symbols` (with `generic_params`) | Closest analogue exists |
| packages.db | `package_metadata` | None | None |

A naive "run the same pass against all three" doesn't compile — there
is no `doc_symbols` table on samples.db or packages.db, and no
`generic_constraints` column on either. Each DB needs its own
schema-appropriate pass, even when the *input* (the
`AppleConstraintsKit.Table` derived from the cupertino-symbolgraphs
corpus) is the same.

---

## What does "enriched" mean for each DB?

### search.db (existing — described for completeness)

**Goal:** when a query like `"NavigationLink generic destination"`
runs, the ranker uses authoritative constraint data to rank the right
page (`NavigationLink` whose `Destination: View`) above generic-named
results.

**Input:** `AppleConstraintsKit.Table` (the in-memory representation
of the symbolgraph-derived constraint map).

**Write target:** `doc_symbols.generic_constraints` column, keyed by
`doc_uri`. The existing `applyAppleStaticConstraints` pass + the
`propagateConstraintsFromParents` hierarchy walk handle this.

**Status:** in production, the only thing #837 changes here is that
the calls run through the postprocessor runner instead of inline in
`Search.IndexBuilder.buildIndex`. Same SQL writes, same ordering.

### samples.db

**Goal:** when a query like `"NavigationLink sample"` runs against
samples, samples that demonstrate `NavigationLink` get ranked using
the same constraint signal that search.db uses for the docs page. A
sample showing `NavigationLink<Label, Destination>` should surface for
`destination view` queries, even if the surrounding prose doesn't say
"View".

**Input:** the same `AppleConstraintsKit.Table` used for search.db.
No new corpus dependency.

**Write target:** `samples.db` already has `file_symbols.generic_params`
which carries the same shape of data (a string representation of the
generic parameter list — `<Label: View, Destination: View>` for
`NavigationLink`). The enrichment pass writes the authoritative
constraint string into this column for any `file_symbols.name` that
matches a known Apple symbol from the table.

**Match key:** `file_symbols.name` against the symbolgraph table's
URI-derived symbol names. The
`AppleConstraintsKit.URIMapper` already converts table URIs to
matchable string forms; we reuse that.

**Idempotency:** the pass writes only when the existing
`generic_params` is NULL or empty, OR when the existing value
mismatches the authoritative one (in which case it overrides and
logs). A `samples_enrichment_version` column on `file_symbols` tracks
which pass version last ran on each row.

**Schema migration:** ADD COLUMN `samples_enrichment_version INTEGER`
on `file_symbols`. v3 → v4 schema bump on samples.db.

**Pass identifier:** `samples-apple-constraints`. dependsOn empty.

### packages.db

**Goal:** packages that import / re-export Apple frameworks should be
filterable / rankable on which Apple framework they extend. A user
searching `"swiftui community"` should see packages that import
SwiftUI.

**Input is asymmetric.** The `AppleConstraintsKit.Table` itself is
not directly useful for packages.db because:

1. packages.db rows are SwiftPM packages, not Apple types. The
   constraint data describes Apple's own framework symbols.
2. packages.db has no symbol-shaped data inside — `package_files`
   stores filename + module + size, not file content or extracted
   symbols.

What IS useful: the **set of valid Apple module names** the
symbolgraph corpus knows about (`SwiftUI`, `UIKit`, `Combine`,
`CoreData`, etc., the keys of
`AppleSymbolGraphsKit.FrameworkModuleMap`). This is a static list,
already derived during cupertino-symbolgraphs generation, ~225
entries.

**Write target:** the existing `package_files.module` column already
carries the Swift module name parsed from per-file `import` declarations
(or from the package's Package.swift `.target(name:)`). A new
`apple_imports_json` column on `package_metadata` aggregates, per
package, the subset of those module names that match the Apple
framework module list — i.e. "this package imports these N Apple
frameworks". The column is computed by joining `package_metadata`
against `package_files` and filtering against the Apple module set.

**Match key:** `package_files.module` against the Apple module set
from `AppleSymbolGraphsKit.FrameworkModuleMap`.

**Idempotency:** the pass writes the full set every time the package's
file list changes. A `packages_enrichment_version` column on
`package_metadata` tracks the pass version.

**Schema migration:** ADD COLUMN `apple_imports_json TEXT` on
`package_metadata`, ADD COLUMN `packages_enrichment_version INTEGER` on
`package_metadata`. v3 → v4 schema bump on packages.db.

**Pass identifier:** `packages-apple-imports`. dependsOn empty.

---

## Two-stage scope

User direction (2026-05-20) is "all DBs must have everything", with
"everything" expanded to BOTH same-framework AND same-schema scopes.
Implemented in two stages:

### Stage 1 (v1.2.x ship): same framework, schema-appropriate writes

Captured in the table below. Each DB gets the postprocessor pipeline,
the `enrichment_version` column for idempotency, and the enrichment
write that its current schema can carry. No new symbol tables.

This stage is what this design doc primarily covers and what the
candidate implementation lands.

### Stage 2 (v1.3.x or later): symmetric symbol extraction on packages.db

Tracked separately. Adds a `package_symbols` table to packages.db
(parallel to `file_symbols` in samples.db), populated by a Swift AST
extraction pass during `cupertino save --packages` over every `.swift`
file in every package (~183 packages, thousands of files). Once
populated, the same `apple-constraints` pass that runs on samples.db
also runs against `package_symbols`. Major indexer rewrite + bundle
size growth — does not ship in v1.2.x.

## What does NOT belong in stage 1 (v1.2.x)

- **Per-symbol Apple-type extraction from packages source.** Deferred
  to stage 2 (see above).
- **Cross-DB joins at query time** (e.g. "show me samples that use
  the same Apple type as this doc"). Useful but a v1.3.x feature.
- **Re-extraction of symbolgraph data inside cupertino.** The
  cupertino-symbolgraphs companion package owns this. cupertino
  consumes the published corpus zip via `cupertino setup`.

---

## Surface area per DB

| DB | New column(s) | Schema bump | Pass identifier | Pass target | Bundle size impact |
|---|---|---|---|---|---|
| search.db | none (existing schema) | none (still v18) | `synonyms` + `constraints` + `hierarchy` | `.search` | none |
| samples.db | `file_symbols.samples_enrichment_version` | v3 → v4 | `samples-apple-constraints` | `.samples` | minimal (~1 int / row) |
| packages.db | `package_metadata.apple_imports_json` + `packages_enrichment_version` | v3 → v4 | `packages-apple-imports` | `.packages` | small (JSON array of module names) |

---

## Tests

Per the methodology guard:

- **samples.db pass** — pin against a synthetic samples fixture with
  a known `NavigationLink<Label, Destination>` reference. Assert that
  after enrichment, `file_symbols.generic_params` carries the
  authoritative `<Label: View, Destination: View>` form, NOT a literal
  copy of the inline declaration.
- **packages.db pass** — pin against a synthetic packages fixture
  whose `package_files.module` entries include `SwiftUI`, `Combine`,
  and `ThirdPartyHelper`. Assert that
  `package_metadata.apple_imports_json` after enrichment carries
  exactly `["SwiftUI", "Combine"]` (sorted) and excludes the third
  party.
- **schema migration** — `samples.db` v3 → v4 and `packages.db`
  v3 → v4 round-trip tests, mirroring the `Issue635SchemaStampGuard`
  pattern.
- **idempotency** — re-running each pass against the same DB at the
  same `schemaVersion` returns `Result.rowsAffected == 0`.

---

## Open questions (require decisions before implementation)

- **Should the samples constraint pass override an existing non-empty
  `generic_params`?** Today the column is populated by the sample
  indexer from the literal source declaration. Overriding to the
  authoritative form changes the column's semantics (from "what the
  sample wrote" to "what the type really has"). Recommend YES,
  override with a log line, since search ranking is the consumer of
  this column and the authoritative form is what helps queries land.
- **Should `apple_imports_json` be a JSON array, a comma-separated
  string, or a separate join table?** A new `package_apple_imports`
  join table would be more queryable but adds schema surface. JSON
  array fits the existing `parents_json` / `available_attrs_json`
  pattern in packages.db. Recommend JSON for consistency.
- **Schema bump strategy across both DBs simultaneously.** Today both
  samples.db and packages.db are at v3. Bumping both to v4 in the
  same release is straightforward (the existing migration runner
  already supports per-DB versions). Confirmed: both bump in v1.2.1.

---

## References

- Companion pipeline design: `docs/design/post-processor.md`
- cupertino-symbolgraphs: `/Volumes/Code/DeveloperExt/public/cupertino-symbolgraphs`
- AppleConstraintsKit: `Packages/Sources/AppleConstraintsKit/`
- Tracking: #837
- Epic: #769
