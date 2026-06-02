# Design: #742 MCP diagnostic block (structured-uncertainty response surface)

## TL;DR

Every MCP tool response should carry machine-readable side-channel signals (spelling candidates, partial-filter notices, per-source degradation, truncation, token cost) alongside the human-readable `content` body, using the MCP spec's own slots: `structuredContent` for model-visible typed data and `_meta` for client-only data. This is the Phase 2.1 keystone that unblocks #10, #13, #21, #70, #271, #517.

**The load-bearing constraint, discovered while designing this and not reflected in the #742 issue body (written before #1167):** the MCP wire types now live in the external **`SwiftMCPCore` package** (cupertino's `MCPCore` target depends on it, Package.swift). At the pinned `v0.1.0`, `Tool` has only `inputSchema` and `CallToolResult` is exactly `{ content, isError }`. Neither `outputSchema`, `structuredContent`, nor `_meta` exists, even though SwiftMCPCore targets the 2025-11-25 spec that defines them. So the design has a hard **Phase 0: extend SwiftMCPCore upstream and cut a release**, before any cupertino-side work. That phase is maintainer-gated (it publishes a package version).

## 1. Context

Seven open issues name a "diagnostic block keystone" as a dependency. Each needs a structured slot on MCP responses to surface its own signal (`spelling_candidates`, `token_cost_estimate`, `degradation`, `truncation`, ...). Until it lands, signals ship as ad-hoc prose: #226's `platform_filter_partial` notice (PR #731), #640's per-source degradation, #645's tools-list `disabledReason` each invented their own markdown shape, and AI clients must parse prose to recover them.

The 2025-11-25 MCP spec already provides the right slots, so cupertino does not invent a field:

- **`structuredContent`** on `CallToolResult`: model-visible typed output, validated against the tool's declared `outputSchema`.
- **`_meta`**: data for the client application, explicitly not exposed to the model, namespaced `prefix/name`.

The dual-emission pattern (prose for humans in `content`, structured for machines in `structuredContent` / `_meta`) is the empirically-validated state of the art for transparent conversational IR (Łajewska et al., WSDM 2024, dimensions 3 + 4: articulate confidence, reveal limitations; CUT, ICTIR 2025, functional + operational uncertainty for utilitarian systems). See the prior-art doc (Phase 1 deliverable, below).

## 2. Goals

