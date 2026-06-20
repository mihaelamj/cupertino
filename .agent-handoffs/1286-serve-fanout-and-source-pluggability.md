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
