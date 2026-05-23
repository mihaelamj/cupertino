# MCP diagnostic block prior art

**Date:** 2026-05-21
**Triggers:** #742 design phase
**Status:** Research note. No code landed.

This document captures what cupertino learned about how the broader ecosystem surfaces structured diagnostic information on tool / search responses, **before** committing to an implementation for issue #742. It exists because the original issue body cited two academic papers ("Wang et al. 2025", "Jain et al. 2024") that do not appear anywhere else in the repo, and made no reference to the existing MCP specification provisions that already overlap with the proposed `diagnostic` field. The research below corrects both gaps.

## 1. Question being investigated

Issue #742 proposes adding a new optional sibling field, `diagnostic`, to every `CallToolResult` emitted by cupertino's MCP server. The block carries optional structured signals: `spelling_candidates`, `platform_filter_partial`, `degradation`, `token_cost_estimate`, `truncation`, `info`, etc. Seven other open issues (#10, #13, #21, #70, #271, #517, plus parent epic #268) are sequenced behind it.

Before implementing, two questions:

1. **Does the MCP specification already provide a slot for this kind of structured side-channel?** If yes, cupertino should use the standard slot rather than invent a new field name.
2. **Is there ecosystem convention for naming and shape?** If yes, cupertino should follow it so that AI clients written against other MCP servers can also read cupertino's diagnostics.

## 2. MCP specification findings

The MCP specification version `2025-11-25` (current at time of research) defines four fields on `CallToolResult`:

| Field | Type | Purpose | Visibility |
|---|---|---|---|
| `content` | `ContentBlock[]` | Model-oriented output, optimised for readability and token efficiency. Preferred for conversational agents and direct model prompting. | Model + client |
| `structuredContent` | `object` (optional) | Machine-oriented output for programmatic tool use, code generation, type-safe orchestration, strict schema validation. Must validate against the tool's declared `outputSchema`. | Model + client |
| `isError` | `boolean` (optional) | Error indicator on the response itself. | Both |
| `_meta` | `object` (optional, inherited from `Result` base) | "Data to client applications without exposing it to the model." Spec text: passes carry-along data the model should not see. | **Client only** (model-hidden) |

Two of these are highly relevant to #742's intent.

### 2.1 `structuredContent` (added 2025-06-18 via SEP / PR #371)

Tools can declare an `outputSchema` (JSON Schema). When they do, every response **must** include `structuredContent` whose value validates against that schema. The motivating example in PR #371 is a weather tool returning `{ "temperature": 22.5, "conditions": "Partly cloudy", "humidity": 65 }` rather than serialised text in `content`.

Two open spec discussions are worth noting:

- **PR #371 itself** explicitly does not address diagnostic / uncertainty surfacing. The intent is strictly schema validation. So `structuredContent` is positioned today as "the tool's typed output," not "the tool's typed output plus warnings."
- **SEP-1624** ("Clarify `structuredContent` vs `content` Usage") is in open-discussion status. It clarifies that `content` is model-oriented prose and `structuredContent` is machine-oriented typed data, and acknowledges the question of how to surface non-fatal diagnostics is unresolved.

### 2.2 `_meta`

