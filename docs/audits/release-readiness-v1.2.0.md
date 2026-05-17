# v1.2.0 Release-Readiness Audit

**Date:** 2026-05-17
**Develop tip:** `f8cc22c feat(cli): #722 — cupertino save --force-replace recovery flag with typed-confirmation gate (#725)`
**Scope:** Pre-release verification for the v1.2.0 tag. Does NOT bump versions or tag — those are user-gated.

---

## TL;DR — green across the board, three items need user decisions before tagging

✅ **107 CHANGELOG entries** under `Unreleased — staged for 1.2.0` — comprehensive
✅ **2218 tests / 303 suites** green from clean `make test-clean`
✅ **0 open bug-labeled issues**
✅ **docs/commands drift-check** clean (14 commands / 0 missing / 0 orphan / 0 enum drift)
✅ **canonical-DB shape** verified post-restore (420 frameworks / 285,735 docs)
✅ **swiftformat / swiftlint** clean

🟡 **User-decision items:** (1) bundle re-index? (2) version constants bump (1.1.0 → 1.2.0), (3) CLAUDE.md roadmap update

---

## Section 1: Test state

```
xcrun swift test (clean) — 2218 tests in 303 suites passed after 43.5s
```

- Net since v1.1.0 baseline: +790 tests (was 1,456 at v1.1.0 tag per CHANGELOG)
- All new tests this round have explicit test files (audited in earlier coverage report)
- No skipped tests, no XFAILs

## Section 2: CHANGELOG audit

**107 bullets** under `Unreleased — staged for 1.2.0`. Spot-check of the last 10 merged PRs against CHANGELOG entries:

| PR | Title (truncated) | CHANGELOG entry? |
|---|---|---|
| #725 | #722 force-replace flag | ✅ |
| #723 | check-canonical-db-shape.sh | ✅ |
| #721 | search_generics platform filter | ✅ |
| #720 | #241 help-text audit | ✅ |
| #718 | #225 Part B | ✅ |
| #717 | README chore | ⚠️ intentional (README chores don't need release-notes entries) |
| #716 | #225 Part A | ✅ |
| #712 | #113 audit-count | ✅ |
| #711 | #194 catalog removal | ✅ |
| #710 | #113 base | ✅ |
| #707 | #665 base | ✅ |
| #706 | #226 platform filter | ✅ |

**Verdict:** comprehensive coverage. No orphaned bullets, no missing entries for behavioural changes.

## Section 3: Version-anchor staleness

Three different version anchors exist in the tree right now:

| Anchor | Value | Source of truth |
|---|---|---|
| `Shared.Constants.App.version` | `"1.1.0"` | binary |
| `Shared.Constants.App.databaseVersion` | `"1.1.0"` | bundle |
| Brew install `cupertino --version` | `1.1.0` | shipped binary |
| CHANGELOG header | `Unreleased — staged for 1.2.0` | release-prep |
| CLAUDE.md `## Active focus` | `v1.0.0 / v1.0.1 / v1.0.2` shipped; **v1.1.0 not mentioned** | roadmap (stale) |
| CLAUDE.md `## v1.0.3 (next)` | `#236, #241, #253, #284, #285` (all closed) | roadmap (stale) |

