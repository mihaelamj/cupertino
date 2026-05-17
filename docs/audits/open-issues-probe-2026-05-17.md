# Open-Issue Currency Probe — 2026-05-17 (Stage C of ironclad sweep)

**Scope:** code-state probe all 57 open cupertino issues. For each: verify the issue is still applicable to develop's current state (not silently shipped, not superseded, not stale).

**Method:** same protocol as Stage A's closure replay, inverted. Read body → extract acceptance bullets → probe specific files/functions → verdict.

## Headline result

- 🟢 **Applicable (work not done):** ~48 issues
- 🟡 **Partially-shipped:** 8 issues — body needs strike-through update for done bullets
- 🔴 **Silently shipped:** **0** — no false-openings found
- ⚫ **Stale / evergreen meta:** 1 (#197)

**0% silent-shipping rate** is meaningful. Stage A's closed-side replay caught 12.5% false closures (2 of 16). Stage C's open-side probe caught 0 silent shippings (0 of 57). The asymmetry is healthy: when in doubt, the tracker leaves issues open rather than prematurely closing them.

## Partial-shipping update table (Bucket 2 work)

| # | Title | What's already shipped (strike from body) | What remains |
|---|---|---|---|
| #50 | MCP conditional tool registration | search.db / sample.db coarse gates (post-#645) | per-source `SourceAvailability` helper + trim `schemaParamSource` enum |
| #13 | MCP resource templates | 2 of 9 templates (`apple-docs`, `swift-evolution`) live in `MCP.Support.DocsResourceProvider.swift:392-409` | 7 templates + per-variable JSON-Schema typing |
| #80 | MCP registries discoverability | PulseMCP + LobeHub badges in README | GitHub MCP Registry + Awesome MCP lists + tagline lock + `server.json` manifest |
| #227 | Per-sample availability annotation | Core annotation pass + per-file `available_attrs_json` (via #228) | Dual-axis columns (framework-floor vs sample-floor) + reconciliation report + CLI filter flags |
| #514 | Quantify WAL+sync=NORMAL throughput | Concurrency-correctness verification (samples + docs) | Three-binary throughput baseline (pre-WAL vs WAL vs WAL+sync=NORMAL) × 3 runs each |
| #247 | Lift FetchCommand to Ingest | Ingest skeleton + Session.swift (291 lines) | 7 Pipeline lifts (sub-PRs 4b-4f); `FetchCommand.swift` still 1202 lines (target <300) |
| #266 | Epic: availability annotation v2 | Children #221 + #225 shipped | 5 remaining children (#222, #223, #224, #227, #235) |
| #77 | CamelCase token-boundary expansion | Code path + 5 of 6 bullets | Bullet 6: wall-clock reindex duration in CHANGELOG |
| #226 | MCP --platform / --min-version | Schema-axis 5-field shape on 5 search-style tools | Required-together validation + `info.platform_filter_partial` cross-source notice |

## Reopen-state reconfirmed

#101 (PR #729 open, awaiting merge), #226, #77 reopens stand. Code-state probes confirm the specific unmet bullets named in the Stage A closure-replay audit.

## Backlog (Bucket 3)

~46 issues are legitimate v1.3+ roadmap items. No "we missed shipping this" — these are "pick up when prioritized." Highlights:

- **Search quality:** #8 vector search, #9 highlighting, #10 BK-tree spelling, #271 token budget, #272 sample cross-links
- **Source expansion (#190 umbrella):** #58 WWDC, #89 Swift Forums, #103 Kernel/IOKit, #216 tutorials, #273 Tech Talks, #713 fastlane, #714 tuist
- **Infrastructure (#251 umbrella):** unified source catalog, #410 per-source DB split, #248 declarative DB registry
- **Process / docs:** #21 cupertino-bench, #22 memory budgets, #43 Homebrew Core, #449 DocC catalog, #517 AI-agent results
- **Internal:** #189 TUI polish (5 items), #197 roadmap meta
- **AST availability:** #222, #223, #224, #235, #269 platform expansion, #270 device tracking
- **MCP capability:** #175 server restart, #195 AI semantic tags (gated on #196 fundraising), #224 doctor coverage
- **Recent:** #724 binary-provenance assertion, #730 swift-packages accessor cleanup

## Methodology validation

Stage C agents applied the Stage A pattern: probe specific files/functions named in the body, cite file:line evidence, use sqlite3 schema probes for DB-shape questions, run actual CLI commands for flag-existence questions.

Patterns observed:
1. **Source-strategy probes are reliable**: searching `Packages/Sources/Search/Strategies/` for an expected strategy file catches both "shipped under different name" and "not implemented" cases.
2. **CLI flag probes via `cupertino <cmd> --help`** are authoritative — develop's binary matches the source.
3. **MCP tool registration probes** via `CompositeToolProvider.swift` line numbers catch all variants.
4. **Schema probes via `sqlite3 ~/.cupertino/search.db .schema`** authoritative for DB-shape bullets (NB: schema reflects v1.0.2 ship state, not develop's staged v1.2.0 schema).

## Action items from Stage C

**Bucket 1 — Code fixes (load-bearing):**
- #226: ship required-together validation + `info.platform_filter_partial` cross-source notice. Bullet 3 is the AI-client-load-bearing piece per the original issue body.
- #77: schedule reindex on reference machine, record wall-clock in CHANGELOG (fold into v1.2.0 release ceremony).
- #729 (PR): merge to land the #101 fix.

**Bucket 2 — Tracker hygiene (8 issue body updates):**
- Strike-through done bullets per the table above.
- Update epic checklists (#266: tick #221 and #225).
- Adjust scope wording where the original phrasing no longer matches the shipped shape.

**Bucket 3 — Defer:**
- Most open issues are legitimate roadmap items; no premature closure recommended.