`_meta` is the spec-sanctioned channel for **client-only metadata** that the model should not see. Examples cited in the wild include token usage, cost information, internal flags, and performance metrics. The Microsoft `agent-framework` bug report ([issue #2284](https://github.com/microsoft/agent-framework/issues/2284)) describes `_meta` as carrying "critical metadata" that should be "preserved" and "passed through" to applications.

The 2025-11-25 spec defines a strict naming convention for `_meta` keys:

> Valid `_meta` key names have two segments: an optional prefix, and a name. Prefix: If specified, MUST be a series of labels separated by dots (`.`), followed by a slash (`/`).
>
> Any prefix beginning with zero or more valid labels, followed by `modelcontextprotocol` or `mcp`, followed by any valid label, is reserved for MCP use. For example: `modelcontextprotocol.io/`, `mcp.dev/`, `api.modelcontextprotocol.org/`, and `tools.mcp.com/` are all reserved.

For cupertino this means:

- A custom prefix like `cupertino.tools/` or `cupertino.io/` is acceptable.
- Bare key names without a prefix are acceptable.
- A prefix containing `mcp` or `modelcontextprotocol` is forbidden (reserved).
- Cupertino must not assume values at reserved keys.

### 2.3 The gap

Despite providing `_meta` and `structuredContent`, **the MCP specification does not define any convention for surfacing diagnostic signals** (warnings, partial results, source degradation, spelling suggestions, truncation notices, token cost estimates). SEP-1624 acknowledges the gap. PR #371 explicitly punts on it.

This is significant: cupertino's #742 is not the only project that needs this. The convention is unsettled at the protocol level.

## 3. MCP servers in the wild

Searches across the modelcontextprotocol/servers reference repository and community MCP server lists turned up **no MCP server today that emits structured diagnostic signals through `_meta` or `structuredContent`** for the use cases cupertino cares about (degraded source, partial filter, spelling correction, truncation, cost estimate).

Existing diagnostic-shaped MCP servers, when they exist, expose the diagnostic surface **as a tool**, not as a sidecar metadata channel:

- The SpellChecker MCP server is a *tool* that LLMs call to check spelling on text, not a metadata field other tools attach to their responses.
- Anthropic's diagnostic / troubleshooter servers (windows-diagnostic-mcp-server, mcp-troubleshooter-mcp) return diagnostic information as their primary `content`.
- The LSP MCP server forwards Language Server Protocol diagnostics as tool responses, again primary `content`.

The Anthropic article "Code execution with MCP" does not discuss metadata or diagnostic conventions at all. It focuses on enabling agents to write code that calls MCP servers as APIs.

**Conclusion: cupertino #742 is filling a real ecosystem gap.** No existing MCP server provides prior art for the specific pattern cupertino wants. Cupertino has an opportunity to either (a) pick a convention and ship it, or (b) propose a SEP back to MCP so the convention is standardised.

## 4. Adjacent ecosystem evidence

### 4.1 LangChain `ToolMessage.artifact`

LangChain (the most-cited Python framework for LLM tool orchestration) explicitly added a sidecar metadata channel called `artifact` to its `ToolMessage` type in mid-2024. The blog post "Improving core tool interfaces and docs in LangChain" describes it as:

> Results needed in downstream components but that should not be part of the content sent to the model

This is the exact conceptual slot MCP calls `_meta`. The two protocols converge on the same design: tool output has a model-visible channel (`content`) and a model-hidden channel (`artifact` / `_meta`). LangChain returns a `(content, artifact)` tuple when a tool's `response_format` is `"content_and_artifact"`.

This confirms the design pattern cupertino needs is real and consistent across the field, not cupertino-specific.

### 4.2 OpenAI function calling

OpenAI's function-calling API (the original tool-use protocol pre-MCP) has:

- `strict: true` mode that guarantees the model's *call arguments* match a JSON Schema. (This is about the model's output to the tool, not the tool's output to the model.)
- A `refusal` field that surfaces the model's refusal to call the tool (model-side signal, not tool-side).
- **No convention** for surfacing tool-side diagnostic information. Tools return free-form JSON in their tool-output messages; any diagnostic structure is invented per-tool.

So OpenAI's protocol does not constrain the diagnostic-block design. Cupertino can use any convention without conflicting with OpenAI clients.

### 4.3 Retrieval-augmented generation literature

The active RAG literature (URAG benchmark, "Decide Then Retrieve", "RQ-RAG", "Modeling Uncertainty Trends for Timely Retrieval in Dynamic RAG", 2024-2026) addresses uncertainty quantification **on the generated answer**, typically via conformal prediction or confidence calibration. The output of these methods is a single uncertainty score per response, sometimes a calibrated probability of correctness.

This is **adjacent but not directly applicable** to cupertino's #742. Cupertino's diagnostic block surfaces retrieval-side metadata (which sources contributed, which were filtered, whether the corpus was complete) rather than answer-side uncertainty. The two should not be conflated.

The papers cited in #742's body (Wang et al. 2025, Jain et al. 2024) could not be verified, no specific titles or DOIs were given, and the search did not turn up canonical entries by those authors that match the claimed framing. They are likely not real. They should be replaced in the issue body with the verifiable citations introduced in section 4.4 below.

### 4.4 Scientific foundation for the diagnostic block

The literature on **structured uncertainty surfacing in conversational information-seeking** is more directly applicable to #742 than general RAG uncertainty work. The two anchor papers below define the conceptual vocabulary cupertino should adopt.

### 4.4.1 Łajewska et al., WSDM 2024 (the primary anchor)

**Citation:** Łajewska, W. et al. *"Grounded and Transparent Response Generation for Conversational Information-Seeking Systems."* Proceedings of the 17th ACM International Conference on Web Search and Data Mining (WSDM '24). [DOI 10.1145/3616855.3635727](https://doi.org/10.1145/3616855.3635727), [arXiv 2406.19281](https://arxiv.org/abs/2406.19281).

This paper articulates the four-dimension response framework that maps directly onto cupertino's signal needs:

> Responses should: (1) synthesize the requested information, (2) ground it in specific facts identified in the passages, (3) articulate the system's confidence, and (4) reveal the system's limitations.

Mapped onto cupertino's MCP responses:

| Łajewska dimension | Cupertino surface |
|---|---|
| (1) Synthesise information | `content` (existing, the prose result body) |
| (2) Ground in specific facts | `content` + per-result URIs (existing) |
| (3) Articulate confidence | `structuredContent` per-result rank score + diagnostic signals like `spelling_candidates`, `truncation` (this issue) |
| (4) Reveal limitations | `structuredContent` signals like `platform_filter_partial`, `degradation`, plus `_meta` for client-only limitations like `token_cost_estimate` (this issue) |

The paper's "information nugget" concept (atomic units of relevant information paired with reliability indicators) maps to cupertino's per-result entry shape; this is already shipped via the existing result format. The paper's emphasis on **system-limitation communication** is the load-bearing rationale for #742: a search system that cannot communicate its limitations forces the consumer to either trust blindly or re-derive limitations from prose.

The follow-up paper **GINGER** (Grounded Information Nugget-based GEneration of Responses) by the same group won the Automated Generation task at TREC RAG'24, demonstrating that the nugget-plus-confidence approach is empirically validated, not just an academic proposal.

### 4.4.2 Chatbot Uncertainty Taxonomy (CUT), ICTIR 2025 (the user-side anchor)

**Citation:** *"Retrieving Under Uncertainty: Towards a Chatbot Uncertainty Taxonomy (CUT) for Information Retrieval."* Proceedings of the 2025 International ACM SIGIR Conference on Innovative Concepts and Theories in Information Retrieval (ICTIR '25). [DOI 10.1145/3731120.3744580](https://doi.org/10.1145/3731120.3744580).

CUT proposes five dimensions of user-perceived uncertainty in chatbot IR, validated via a 50-participant survey across hedonic and utilitarian scenarios:

| Dimension | Meaning |
|---|---|
| **Functional** | Will the system perform the task? Will it return useful results? |
| **Operational** | Is the system reliable, fast, correctly configured? |
| **Ethical** | Is the response biased, factual, fair? |
| **Privacy-related** | Is the query / context handled safely? |
| **Relational** | Is the system trustworthy as a conversational partner? |

Empirical findings of direct relevance to cupertino:

- **Functional uncertainty prevails in all scenarios.** This is what cupertino's diagnostic block primarily addresses (did the system actually answer the question, was the answer grounded in the corpus, were sources missing).
- **Operational uncertainty dominates utilitarian settings** (which cupertino is, agents using it as a tool, not a casual chatbot). Signals like `degradation` (was a source down), `truncation` (was the answer clipped), and `token_cost_estimate` (resource accounting) map onto this dimension.
- **Privacy and relational uncertainty matter more for known systems** than first-time interactions. Less directly relevant to cupertino since the corpus is fixed and the queries are not personal data.

The CUT framework tells cupertino which signals matter most: **functional and operational signals should be first-class, structured, and visible to the consumer** because those are the dimensions that dominate when an agent is using cupertino as a tool. Ethical, privacy, and relational signals are lower priority for this use case.

### 4.4.3 LLMs Should Express Uncertainty Explicitly (arXiv 2604.05306)

**Citation:** *"LLMs Should Express Uncertainty Explicitly."* [arXiv 2604.05306](https://arxiv.org/pdf/2604.05306).

This paper validates the core principle of #742: rather than relying on implicit token-probability signals, systems should emit explicit, structured uncertainty alongside the primary response. Key takeaways for cupertino:

- API designs should "surface uncertainty as explicit output fields alongside predictions."
- Designs should support both "natural language uncertainty expressions and structured confidence metrics", which is exactly the dual-emission policy cupertino is proposing (prose stays in `content`, structured stays in `structuredContent`).
- Distinguish human-facing uncertainty (interpretable language) from machine-facing uncertainty (parseable structured fields). Cupertino does this naturally via the `content` vs `structuredContent` split.

### 4.4.4 Explainability for Transparent Conversational Information-Seeking

**Citation:** *"Explainability for Transparent Conversational Information-Seeking."* [arXiv 2405.03303](https://arxiv.org/pdf/2405.03303).

A SIGIR-adjacent paper extending the transparency theme. The full text was not fully extractable from the PDF in this research pass, but the abstract and search-result summaries confirm the general principle: **conversational IR systems should identify and communicate any potential limitations to users** so that consumers can evaluate response quality. This generalises Łajewska's dimension (4).

### 4.4.5 Conversational Gold (SIGIR '25)

**Citation:** *"Conversational Gold: Evaluating Personalized Conversational Search System Using Gold Nuggets."* Proceedings of the 48th International ACM SIGIR Conference on Research and Development in Information Retrieval. [DOI 10.1145/3726302.3730316](https://doi.org/10.1145/3726302.3730316), [arXiv 2503.09902](https://arxiv.org/abs/2503.09902).

Defines **gold nuggets** as "concise, essential pieces of information extracted from relevant passages which serve as a foundation for automatic response evaluation." Relevant to cupertino because it cements information-nugget evaluation as a standard methodology in SIGIR. Cupertino's per-result entries are conceptual information nuggets; their associated diagnostic signals (confidence, source attribution) extend the nugget representation in a way consistent with this literature.

### 4.4.6 Synthesis

The scientific position is settled enough to ground cupertino's design:

1. **Structured uncertainty surfacing IS the academic state-of-the-art** for conversational IR systems (Łajewska 2024, CUT 2025, arXiv 2604.05306).
2. **The four-dimension framework** (synthesise, ground, articulate confidence, reveal limitations) is empirically validated via GINGER's TREC RAG'24 win.
3. **The user-facing dimensions that dominate in utilitarian (cupertino-shaped) use cases** are functional and operational, per CUT's survey.
4. **Dual emission** (prose for humans + structured for machines) is the recommended API pattern, matching what MCP already provides via `content` + `structuredContent`.

Cupertino's #742 is therefore not inventing a new pattern. It is implementing a well-validated academic framework over the spec's existing extensibility slots.

### 4.5 Search APIs outside the tool-use space

Elasticsearch and similar search engines surface partial-results signals via response-level fields (`timed_out`, `_shards.failures[]`, `_shards.skipped`). The convention is **a flat sibling-of-`hits` field** in the response, not a nested metadata block. GraphQL APIs use a top-level `errors` array alongside `data` for the same purpose.

The cross-ecosystem pattern is consistent: structured-diagnostic info goes in a **named sibling field** at the response root, not embedded in the result body. MCP's `_meta` and `structuredContent` both fit this pattern.

## 5. Implications for the #742 design

The #742 issue body, as written 2026-05-21, proposes:

> A structured object appended to every MCP tool response (where present) carrying machine-readable signals that complement the human-readable result body.

The proposed shape is a new `diagnostic` field as a sibling to `content`:

```json
{
  "content": [...],
  "diagnostic": { "platform_filter_partial": ..., "spelling_candidates": ..., ... }
}
```

This shape **conflicts with the existing MCP spec** in two ways:

1. **The slot name `diagnostic` is not a spec-recognised field on `CallToolResult`.** Adding it makes cupertino's MCP responses non-conformant; clients that strictly type-check `CallToolResult` will reject the unexpected key. (The spec uses additive optional fields like `_meta` and `structuredContent` precisely to avoid this.)
2. **The intent (machine-readable signals alongside human-readable content) is already served by `_meta` and `structuredContent`.** Inventing a third slot duplicates the protocol's existing extensibility points.

### 5.1 Recommended pivot

Implement #742 using the spec-provided slots. Concretely:

| Signal | Goes in | Rationale |
|---|---|---|
| `spelling_candidates` | `structuredContent` | Model needs to see them to retry the query with a correction. Schema published in `outputSchema`. |
| `platform_filter_partial` | `structuredContent` | Model needs to know which sources were filtered to reason about result completeness. |
| `degradation` (per-source) | `structuredContent` | Model needs to know "apple-archive failed, results are missing that source." Client may also lift this for a UI badge. |
| `truncation` | `structuredContent` | Model needs to know the result was clipped at the token budget so it can request a follow-up. |
| `token_cost_estimate` | `_meta` (key `cupertino.tools/token-cost-estimate`) | Client-only concern (cost UI, monitoring, billing). Model should not see this. |
| `info` (general infos) | depends on signal | Client-only infos → `_meta`. Model-relevant infos → `structuredContent`. |

This gives cupertino:

- **Spec conformance**: every signal lands in a spec-recognised field.
- **Namespace hygiene**: `_meta` keys carry a `cupertino.tools/` prefix per the reserved-prefix convention.
- **Model / client separation**: signals the model needs are visible to it; signals only the client needs are hidden.
- **Backward compat**: existing clients that ignore `structuredContent` and `_meta` see no change.

### 5.2 What changes in #742's acceptance criteria

Current `## Acceptance` calls for `MCP.Core.Protocols.DiagnosticBlock` struct as a new sibling on `CallToolResult`. After the pivot:

- Drop the `DiagnosticBlock` struct + new field on `CallToolResult`. The spec's existing slots replace it.
- Add a Codable struct per signal type (`PlatformFilterPartial`, `Degradation`, `SpellingCandidates`, `Truncation`, `TokenCostEstimate`).
- For each tool emitting structured signals, declare its `outputSchema` and route signals into `structuredContent`.
- For client-only signals, route into `_meta` under `cupertino.tools/` prefix.
- The proof-of-concept migration (PR #731's `platform_filter_partial` prose notice) lands under `structuredContent`, not under a new `diagnostic` field.
- The docs page (currently planned at `docs/protocols/mcp-diagnostic-block.md`) becomes a spec for cupertino's `outputSchema` declarations and its `_meta` key namespace, not a new field.

### 5.3 Sequencing implication

The work is **the same size or smaller** than the original plan. The seven dependent issues (#10, #13, #21, #70, #271, #517) still each add their own signal as a small follow-up; only the slot changes from `diagnostic.spelling_candidates` to `structuredContent.spelling_candidates` (or `_meta`, depending on the signal). The keystone PR for #742 still ships:

1. The per-signal Codable structs.
2. The `outputSchema` declarations for every tool that emits structured signals.
3. The `_meta` helpers with the `cupertino.tools/` prefix.
4. One signal migrated end-to-end as proof.
5. The spec doc, repurposed as cupertino's diagnostic-namespace catalog.
6. Tests pinning the schema + namespace.

### 5.4 Optional follow-up

Once cupertino's implementation is settled, consider proposing a SEP to MCP that adds a standard `diagnostic` convention for `structuredContent`-style signals (e.g., a recommended key path under `structuredContent` or a sub-schema convention). This would standardise the convention upstream so other MCP servers can adopt it. Optional, not blocking.

## 6. References

### Protocol and ecosystem

- [MCP Specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)
- [MCP Specification 2025-06-18 schema](https://modelcontextprotocol.io/specification/2025-06-18/schema)
- [MCP TypeScript schema (raw, schema.ts on main)](https://raw.githubusercontent.com/modelcontextprotocol/specification/main/schema/2025-11-25/schema.ts)
- [RFC #371: add `Tool.outputSchema` and `CallToolResult.structuredContent`](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/371)
- [SEP-1624: Clarify `structuredContent` vs `content` usage](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1624)
- [Microsoft agent-framework issue #2284 (CallToolResult `_meta` field semantics)](https://github.com/microsoft/agent-framework/issues/2284)
- [LangChain tool artifacts documentation](https://python.langchain.com/docs/how_to/tool_artifacts/)
- [LangChain `ToolMessage` reference](https://reference.langchain.com/python/langchain-core/messages/tool/ToolMessage)
- [Anthropic: Code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp)
- [OpenAI function calling guide](https://developers.openai.com/api/docs/guides/function-calling)
- [OpenAI structured outputs guide](https://developers.openai.com/api/docs/guides/structured-outputs)
- [GraphQL specification, Section 7: Response](https://github.com/graphql/graphql-spec/blob/main/spec/Section%207%20--%20Response.md)
- [Elasticsearch REST API conventions](https://www.elastic.co/guide/en/elasticsearch/reference/current/api-conventions.html)
- [Elastic blog: scoped search suggestions and query corrections](https://www.elastic.co/blog/how-to-build-scoped-search-suggestions-and-search-query-corrections)

### Scientific foundation

- Łajewska, W. et al. *"Grounded and Transparent Response Generation for Conversational Information-Seeking Systems."* WSDM '24. [DOI 10.1145/3616855.3635727](https://doi.org/10.1145/3616855.3635727) | [arXiv 2406.19281](https://arxiv.org/abs/2406.19281). **Primary anchor.**
- *"Retrieving Under Uncertainty: Towards a Chatbot Uncertainty Taxonomy (CUT) for Information Retrieval."* ICTIR '25. [DOI 10.1145/3731120.3744580](https://doi.org/10.1145/3731120.3744580). **User-side anchor.**
- *"LLMs Should Express Uncertainty Explicitly."* [arXiv 2604.05306](https://arxiv.org/pdf/2604.05306).
- *"Explainability for Transparent Conversational Information-Seeking."* [arXiv 2405.03303](https://arxiv.org/pdf/2405.03303).
- *"Conversational Gold: Evaluating Personalized Conversational Search System Using Gold Nuggets."* SIGIR '25. [DOI 10.1145/3726302.3730316](https://doi.org/10.1145/3726302.3730316) | [arXiv 2503.09902](https://arxiv.org/abs/2503.09902).
- *"ICR: Iterative Clarification and Rewriting for Conversational Search."* EMNLP '25. [ACL Anthology 2025.emnlp-main.496](https://aclanthology.org/2025.emnlp-main.496/).
- *"To Retrieve or Not to Retrieve? Uncertainty Detection for Dynamic Retrieval Augmented Generation."* [arXiv 2501.09292](https://arxiv.org/pdf/2501.09292).
- *"Uncertainty Quantification for Retrieval-Augmented Reasoning."* [arXiv 2510.11483](https://arxiv.org/html/2510.11483v1).
- *"Faithfulness-Aware Uncertainty Quantification for Fact-Checking the Output of Retrieval Augmented Generation."* [arXiv 2505.21072](https://arxiv.org/pdf/2505.21072).
- *"Modeling Uncertainty Trends for Timely Retrieval in Dynamic RAG."* [arXiv 2511.09980](https://arxiv.org/pdf/2511.09980).
- *"URAG: A Benchmark for Uncertainty Quantification in Retrieval-Augmented Large Language Models."* [arXiv 2603.19281](https://arxiv.org/pdf/2603.19281).
- *"Not All Relevance Scores are Equal: Efficient Uncertainty and Calibration Modeling for Deep Retrieval Models."* [arXiv 2105.04651](https://arxiv.org/pdf/2105.04651).

## 7. Open follow-ups

- Replace the unverifiable "Wang et al. 2025 + Jain et al. 2024" citations in #742's body with the real anchors from section 4.4 (Łajewska 2024 + CUT 2025 + arXiv 2604.05306 at minimum).
- Update #742's `## Fix` and `## Acceptance` sections to reflect the spec-aligned design (use `structuredContent` + `_meta` instead of a new `diagnostic` field).
- Add a new bullet under the spec doc's outline: a catalogue of cupertino's reserved `_meta` keys under the `cupertino.tools/` prefix.
- Adopt Łajewska's four-dimension framework (synthesise / ground / articulate confidence / reveal limitations) as the structural index for the spec doc. Each cupertino signal type then has a one-line citation back to which dimension it serves.
- Adopt CUT's functional/operational/ethical/privacy/relational taxonomy as a secondary index: every signal cupertino emits should declare which user-uncertainty dimension it reduces. This is the empirical justification for shipping the signal.
- Optional: draft a SEP for upstream MCP that standardises a diagnostic convention. Defer until cupertino's own implementation has shipped and proven the pattern. If cupertino contributes back, cite Łajewska + CUT as the academic foundation for the proposal.