- One structured, spec-conformant surface for all current and future MCP response signals.
- Two visibility tiers driven by spec semantics: model-visible (`structuredContent`) vs client-only (`_meta` under `cupertino.tools/`).
- Additive and backward-compatible: clients that ignore the new slots see no change; prose notices stay for at least one minor release.
- A real proof-of-concept: migrate #731's `platform_filter_partial` to a structured twin.
- Each dependent issue (#10/#21/#70/#271/#517/...) becomes a small follow-up that adds one signal, citing this design and the spec doc.

## 3. Non-goals

- A new top-level field like `diagnostic` on `CallToolResult` (rejected: non-conformant, conflicts with the spec slots; see Alternatives).
- Removing the prose notices (#226/#640/#731). They keep serving human-CLI consumers across at least one minor release.
- A JSON-only MCP output mode (that is #517's `search_agent` concern).
- Streaming/partial-response signals (MCP does not stream today).
- Signals on the CLI transport (markdown prose already conveys them there).

## 4. The constraint: where the wire types live

`MCPCore` (cupertino) re-exports the external `SwiftMCPCore` (Package.swift: `.product(name: "SwiftMCPCore", ...)`, pinned `from: 0.1.0`). At v0.1.0:

```swift
// SwiftMCPCore/MCP.Core.Protocols.Tool.swift
public struct Tool: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema          // <- no outputSchema
}
public struct CallToolResult: Codable, Sendable {
    public let content: [ContentBlock]
    public let isError: Bool?                    // <- no structuredContent, no _meta
}
```

There are two ways to get structured signals onto the wire:

- **(A) Extend the types upstream in SwiftMCPCore** (recommended). Type-safe, spec-conformant, reusable by `SwiftMCPClient` for symmetric decoding.
- **(B) Hand-serialize the JSON-RPC result in cupertino's server**, bypassing `CallToolResult`'s `Codable`. Rejected: fragile, untyped, duplicates the encoder, and `SwiftMCPClient` could not decode the round-trip in tests.

We take (A). It makes Phase 0 a prerequisite the #742 issue did not account for.

## 5. Design

### Phase 0 (upstream, SwiftMCPCore v0.2.0, maintainer-gated)

Add three optional fields, all backward-compatible (absent encodes to nothing, decode tolerates absence):

```swift
public struct Tool {
    // ...
    public let outputSchema: JSONSchema?         // new, optional
}
public struct CallToolResult {
    public let content: [ContentBlock]
    public let isError: Bool?
    public let structuredContent: JSONValue?     // new, optional, model-visible
    public let meta: [String: JSONValue]?        // new, optional; CodingKeys maps to "_meta"
}
```

`JSONValue` is SwiftMCPCore's existing dynamic JSON type (the same one `AnyCodable` wraps); no new primitive needed. Encoding omits each field when nil (`encodeIfPresent`). This is a pure additive change: existing callers compile unchanged because the new fields have defaulted inits.

Cut `SwiftMCPCore v0.2.0`, then bump cupertino's pin (`from: "0.2.0"`). **Publishing the release is the maintainer's call** (it is a GitHub release of a separate public package); the cupertino PR cannot merge green until the pin resolves.

### Phase 1 (cupertino, one PR, after the pin bump)

1. **Per-signal Codable structs** in cupertino's `MCPCore` (the re-export/composition layer, not the neutral upstream):
   - `SpellingCandidate { token, suggestion, editDistance }`
   - `PlatformFilterPartial { filteredSources, unfilteredSources, reason }`
   - `Degradation { source, reason }`
   - `Truncation { reason, chunksDropped }`
   - Each `Codable`, fields optional unless semantically required, and an opaque catch-all so decoders tolerate unknown keys (forward-compat for future signals).

2. **A `DiagnosticSignals` aggregate** that an emitter builds and encodes into `structuredContent`, **omitting empty signals** (no key emitted for a nil/empty signal; if all are empty, `structuredContent` itself stays nil so the response is byte-identical to today).

3. **`_meta` helpers** under the non-reserved `cupertino.tools/` prefix: `token-cost-estimate`, `per-source-stats`, `cache-hit`. A small builder produces the `[String: JSONValue]` map, returning nil when empty.

4. **Per-tool `outputSchema`** in `SearchToolProvider/CompositeToolProvider`: each tool that can emit signals declares a JSON Schema for its `structuredContent`. The schema declares which keys MAY appear, not which MUST.

5. **Proof-of-concept migration (#731):** `Search.PlatformFilterScope` already emits the `platform_filter_partial` prose blockquote. Keep it; additionally populate `structuredContent.platform_filter_partial`. This proves the end-to-end path with a real signal.

6. **Docs:** `docs/protocols/mcp-diagnostic-block.md` (the canonical signal catalog, indexed by Łajewska's four dimensions, each signal tagged with the CUT dimension it reduces, every `cupertino.tools/` key enumerated) and `docs/research/mcp-diagnostic-block-prior-art.md` (the anchor-paper survey; does not exist yet).

7. **Tests:** `Issue742DiagnosticBlockSchemaTests` pin each struct's shape, JSON round-trips, omit-empty behaviour (empty signal → absent key; no signals → nil `structuredContent` and nil `_meta`), unknown-key tolerance, and the #731 twin. Plus one live MCP probe asserting `structuredContent.platform_filter_partial` is present and shaped on a platform-filtered query (assert on a semantic marker, not length).

### Signal catalog

Model-visible (`structuredContent`, validated by `outputSchema`):

| Signal | Purpose | Łajewska dim |
|---|---|---|
| `spelling_candidates` | suggested rewrites, lets the model retry | (3) confidence |
| `platform_filter_partial` | which sources were not platform-filtered, and why | (4) limitations |
| `degradation` | per-source error/unavailable classification | (4) limitations |
| `truncation` | result clipped at a token budget | (4) limitations |

Client-only (`_meta`, `cupertino.tools/` prefix):

| Key | Purpose | CUT dim |
|---|---|---|
| `cupertino.tools/token-cost-estimate` | tokens this response costs the client context | operational |
| `cupertino.tools/per-source-stats` | per-source latency / rows scanned | operational |
| `cupertino.tools/cache-hit` | served from cache | operational |

### Worked example (populated response)

```json
{
  "content": [{ "type": "text", "text": "...markdown body..." }],
  "structuredContent": {
    "spelling_candidates": [{ "token": "searchabe", "suggestion": "searchable", "edit_distance": 1 }],
    "platform_filter_partial": {
      "filtered_sources": ["apple-docs", "packages"],
      "unfiltered_sources": ["hig"],
      "reason": "user-requested platform filter"
    }
  },
  "_meta": { "cupertino.tools/token-cost-estimate": 1842 }
}
```

A response with nothing to flag emits neither block: identical bytes to today.

## 6. Rollout / phasing

1. **Phase 0 (upstream, maintainer-gated):** SwiftMCPCore v0.2.0 adds `outputSchema` + `structuredContent` + `_meta`; publish; bump cupertino pin.
2. **Phase 1 (cupertino, one PR):** signal structs + aggregate + `_meta` helpers + per-tool `outputSchema` + #731 twin + docs + tests. Lands before any dependent issue uses it.
3. **Dependents (follow-ups, 1 to 2 days each):** #10 adds `spelling_candidates`, #271 adds `truncation` + `token-cost-estimate`, #517 routes `search_agent` output here, etc. Each cites this doc and the spec doc.

This revises the #742 body's "ship as one PR" claim: Phase 0 is a separate, upstream, maintainer-gated prerequisite. The cupertino work is still one PR, but it is gated on the SwiftMCPCore release.

## 7. Reliability & failure modes

- **Client negotiated an older protocol version.** `structuredContent` and `_meta` are additive response fields; a client that does not understand them ignores them (JSON decoders skip unknown keys). No negotiation gate needed; emit unconditionally.
- **`structuredContent` does not validate against `outputSchema`.** That is a server bug, not a runtime client error. Tests pin the schema-vs-payload agreement; CI catches drift. The server never rejects its own response.
- **`_meta` namespace collision.** `cupertino.tools/` is non-reserved and is not `mcp.*` / `modelcontextprotocol.*`. Documented and enumerated in the spec doc.
- **Empty-signal noise.** The omit-empty rule guarantees a no-signal response is byte-identical to today, so the change cannot regress existing snapshot tests or token cost.
- **Prose / structured divergence.** During the transition both are emitted from the same source data (e.g. `PlatformFilterScope` builds both), so they cannot disagree.

## 8. Testing strategy

- `Issue742DiagnosticBlockSchemaTests`: per-struct shape pins, round-trips, omit-empty, unknown-key tolerance.
- `outputSchema`-vs-payload agreement test per tool.
- One live MCP probe (per `feedback_mcp_probe_shape_not_length`): a platform-filtered `search` returns `structuredContent.platform_filter_partial` with the expected `unfiltered_sources`; assert the semantic marker, never `len > 0`.
- Backward-compat: a no-signal response encodes with no `structuredContent`/`_meta` keys.

## 9. Alternatives considered

- **New `diagnostic` field on `CallToolResult`** (the pre-2026-05-21 design). Rejected: invents an unrecognised top-level field, non-conformant with the spec slots.
- **Hand-serialize the JSON-RPC result in the server**, leaving SwiftMCPCore untouched. Rejected: untyped, fragile, duplicates the encoder, breaks symmetric decode in `SwiftMCPClient` tests. Phase 0 (typed upstream extension) is worth the maintainer-gated release.
- **Prose only (status quo).** Rejected: the per-feature markdown reinvention this keystone exists to end.

## 10. Open questions

- Phase 0 release cadence: fold the three fields into the next SwiftMCPCore release, or cut a dedicated v0.2.0? (Maintainer's call; gates the cupertino PR either way.)
- Does `SwiftMCPClient` need symmetric decode of `structuredContent`/`_meta` in the same release, or can client-side decode lag? (Recommend same release so round-trip tests are real.)
- `outputSchema` granularity: one shared schema for all signal-bearing tools, or per-tool? (Recommend per-tool; a tool only declares the keys it can emit.)

## 11. Status / references

Status: design only (2026-06-02). Not started. Gated on Phase 0 (SwiftMCPCore extension + release).

- Issue: [#742](https://github.com/mihaelamj/cupertino/issues/742). Parent epic [#268](https://github.com/mihaelamj/cupertino/issues/268). Dependents: #10, #13, #21, #70, #271, #517.
- Migrates: #226 / #640 / #645 prose signals; PR #731 is the POC site (`Search.PlatformFilterScope`).
- Upstream: `mihaelamj/SwiftMCPCore` (the external wire-type package, pinned `0.1.0`).
- Spec: MCP 2025-11-25; RFC #371 (`outputSchema` + `structuredContent`); SEP-1624 (`structuredContent` vs `content`).
- Anchors: Łajewska et al. WSDM 2024 (arXiv 2406.19281); CUT, ICTIR 2025; "LLMs Should Express Uncertainty Explicitly".
- Phase-1 doc deliverables: `docs/protocols/mcp-diagnostic-block.md`, `docs/research/mcp-diagnostic-block-prior-art.md`.
