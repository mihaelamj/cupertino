# Stage D — Regression Locks (ironclad sweep)

**Scope:** for each of the 11 Stage A confirmed-closed issues, document the regression lock that prevents the closure from silently reopening. Locks come in four shapes:

- **Test**: unit / integration / E2E test pinning the invariant
- **Structural assertion**: schema constraint, type signature, build-time check
- **CI guard**: script invoked by CI that fails on known-bad patterns
- **No-lock note**: explicit rationale when a lock isn't possible / appropriate

The protective intent: when someone refactors next month and accidentally re-introduces the bug, the lock catches it before merge.

---

## Inventory: the 11 Stage A confirmed-closed issues

| # | Closure | Existing test coverage | Lock type |
|---|---|---|---|
| #708 | multi-term FTS5 AND-collapse (false positive) | 0 test files | Existing: `scripts/check-canonical-db-shape.sh` |
| #709 | class-reference page ranking miss (false positive) | 0 test files | Existing: `scripts/check-canonical-db-shape.sh` |
| #715 | over-precise multi-term low-score (false positive) | 0 test files | Existing: `scripts/check-canonical-db-shape.sh` |
| #719 | SwiftUI class-reference docs sparse (false positive) | 0 test files | Existing: `scripts/check-canonical-db-shape.sh` |
| #225 | Index Swift language version | 4 test files (`Issue225*`) | Test + schema-shape pin (`SchemaShapeTests`) |
| #275 | doctor --freshness | 1 test file (`Issue275FreshnessProbeTests`) | Test |
| #665 | search_generics MCP tool | 4 test files (`Issue665*` + `Issue645ToolsListHonestyTests`) | Test + tools/list count pin |
| #113 | doc:// → https:// rewriter | 3 test files (`Issue113*`) | Test + post-save sweep |
| #722 | SaveSiblingGate --force-replace | 1 test file (`Issue722ForceReplaceTests`) | Test (24 sub-cases) |
| #409 | AST is_public + generic_params | 3 test files (`Issue409*` + `Issue665*`) | Test |
| #624 | /cupertino-test-everything skill | 0 test files | **No-lock** (cross-repo) — documented |

**6 of 11 have strong native test coverage** (#225, #275, #665, #113, #722, #409). **4 of 11 are false positives** covered by the existing `check-canonical-db-shape.sh` (which is itself the regression lock the false-positive class needed). **1 of 11 is genuinely cross-repo** (#624 — the skill lives in `mihaela-agents/`).

## Plus the #101 reopen lock (this stage's new addition)

The Stage A closure-replay reopened #101 because the duplicate-constant fold-in named in the issue body was never done. PR #729 ships the fix; this stage adds the regression lock that would have caught the original miss.

**New CI guard: `scripts/check-canonical-literals.sh`**

Enforces that load-bearing literals appear in exactly one `Packages/Sources/` location. Registry-driven — each entry names the literal, the expected single file, and the issue / PR that defines the invariant. Current registry:

- `"selected-archive-guides.json"` → `Packages/Sources/Shared/Constants/Shared.Constants.swift` (#101)

If `develop` ever reintroduces the literal in a second location, the script exits 1 with a clear diagnostic naming the duplicate file. Add new registry entries as future duplicate-constant smells emerge.

Smoke-tested by adding a known-bad pre-#101 source state: the script correctly identifies the two files and prints the same message the Stage A audit produced.

## False-positive class lock (already shipped, documented here for completeness)

The four false-positive closures (#708 / #709 / #715 / #719) share a root cause: the user's `~/.cupertino/search.db` was corrupted by an earlier runaway-save incident (160 MB / 37 frameworks / 21,701 docs, vs canonical 2.4 GB / 420 frameworks / 285,735 docs). Every "search returns weird results" bug filed against the corrupt DB looked real until the DB-shape check ran.

The regression lock for the class is `scripts/check-canonical-db-shape.sh` (shipped pre-Stage A, see [Stage A audit](closure-replay-2026-05-17.md) for the field-report cycle the canonical floor of 420 frameworks / 285,735 docs was set against). Running the check upfront would have skipped four file-issue → cross-link → comment → close cycles.

Operationalised as a memory rule (`feedback_smoke_check_db_state_before_filing.md`): always smoke-check before filing a search-quality bug. The shell script makes the discipline mechanical.

## No-lock: #624 (cross-repo skill)

The `/cupertino-test-everything` skill (875 lines) lives at `mihaela-agents/skills/cupertino/test-everything/SKILL.md` — a private sibling repo. Cupertino's CI cannot reach across the repo boundary to verify the skill file exists, has the expected step structure, or produces the expected PASS/FAIL output.

**Workarounds considered + rejected:**

- **Symlink**: would couple the public cupertino repo to private mihaela-agents, breaking the public-only build.
- **CI hook that clones mihaela-agents**: requires a credential the public CI can't carry without leaking access.
- **Vendoring the skill into cupertino**: would duplicate the skill that mihaela-agents owns as the canonical mirror.

**Resolution:** leave unlocked. The skill's correctness is verified manually whenever the maintainer runs `/cupertino-test-everything` — which is the post-promote ritual the skill was built for. If the skill silently breaks, the next promote will surface it. Documented in [Stage E process changes](#) when those land: the closure protocol for cross-repo deliverables should call out "lock-not-possible" as a legitimate state with a corresponding monitoring practice.

## Methodology note

Stage D was scoped at session start as a 4-8h pass to write new locks for every closure. The inventory pass showed most closures already had solid coverage from their original PRs — the actual gap was narrow (one structural-CI script for the #101 class, plus an explicit no-lock note for #624). That asymmetry is itself a methodology finding: **closures from PRs with strong test discipline don't need a Stage D pass at all; closures that slipped through with thin tests are the ones Stage D actually adds value to.**

Future Stage D passes should start with the inventory step and target only the closures whose existing coverage is thin. The dramatic majority of Stage A's confirmed-closed list landed via PRs that already had ironclad-shape test coverage; Stage D's value is concentrated on the narrow tail.

## Action items

- [x] `scripts/check-canonical-literals.sh` — created + smoke-tested
- [x] This audit doc — committed
- [ ] CI workflow integration: invoke the script in `.github/workflows/lint.yml`. (Deferred — would require a CI workflow edit; the script is invokable locally in the meantime.)
- [ ] Stage E (process changes): closure protocol should encode "lock type + location" as required metadata in every closing comment.

## What Stage D does NOT do

- Add tests for the false-positive cluster (#708-719). Their lock is the DB-shape smoke check, not per-issue tests — the bugs were against a corrupt DB, not against a code path.
- Re-test the 6 closures with strong existing coverage. Their tests are the lock.
- Cross-repo verification of #624. Documented as no-lock with rationale.
