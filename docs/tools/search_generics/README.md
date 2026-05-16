# search_generics

Find generic types and functions by constraint, across Apple documentation.

## Synopsis

```json
{
  "name": "search_generics",
  "arguments": {
    "constraint": "Sendable",
    "framework": "swiftui",
    "limit": 20
  }
}
```

## Description

Surfaces the AST-extracted `doc_symbols.generic_params` column — the where-clause of every generic declaration in the indexed corpus (`T: View`, `Element: Hashable & Sendable`, `Key: Comparable`, …). Match is substring-`LIKE` on the constraint, so a query of `Sendable` returns both `T: Sendable` and `T: Hashable & Sendable`.

The response echoes the matched clause on every row, so a calling agent can tell why a symbol matched without re-reading the source.

This tool complements `search_conformances`: `search_conformances` finds types that **conform** to a protocol; `search_generics` finds types that **bound** a generic parameter on a protocol (a different relationship, often more useful for "where is X used as a constraint" investigations).

## Parameters

### constraint (required)

Generic-parameter constraint to search for. Matched as a substring against the joined clause.

**Type:** String

**Common constraints:**
- `"Sendable"` — Concurrency-safe constraints
- `"Hashable"` — Used as dictionary keys / set elements
- `"Equatable"` — Equality-comparable constraints
- `"Comparable"` — Ordering constraints
- `"View"` — SwiftUI view-content bounds
- `"Codable"` — Encode/decode bounds
- `"Identifiable"` — Stable-identity bounds
- `"BinaryInteger"` — Numeric constraints
- `"FloatingPoint"` — Floating-point bounds

### framework (optional)

Restrict results to a specific framework (case-insensitive).

**Type:** String

**Examples:**
- `"swiftui"`
- `"foundation"`
- `"combine"`

### limit (optional)

Maximum number of results.

**Type:** Integer  
**Default:** 20

### min_ios / min_macos / min_tvos / min_watchos / min_visionos (optional)

Platform-availability floor (#226). Drops rows whose `min_<platform>` is above the user's floor — i.e. the user is on platform version X, hide APIs that require newer. Rows with NULL `min_<platform>` on the requested platform are dropped when the filter is active (no availability metadata = unknown = excluded from a platform-scoped query). Mirrors the semantics of the same args on `search_symbols` / `search_property_wrappers` / `search_concurrency` / `search_conformances`.

**Type:** String (dotted-decimal semver, e.g. `"16.0"`, `"10.15"`)

**Example:** `{"constraint": "Sendable", "min_ios": "16.0"}` returns only Sendable-constrained generics whose iOS deployment-target floor is ≤ 16.0 (i.e. available on iOS 16 and earlier; iOS 18-only APIs filtered out).

## Examples

### Find Sendable-Constrained Generics

```json
{
  "constraint": "Sendable"
}
```

### Find View-Constrained Generics in SwiftUI

```json
{
  "constraint": "View",
  "framework": "swiftui"
}
```

### Find Hashable Bounds

```json
{
  "constraint": "Hashable"
}
```

## Common Use Cases

### Auditing Sendable Adoption

```json
{"constraint": "Sendable"}
```

Find every generic that requires `Sendable` — useful when migrating a library to Swift 6 strict concurrency.

### Learning Generic-Constraint Idioms

```json
{"constraint": "Comparable"}
{"constraint": "BinaryInteger"}
```

See how Apple bounds generics in the standard library and Foundation.

### Tracking Down Specific Constraints

```json
{"constraint": "View", "framework": "swiftui"}
```

Find every SwiftUI generic that bounds its content on `View` — the canonical pattern for composable view containers.

## Notes

- Symbols with no generic clause are excluded entirely (a `LIKE` against `NULL` is `NULL`, not `TRUE`).
- An empty `constraint` (`""`) matches every symbol with any generic clause — useful as a coarse "show me all generics" pass.
- Framework filter is case-insensitive (`"SwiftUI"` and `"swiftui"` both work).

## See Also

- [search_conformances](../search_conformances/) — Search by protocol conformance (types that **implement** a protocol)
- [search_symbols](../search_symbols/) — Search by symbol kind and name
- [search_property_wrappers](../search_property_wrappers/) — Search by property wrapper
- [search_concurrency](../search_concurrency/) — Search concurrency patterns
