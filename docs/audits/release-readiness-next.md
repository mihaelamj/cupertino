# Release readiness: next release (post-v1.3.0)

Status: 2026-06-19. Target: the next cupertino release (74 commits ahead of `v1.3.0` on `main`),
whose headline server-side changes are the `list_sources` MCP inventory tool (#1277) and the
read-only-WAL open fix (#1194, `63bbe656`). Version not yet assigned.

This is an iron-clad, evidence-based readiness matrix in the proof-discipline style: "the release
is correct" is decomposed into separately-provable layers, each labelled with one epistemic
status, with the exact reproduction command and the measured result. No layer is asserted; each
is proven, witnessed, or named as a caveat. Nothing is silently skipped.

## Epistemic legend

- **PROVEN** — covered by an automated test that ran and passed.
- **WITNESSED** — exercised once against the real installed corpus / a live server and observed
  to pass (not a permanent regression guard, a point-in-time witness).
- **ENVIRONMENTAL** — depends on the host machine, not the release candidate.

## Matrix

| # | Layer | Epistemic status | Reproduce | Measured result (2026-06-19) |
|---|-------|------------------|-----------|------------------------------|
| 1 | Release-config build compiles | PROVEN | `swift build -c release` (in `Packages/`) | Build complete (212.84s), 0 errors. |
| 2 | Full behaviour suite (unit + integration) | PROVEN | `swift test` (in `Packages/`) | 3131 tests in 503 suites passed. (Swift disables `@testable` in release, so `swift test -c release` runs 0 tests by design; behaviour is proven in debug, the binary is proven to compile in release.) |
| 3 | Live MCP transport + handshake | PROVEN | `swift test --filter MCPIntegrationTests` | 11/11 passed: real `cupertino serve` over stdio, initialize handshake, `tools/list`, framing, malformed-input rejection. |
| 4 | `list_sources` inventory tool, live (#1277) | PROVEN | `swift test --filter MCPIntegrationTests` (the `list_sources` case) | Real `serve` `tools/call list_sources` returns a decodable `Search.SourceInventory`: non-empty, excludes legacy `search.db`, `installed <= expected`. |
| 5 | `list_sources` inventory derivation + tool unit (#1277) | PROVEN | `swift test --filter "SourceInventoryDerivationTests\|Issue1277ListSourcesToolTests"` | 6/6 passed: canonical registry-derived set, legacy `search` excluded, advertise/hide/return-JSON. |
| 6 | Read-only WAL open robustness (#1194) | PROVEN | `swift test --filter SQLiteSupportReadOnly` | 2/2 passed: a checkpointed WAL DB with sidecars removed reads correctly read-only (was misreported "schema version 0"). |
| 7 | Real-corpus read-only surface matrix | WITNESSED | `scripts/eval/release-corpus-smoke.sh ~/.cupertino` | 16/16 functional checks pass against the installed corpus: doctor, apple-docs search, fan-out search, read, list-frameworks, list-documents, list-children, list-samples, read-sample, package-search, package-read, search-symbols, search-conformances, search-generics, inheritance; plus "DB files + sidecar sizes unchanged" (read-only proven on real data). |
| 8 | Per-source schema-version consistency | WITNESSED | `cupertino doctor` (from-source binary, against `~/.cupertino`) | The 6 doc DBs at schema 18 (match binary); `apple-sample-code.db` 4 and `packages.db` 5 (their own correct per-DB versions); legacy `search.db` flagged for retire. The active set is the canonical 8. |
| 9 | Host disk headroom | ENVIRONMENTAL | (the `doctor` disk check inside layer 7) | FAIL on this host: `~/.cupertino` volume at 6% free (27.6 GB of 494 GB) — below the 10% `doctor` floor. This is the host machine being full of user data (not a release defect); the release-bundle build needs the host to free space first. Functional matrix is unaffected. |

## Verdict

The release candidate is **functionally green across every proven and witnessed layer** (1-8). The
only failing check (9) is the host's disk headroom, which is environmental and does not reflect a
defect in the candidate. Before cutting the bundle, free disk on the build host so the
`cupertino-databases-vX.Y.Z.zip` build has room and `doctor` clears its disk floor.

## Notes

- Layer 7's smoke is read-only by construction and asserts the corpus files + sidecars are byte-
  unchanged after the run, so running it against a real install is safe.
- Layers 4/5 mean the new `list_sources` tool is proven both in isolation and over the real MCP
  transport, so the desktop consumer (cupertino-desktop#98) can rely on it.
- Re-run the full matrix after any change to the source registry, the per-source DB descriptors,
  or the MCP tool provider, since those define the canonical source set (see #1036 migration).
