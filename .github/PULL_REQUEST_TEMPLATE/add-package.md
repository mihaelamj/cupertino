<!--
  PR template for adding a Swift package to Cupertino's priority catalog.
  Selected via ?template=add-package.md when opening a PR.
  Read CONTRIBUTING.md first. This is the lightweight path: it gets a package
  into the shipped corpus without the user-side `cupertino package add` flow.
-->

## Package

<!-- One package per PR. Fill all three. -->

- Owner / repo: `owner/repo`
- URL: https://github.com/owner/repo
- Tier: <!-- apple_official (owner is `apple`) | ecosystem (everything else) -->

## Why it belongs

<!-- Why should this ship in Cupertino's default corpus for every user?
     Concrete relevance to Apple-platform / Swift development, not just popularity. -->

-

## Eligibility

- [ ] It is a Swift or Swift-ecosystem repository whose docs are useful to Apple-platform / Swift developers (most are SwiftPM packages; the catalog also carries first-party repos like `apple/swift` and `sourcekit-lsp`).
- [ ] It is publicly hosted and the license permits redistribution of its docs.
- [ ] It is actively maintained (a release or commit within the last ~12 months).
- [ ] It is not already in the catalog (search `Resources.Embedded.PriorityPackages.swift` for the repo name).

## What to edit

Add the package to the embedded catalog, which is the build-time source of truth:

`Packages/Sources/Resources/Embedded/Resources.Embedded.PriorityPackages.swift`

1. Add an entry to the right tier's `packages` array:
   - `apple_official` (owner is implied, so no `owner` field): `{ "repo": "swift-foo", "url": "https://github.com/apple/swift-foo" }`
   - `ecosystem` (keep this array ordered by owner then repo): `{ "owner": "SomeOwner", "repo": "Foo", "url": "https://github.com/SomeOwner/Foo" }`
2. Bump that tier's `"count"` by one.
3. Bump the matching field in the top-level `"stats"` block: `totalPriorityPackages` always, plus `totalCriticalApplePackages` (apple tier) or `totalEcosystemPackages` (ecosystem tier). Keep every counter consistent: each tier `count` equals its array length, and the `stats` totals match.
4. Bump the top-level `"lastUpdated"` date.

<!--
  Note for maintainers: the embedded catalog above is the single source of
  truth. The old committed Packages/priority-packages.json (a stale v1.0 relic)
  was removed in #1149; the generator still takes a priority-packages.json as
  input, but only from /tmp/catalogs, never from the repo.
-->

## Linked issue

<!-- e.g. "Closes #123" if an issue requested this package. Optional for a single add. -->

## Test plan

```bash
cd Packages && swift build
swift test --filter PriorityPackages
```

<!-- Cite the result. The PriorityPackages suite confirms the catalog still
     parses and merges; the count / stats counters are not asserted by a test,
     so eyeball them yourself per step 2-3 above. -->

## Checklist

- [ ] Targets `develop`, not `main` (external PRs to `main` are rejected by CI).
- [ ] One package added; the tier `count`, `totalPriorityPackages`, the matching per-tier `stats` total, and `lastUpdated` all bumped and consistent.
- [ ] Ecosystem entries kept ordered by owner then repo.
- [ ] Catalog still parses and the build passes locally.
- [ ] `CHANGELOG.md` noted under the correct section.
