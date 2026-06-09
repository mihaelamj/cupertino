# --apple-imports

Filter `packages` results to packages that import a given Apple framework.

## Synopsis

```bash
cupertino search <query> --source packages --apple-imports <module>
```

## Description

Restricts the `packages` candidate set to packages whose `package_metadata.apple_imports_json` array contains the given Apple framework slug. The packages indexer derives `apple_imports_json` from `package_files.module` joined against the symbol-graph module list shipped with the bundle, so the value is `["combine","swiftui"]` for a package that imports SwiftUI + Combine.

The filter uses a quote-bracketed JSON `LIKE` pattern (`'%"swiftui"%'`) so `swiftui` matches `["swiftui"]` and `["combine","swiftui"]` but not `["swiftuihelper"]` or any other substring false-positive.

Wired through CLI → `Search.PackageFTSCandidateFetcher` → `Search.PackageQuery.answer(appleImport:)` for the single-source path, and through MCP → `Services.UnifiedSearchService.searchAll(appleImports:)` → `Search.PackagesSearcher` for the fan-out path.

## Scope

- Applies on **packages** results only. No effect on rows from `apple-docs`, `apple-archive`, `hig`, `swift-evolution`, `swift-org`, `swift-book`, or `samples`.
- Combines with `--platform` / `--min-version` in fan-out mode; both filters apply to package rows before ranking.
- Module slug is **lowercased** at write time, so the CLI lowercases its argument before binding. Passing `--apple-imports SwiftUI` is equivalent to `--apple-imports swiftui`.

## Default

Unset. No `apple_imports_json` filter is applied; the packages candidate set is BM25-ranked across the full corpus.

## Examples

### SwiftUI-only packages
```bash
cupertino search "View" --source packages --apple-imports SwiftUI
```

### Combine-only packages
```bash
cupertino search "Publisher" --source packages --apple-imports Combine
```

### Fan-out search restricted to SwiftUI packages
```bash
cupertino search "rendering" --apple-imports SwiftUI
```
(no `--source`: docs / samples / hig / swift-evolution / swift-org / swift-book are unaffected; packages bucket is filtered.)

## Combining with Other Options

### apple-imports + platform
```bash
cupertino search "Pie" --source packages --apple-imports SwiftUI --platform iOS --min-version 17
```

### apple-imports + framework
```bash
cupertino search "Chart" --source packages --apple-imports Charts
```
Note: `--framework` filters by Apple-framework slug on `apple-docs` / `apple-archive`; on packages it matches against `package_files.module`. Both can be set simultaneously.

### MCP equivalent
The MCP `search` tool accepts the same filter as the `apple_imports` argument:

```json
{
  "name": "search",
  "arguments": {
    "query": "View",
    "source": "packages",
    "apple_imports": "SwiftUI"
  }
}
```

## Use Cases

- **Find packages that integrate with a specific Apple framework**: `--apple-imports SwiftUI` narrows the result set to packages whose source tree imports SwiftUI somewhere.
- **AI agents triaging dependency choices**: combining `--apple-imports` with a query produces a small, semantically-coherent candidate set instead of a generic BM25 mix.
- **Auditing**: pass an Apple framework you've deprecated internally and see which packages still depend on it.

## Notes

- The `apple_imports_json` column is populated by the `cupertino save --source packages` enrichment pass introduced in v1.2.0. Bundles built against older binaries (pre-v1.2.0) carry NULL `apple_imports_json` and `--apple-imports` filters to zero rows. Run `cupertino setup` to fetch a v1.2.0+ bundle.
- The filter is one-dimensional: it asserts the module **is** in the package's apple-imports set. There's no exclusion form. Pass a single module per query.
- When combined with `--apple-imports <non-Apple-module>` (e.g. `Vapor`), the filter still applies the LIKE pattern but no rows match because `apple_imports_json` only stores Apple-framework slugs.
- Set on a source other than `packages` is silently ignored: `cupertino search "View" --source apple-docs --apple-imports SwiftUI` returns the same rows as without the filter.
