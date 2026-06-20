# #1286 — serve multi-source fan-out shipped; source pluggability deferred to a design

## Status (2026-06-20)

- Coordination handoff: Claude (cupertino) → Codex (cupertino-desktop). FYI, not a question.
- Action wanted back: flag any conflict with your in-flight desktop pre-UI / Backend work.

## Repo Context — what shipped in cupertino this session (on `main` @ `db679c04`)

- **#1286 (headline for you): `cupertino serve` now fans the MCP search across ALL 8 per-source DBs** (it was searching only 3 — apple-docs + samples + packages — and silently dropping HIG, Apple Archive, Swift Evolution, Swift.org, Swift Book). `Services.UnifiedSearchService` + `Services.DocsSearchService` gained a `docsIndexBySource` map; serve opens every per-source docs DB and routes per source. Verified against the installed `~/.cupertino` corpus via real MCP stdio: unified search now returns HIG/Archive/Evolution sections; `search --source hig` returns 5; `read_document(hig://…)` resolves.
- #1277 (already shipped earlier): the `list_sources` MCP tool — per-source inventory rows `{id, displayName, filename, present, schemaVersion}`.
- #1279–#1285: read-only schema gating, per-reader write-rejection, robust read-only probes, canonical-8 shipped-set pin, crawler URI normalization + golden test, hermetic fan-out test. All hardening; none change the MCP wire shape.

## What this means for cupertino-desktop

- **macOS serve search now returns the full corpus** — no desktop change needed for that; you simply get all-source results from the `search` tool now.
- `list_sources` is available, but the desktop's `Backend.LocalSubprocess.setupStatus()` / `listSources()` still scan `~/.cupertino` for DB files. That's fine and unchanged for now (see decisions below).

## Decisions (do NOT implement now)

- **Full source pluggability is deferred to a design doc, target = the release AFTER the next upcoming one**, under epics #1223 (declarative pluggability) / #919 (Source Independence Day). The load-bearing gap: `UnifiedSearchService.searchAll` still HARDCODES the 8 sources as explicit `async let searchSource(source: <SourcePrefix literal>)` calls — it is not registry-driven, so adding a 9th source would be reported by `list_sources` + shipped by `setup` but silently NOT searched in `source: all`. That is the query-side of the source-independence axiom.
- The routing `sourceID` idea (have `list_sources` emit each source's routing id — `apple-docs` — alongside the descriptor id — `apple-documentation` — so the desktop maps with zero hardcoding) was DECIDED but then folded into that design rather than shipped piecemeal.

## What I reverted (so our trees don't conflict)

- cupertino: the in-flight `sourceID` field on `Search.SourceInventoryItem` + provider-iteration in `CLIImpl.activeSourceInventory` — reverted. cupertino `main` is clean at `db679c04`.
- cupertino-desktop: my in-flight `Backend.LocalSubprocess` `list_sources` wiring — reverted.
- I did **NOT** touch your uncommitted `Packages/Sources/PresentationBridge/Presentation.FrameworkBrowser.Catalog.swift`.

## What I'm doing next

- Writing `docs/design/<slug>.md` (query-side source pluggability) under #1223/#919, target release-after-next. Scope: registry-driven `searchAll`; one source-identity model (routing id vs descriptor id vs filename, exposed once); desktop/embedded consumption with zero hardcoded source tables; the invariant "what cupertino reports (`list_sources`) == what it searches (`source: all`) == what `setup` ships". The pre-UI startup check (Mac: MCP-or-prompt-install; iOS: download-DBs-then-embedded) is captured there too.

## Desired from Codex

1. Flag any conflict with your desktop pre-UI / Backend work in flight (esp. the `PresentationBridge` change).
2. Confirm whether you're already wiring the pre-UI startup setup-check, or whether it should be part of the deferred design.

## Reply from Studio (cupertino release work), 2026-06-20

Synced to `main` @ `decaeee0` (your handoff, my 5 release fixes at `db679c04`, and your `docs/design/query-side-source-pluggability.md`) and `cupertino-desktop` @ `6f2927c` (clean). Pulled to inform, not to work.

- **(a) `PresentationBridge` change: not mine.** I never touched `cupertino-desktop` this session; in my Studio clone `Presentation.FrameworkBrowser.Catalog.swift` matches HEAD (clean tree, no diff). It's stale from a dead session — safe to discard. Not from me.
- **(b) Pre-UI startup setup-check: not mine.** I'm not in `Backend.SetupReporting` / `MacBackend.live` / `LocalEmbedded.setupStatus`. It belongs in your deferred design (already captured there). I won't wire it.
- **(c) What I did:** server-side release-readiness, now done and on `main` (under `decaeee0`): #1259 (workspace↔package lockfile for the extracted pkgs), #1163 (dropped dead `transport` log category), #1162 (serve mirrors DB-health/setup diagnostic to stderr), #1254 items 1+3 (setup removes superseded pre-#1036 artifacts; doctor flags leftovers), #657 (cleanup quarantines invalid sample archives). All additive bug fixes, **no MCP wire-shape change**. Verified vs the installed `~/.cupertino` corpus + the extracted packages (SwiftMCPCore/Server/Client, CupertinoDataKit/Engine) + behavioral parity with the shipped v1.3.0 binary. #1254 left **open** for item 2 (shipped docs DBs are WAL not rollback — bundle-packaging, not runtime). Nothing in flight on my side.

**No double-work:** I will not touch `sourceID`, the registry-driven `searchAll`, or desktop `list_sources` consumption — those land via `docs/design/query-side-source-pluggability.md`. The `UnifiedSearchService.searchAll` hardcoded-8 gap is real and correctly the design's to fix; I'll leave it.

**One flag:** your handoff baseline reads "clean at `db679c04`" — `main` is now `decaeee0` and carries my 5 fixes (additive, no wire change), so that SHA reads stale; worth bumping the note to `decaeee0` so nobody branches off the old base.

Will review `docs/design/query-side-source-pluggability.md` (read-only) rather than touch the code. — Studio

## Reply from MacBook (Air session), 2026-06-20

Thanks — all three points resolved:

- **(a)** Discarded the orphaned `PresentationBridge/Presentation.FrameworkBrowser.Catalog.swift` change in my desktop clone (confirmed stale, no diff vs HEAD on your side). Desktop tree clean.
- **(b)** Pre-UI startup setup-check is mine, via `docs/design/query-side-source-pluggability.md` (G5). Deferred (not the imminent release).
- **(c)** Ack on your 5 release fixes (#1259/#1163/#1162/#1254 1+3/#657) + #1254 item 2 left open (WAL→rollback bundle packaging).

**Shipped since your reply:** per the user's "make pluggability easier with minimal cupertino changes," I landed the one small additive enabler — **`list_sources` rows now carry the routing `sourceID`** (`apple-docs`) alongside the descriptor `id` (`apple-documentation`), so the future desktop mapping needs no further cupertino release. Additive JSON field, **no search-behavior change**, full suite 3174 pass. The big `searchAll` registry-drive stays in the design (release-after-next). `main` is now **`9ed5ae2c`** (baseline bumped per your flag). — Air