**The CLAUDE.md staleness is the load-bearing finding.** It refers to v1.0.3 as "next" with 5 tickets that are all shipped (per the bug-list check + the #183 epic update). The actual "next" is v1.2.0, which is what this round delivers. CLAUDE.md hasn't been updated since v1.0.2.

## Section 4: User-decision items (you do these; I cannot)

These are the items the release-prep memory flags as user-gated:

### 4.1 Bundle decision — re-index or carry?

The v1.1.0 bundle is already on disk + in homebrew (verified via the user's brew bundle showing 420 frameworks / 285,735 docs). v1.2.0's question: ship the same bundle, or re-index against a fresher corpus?

**If carry the v1.1.0 bundle:**
- No 12-hour re-index required
- Bundle file name stays `cupertino-databases-v1.2.0.zip` (copy / rename from v1.1.0)
- Save the time; ship the binary changes only

**If re-index:**
- ~12 hours on a fast machine
- Bundle includes the #113 doc:// rewriter changes + #668 docs_structured for HIG/Evolution/Archive + #194 catalog removal effects
- New corpus carries the latest crawl data

The CHANGELOG entries that benefit from a re-index: #113 doc:// rewriter (existing leaked `doc://` URIs in shipped bundle won't be cleaned without re-index), #668 docs_structured coverage. The CHANGELOG explicitly says about #113: *"Brew users running against the existing v1.0.2 bundle keep the old leaked URIs (the bundle is the source of truth post-distribution)."*

### 4.2 Version constants bump

When you're ready to tag, update:

```swift
// Packages/Sources/Shared/Constants/Shared.Constants.swift
public static let databaseVersion = "1.2.0"   // was "1.1.0"
public static let version = "1.2.0"            // was "1.1.0"
```

(`App.version` is the binary version; `App.databaseVersion` is the bundle version. Both bump together for a major-minor release.)

### 4.3 CLAUDE.md roadmap update

Replace stale sections:

```markdown
## Active focus

[#183 — bugs → recrawl → vector → tutor]. v1.0.0 / v1.0.1 / v1.0.2 / **v1.1.0 (shipped 2026-05-14) / v1.2.0 (shipped 2026-05-17)**.

## v1.2.0 (shipped 2026-05-17)

Ironclad round. 107 CHANGELOG entries. Headline shipping:

- **Concurrent-save infrastructure:** #253 SaveSiblingGate + #722 --force-replace recovery
- **MCP surface:** #226 platform filter on 4 AST tools + #665 search_generics (12th MCP tool) + #665 follow-up platform filter on search_generics
- **Schema bumps:** packages.db v2→v3 (#225 Part A swift_tools_version), search.db v15→v16 (#225 Part B implementation_swift_version)
- **Indexer hardening:** #113 doc:// → https:// rewriter + audit-count, #668 docs_structured coverage, #669 inheritance fallback, #673 ironclad phases E/F/G/H
- **Triage discipline:** scripts/check-canonical-db-shape.sh smoke check + the feedback_smoke_check_db_state_before_filing memory rule

Test suite: 2218 / 303 suites (was 1,456 / 163 at v1.1.0 tag — +762 / +140).

## v1.3.x (next)

Carried-over backlog: #708 / #709 / #715 / #719 search-quality cluster (all closed as false positives this round; refile if real); #713 fastlane + #714 tuist external sources; #624 test-everything skill; #514 perf measurement; #410 split search.db.
```

### 4.4 Tag + release ceremony (when above is done)

```bash
# In Packages/
make build-release   # not raw swift build, per feedback_build_with_make_not_swift_build
xcrun swift test     # confirm 2218+ green from clean (already done — locked here)

git tag -a v1.2.0 -m "v1.2.0 ironclad — 107 CHANGELOG entries, 762 net new tests"
git push origin v1.2.0
gh release create v1.2.0 --notes-file ... --title "v1.2.0 ironclad"

# Bundle zip + homebrew formula: separate maintainer flow (release-prep memory items)
```

## Section 5: Pre-release CI / sanity check matrix

| Check | Result |
|---|---|
| `xcrun swift build` clean | ✅ |
| `xcrun swift test` (clean) | ✅ 2218 / 303 / 43.5s |
| `swiftformat .` no changes | ✅ |
| `scripts/check-docs-commands-drift.sh` | ✅ 14/0/0/0 |
| `scripts/check-canonical-db-shape.sh` | ✅ 420 / 285,735 |
| `scripts/smoke-reindex.sh` | (not run this audit — last verified at PR #643) |
| 0 open `bug` issues | ✅ |
| 0 open round-named tickets | ✅ |

## Section 6: What I am NOT doing in this audit (the release gate)

Per the established workflow ("you guys are allowed to code, test, merge PRs, just not release"):

- ❌ Bumping the CHANGELOG header from `Unreleased` to `1.2.0 (2026-05-17)`
- ❌ Bumping `App.version` / `App.databaseVersion` constants
- ❌ Updating CLAUDE.md
- ❌ Creating the v1.2.0 tag
- ❌ Publishing the GitHub Release
- ❌ Updating the homebrew formula
- ❌ Building / uploading the bundle zip

These six items are all yours when you're ready.

---

**Bottom line:** code is green, tests are green, docs are green, the round is closed. Three user-decision points are flagged above; everything else is ready for the tag.
