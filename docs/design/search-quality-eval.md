# Design: search-quality evaluation harness

| Field | Value |
|---|---|
| **Status** | draft |
| **Created** | 2026-05-20 |
| **Last revised** | 2026-05-20 |
| **Tracking issue** | none yet |
| **Companion docs** | `docs/architecture/database.md` (what the system is), `mihaela-agents/Rules/universal/search-quality-eval.md` (the universal IR methodology rule this design specialises) |

---

## TL;DR

Cupertino has two co-equal success criteria, and this design addresses both with a phased evaluation strategy. **Criterion 1 (good search):** for any query, the right doc appears near the top of the result list. **Criterion 2 (anti-hallucination grounding for AI coding agents):** the agent, given cupertino's top-K results, produces correct, currently-shipping, availability-correct Swift. Phase 1 (cheap, ~30 min, no human judging) addresses a slice of Criterion 1: ~50 canonical-lookup queries with known right-answer URI patterns, MRR / P@1 / P@5 / NDCG@10, paired Wilcoxon on MRR. Phases 1.1-1.6 extend Criterion 1 to the other query classes (deprecation-aware, cross-source canonical, CamelCase fragment, acronym, prose, symbol-attribute) in priority order. Phase 2 upgrades Criterion 1 to TREC-grade human pooling when warranted. **Phase 1.7 addresses Criterion 2:** ~30 hand-curated Swift coding tasks, run with vs without cupertino grounding, scored on "does the produced code compile and call only real / current / availability-correct symbols." Phase 1.7 is the actual success measure; Phase 1 is the cheap proxy. The first concrete artefact (Phase 1 harness) lives at `scripts/eval/search-quality-phase1.py` (forthcoming) and produces a JSON results dump plus a human-readable report. Phase 1.7 is its own follow-up design (`docs/design/anti-hallucination-eval.md`, not yet written).

---

## 1. Context

### 1.1 Problem

Cupertino ships periodic rebuilds of `search.db` driven by corpus changes (more Apple frameworks indexed), enrichment changes (new AST extraction, new symbolgraph integration, new framework synonyms), schema changes (new columns, new tables, new FTS5 weights), and engine-tuning changes (FTS5 PRAGMAs, automerge configuration). When a new build is produced, we want to claim either "the new build is better" or "no regression" with rigour, not from anecdote.

The class of question this design addresses is exactly: **for two `search.db` files A and B, is search quality better, worse, or unchanged on B vs A?**

### 1.2 Why the obvious approaches don't work

- *"Run a few queries and eyeball."* Eight cherry-picked queries are an anecdote, not an evaluation. Rank metrics have terrible discrimination below ~30 queries.
- *"Compare row counts."* More indexed documents is a recall-side signal at best. It tells us nothing about ranking quality. Two databases can have identical counts and very different first-result quality.
- *"Compare schema versions."* Says nothing about ranking, only about the indexer's substrate.
- *"Have an LLM judge."* No IR conference accepts LLM-as-primary-judge as of late 2025. Acceptable as a pre-screen; not as evidence of record.
- *"Trust user feedback."* Self-selected, biased toward negative reports, low sample size, no per-query pairing.

### 1.3 Why now

Two recent events made this necessary. (a) The v1.2.0 reindex on 2026-05-19/20 produced a new `search.db` that needed to be defended against the v1.1.0 brew bundle; the question "is the new one better" was answered with ad-hoc anecdotes that did not meet the project's "no nonsense" bar. (b) The experimental A+B FTS5 mitigations on branch `exp/800` need a rigorous quality check before promotion (cupertino-internal issue #800).

### 1.4 The query workload (domain taxonomy)

Apple-platform developer search has a recognisable shape, and treating every query as the same kind of question is wrong. We identify eight query classes that cupertino's users actually issue, each with a different notion of what makes a result "correct" and a different appropriate metric. Any honest evaluation has to either restrict to one class explicitly (this design's Phase 1 path) or measure each class on its own terms (Phase 1.x follow-ups).

| Class | Description | Example query | Notion of "correct" | Appropriate metric |
|---|---|---|---|---|
| **A. Canonical lookup** | "Where is X defined?" — single concept with one canonical URI | `Hashable`, `URLSession`, `LazyVGrid` | URI matches `apple-docs://<framework>/<concept>($\|/)` | MRR, P@1 |
| **B. Framework-root** | "Open the framework" | `SwiftUI`, `Combine`, `WidgetKit` | URI is the framework root | MRR, P@1 |
| **C. Acronym / synonym** | Framework or concept by abbreviation | `NFC` → CoreNFC, `CK` → CloudKit | Result is the canonical framework, not a literal-token match | MRR (relies on `framework_aliases.synonyms`) |
| **D. CamelCase fragment** | Component of a compound identifier | `Grid` should retrieve `LazyVGrid`, `LazyHGrid`; `Decoder` should retrieve `JSONDecoder`, `PropertyListDecoder` | Top-K contains all canonical components in the namespace | P@5, P@10 (relies on `symbol_components`, #77) |
| **E. Deprecation-aware** | A concept exists in both modern (Swift) and legacy (Objective-C / NS-prefixed) form | `URLSession`, `NotificationCenter`, `FileManager` | The Swift form ranks above the deprecated form | Pairwise: rank(Swift) < rank(legacy) per query; aggregate as a paired sign test |
| **F. Cross-source canonical** | A concept lives in multiple sources at different authority | `Swift 6 concurrency`, `Observation framework migration` | Top-1 from the highest-authority source that has a hit (per RRF source weights) | MRR on per-source canonical answer |
| **G. Prose / conceptual** | Multi-word question, no single canonical URI | `actor reentrancy semantics`, `how does Observable invalidate views` | A small set of pages explains the concept | R-Precision or NDCG@10 with size-of-relevant-set ≥ 1 |
| **H. Symbol-attribute** | Find things by attribute or signature | `@MainActor properties on View`, `async throws functions returning String` | Many valid answers, no canonical one | P@k only; MRR is meaningless |

This design's Phase 1 covers **classes A, B, and partially C** (the regex patterns admit some acronym-driven queries). Classes D, E, F, G, H are explicit out-of-scope in this design and become Phase 1.x companion designs each.

### 1.5 Ultimate goal: both good search AND anti-hallucination grounding

Cupertino has two co-equal success criteria, neither of which subsumes the other. Any evaluation that addresses only one is incomplete.

**Criterion 1 — good search.** For a query a human or agent issues, cupertino returns the right doc near the top of the result list. This is the classical IR-quality framing. Metrics: MRR, P@k, NDCG@k, R-Precision per the taxonomy in §1.4. Failure mode: the user (human or agent) reads the top-K and the doc they need is not there or is buried.

**Criterion 2 — anti-hallucination grounding for AI coding agents.** Per README.md ("No more hallucinations: AI agents get accurate, up-to-date Apple API documentation") and design/cupertino.md §1.1 ("AI coding agents need accurate, current Apple API references to avoid generating code that calls nonexistent symbols, uses deprecated APIs, or violates platform availability constraints"). Cupertino's most valuable consumer is an LLM-driven coding agent with a Swift task in flight, ~3-5 MCP results worth of token budget, and a tendency to invent plausible-sounding APIs that don't exist. The success criterion is "the agent generated correct, currently-shipping, availability-correct Swift" because cupertino put the right doc in front of it. Failure mode: agent writes `foo.bar()` that doesn't exist, calls `NSURLConnection` on a Swift 6 codebase, or assumes a SwiftUI 17 API is available on macOS 13.

The two criteria overlap (good search is a precondition for good grounding) but are not the same. A canonical-lookup MRR delta tells us about Criterion 1. A "does the agent compile" delta tells us about Criterion 2. The full evaluation needs both; Phase 1 covers a slice of Criterion 1 only, and Phase 1.7 (§14.4) covers Criterion 2.

### 1.6 Domain features that affect ranking quality (and therefore evaluation)

The cupertino corpus has six properties that a domain-blind evaluation will mishandle. The evaluation design must either account for each or document the gap.

1. **Multi-language duplicates.** The same concept exists in `language=swift` and `language=objc` form (e.g., `URLSession` Swift class vs `NSURLSession` Objective-C class). A query for `URLSession` should rank the Swift form above the Obj-C form on a modern Swift-first index. Programmatic ground truth that ignores `language` is blind to this.
2. **Multi-platform availability.** Many APIs are tagged with `min_ios`, `min_macos`, etc. Filter-aware queries (the user passed `--min-ios 17.0`) and filter-implicit queries (a current Swift dev expects current APIs first) interact with ranking.
3. **Framework synonyms.** `framework_aliases.synonyms` maps `nfc → corenfc`, `bluetooth → corebluetooth`. Acronym queries must route through the synonyms table; a naive regex on the literal query token fails by design.
4. **Deprecated APIs.** Apple ships deprecated APIs as documented pages. A query for a deprecated concept should still find it, but the documented-deprecated marker should not be ranked above a current alternative for the same concept name. The corpus contains both; ranking has to discriminate.
5. **Source authority for prose vs symbol queries.** A query that looks like a Swift identifier (CamelCase, no spaces) almost always wants apple-docs (the canonical reference). A prose query may want swift-evolution (design rationale), hig (UX guidance), or swift-org (compiler docs). The RRF source-weight machinery (`Search.SmartQuery.sourceWeights`, intent routing) implements this. Evaluation must test that source routing is doing the right thing per query class, not just that some result came back.
6. **Symbol-component recall.** The `symbol_components` column (#77) splits CamelCase into recall-aiding fragments. The whole point is that a query like `Grid` retrieves `LazyVGrid` even though the literal token `Grid` does not appear as a standalone word in the indexed text. Testing this requires queries with deliberate fragment-only inputs.

Each of properties 1-6 is testable. None is tested by Phase 1 as designed. Properties 1, 4, 5, 6 become explicit Phase 1.x test plans below.

---

## 2. Goals

### P0
- **G1**: For query classes **A (canonical lookup)** and **B (framework-root)** as defined in §1.4, given two `search.db` files and the corresponding binaries, produce per-query MRR, P@1, P@5, NDCG@10 in one script invocation. Verified by: script exits cleanly on both DBs of the v1.2.0 comparison.
- **G2**: Compute paired Wilcoxon signed-rank significance on per-query MRR between the two systems. Verified by: report includes W statistic, two-sided p-value, and one-sided (B > A) p-value.
- **G3**: Be reproducible. Given the same DBs and binaries, two runs of the script produce identical metrics (modulo a documented tolerance for ties broken by SQLite query-plan caching). Verified by: re-run produces identical JSON.
- **G4**: Be auditable. The full per-query top-10 result lists are dumped to JSON for post-hoc inspection. Verified by: JSON dump exists at the documented path after a run.

### P1
- **G5**: Run in under 5 minutes for 50 queries on a single machine. (Current Phase 1 measured at ~70 seconds for 50 queries; comfortably under target.)
- **G6**: Use only the Python standard library plus SciPy (for Wilcoxon). No npm, no Ruby, no Swift compilation, no docker.
- **G7**: Phase 1.x extension hooks for the other query classes (C-H per §1.4) are designed even if not implemented. Verified by: §14 implementation plan names each.

### P2
- **G8**: Support a second "ground truth" mode where qrels are read from a human-judged TSV instead of regex patterns. This is the Phase 2 hook in the universal rule.
- **G9**: Implementation of Phase 1.x for at least one of the domain-specific classes (preferably E. deprecation-aware or F. cross-source canonical, since both directly test the RRF source-weight machinery which has no other test coverage today).

### P0 for Criterion 2 (anti-hallucination grounding)

- **GH1**: A Phase 1.7 design (separate, follow-up) that measures whether an LLM coding agent, given cupertino's top-K results for a Swift task, produces code that (a) compiles, (b) calls only currently-shipping symbols, (c) respects the target platform's availability. Verified by: doc exists, sketches the agent harness and the task corpus, and is ready to land as its own design even before any code.
- **GH2**: An explicit articulation in §14 of how Criterion 1 metrics (MRR / P@k / NDCG) relate to Criterion 2 outcomes ("the agent shipped correct code"). The relationship is asymmetric: high MRR is necessary but not sufficient for good agent grounding; an agent can still hallucinate even when the right doc is at rank 1.

### P1 for Criterion 2

- **GH3**: Query-corpus realism. The Phase 1 corpus is single-token canonical lookups; agents in coding sessions overwhelmingly issue prose questions ("how do I make a type usable as a dictionary key in Swift 6"). A second corpus, derived from realistic agent-emitted queries, is needed for Criterion 2's purposes even before the agent harness exists.

---

## 3. Non-goals

- **NG1**: A general-purpose IR evaluation toolkit. *We are not rebuilding `trec_eval` or `pytrec_eval`. This is a focused tool for cupertino's specific corpus and CLI shape. If the project ever needs the breadth of `trec_eval`, we adopt it; we do not extend this harness toward it.*
- **NG2**: Production CI gating. *The harness is a local research tool. Wiring it into CI requires deciding what regression delta blocks a merge, which is a policy decision out of scope for this design.*
- **NG3**: Query-latency benchmarking. *This design measures result quality, not throughput. Latency is measured separately in the validation report harness; mixing them produces noisy numbers for both.*
- **NG4**: Evaluation of `packages.db` or `samples.db`. *This design targets `search.db` only. The same methodology applies to the other two but needs its own query set and right-answer patterns; that is follow-up work, not this design.*
- **NG5**: An LLM-as-judge alternative path. *Per the universal rule, LLM-as-judge is not the metric of record as of late 2025. We do not plumb it in even as an optional mode, to avoid the temptation to default to it.*
- **NG6**: Evaluation of query classes C-H from §1.4 (acronym, CamelCase fragment, deprecation-aware, cross-source canonical, prose, symbol-attribute). *Each requires its own corpus, ground-truth model, and in some cases its own metric. They are explicitly out of Phase 1 scope and become Phase 1.x follow-ups. Reporting Phase 1 results as a measure of "overall cupertino search quality" is wrong; the right framing is "canonical-lookup quality only."*
- **NG7**: A single composite "search quality score." *Different query classes optimise differently. Folding eight per-class metrics into one number hides the trade-offs an actual ranking change makes (e.g., a BM25F weight tweak that helps class A canonical-lookup may hurt class D fragment recall). Per-class reporting is mandatory; a composite is misleading.*
- **NG8**: Building SWE-bench / HumanEval / MultiPL-E from scratch. *The agent-end-to-end eval (Criterion 2, §14.4) borrows their methodology — a set of coding tasks, scored by whether the generated code compiles and passes tests — but does not attempt to build a general code-eval benchmark. The cupertino-specific task corpus is Apple-platform Swift and is small enough (~30 tasks) to maintain by hand.*
- **NG9**: Inferring Criterion 2 (anti-hallucination) outcomes from Criterion 1 (IR quality) metrics alone. *A high MRR can coexist with agent hallucination if the agent ignored the result, misread it, or asked a different question than the corpus represents. The relationship is one-way: high MRR is necessary but not sufficient. The two criteria need separate, parallel measurements.*

---

## 4. Requirements

### 4.1 Functional

| ID | Requirement | Verified by |
|---|---|---|
| F1 | Curated query corpus of at least 50 canonical-lookup queries with right-answer URI regex patterns. | Script source: count of `Query(...)` entries ≥ 50 |
| F2 | Each query is run against System A and System B using their respective `cupertino` binaries (the binary that built the DB, or any binary compatible with the DB's schema). | Harness `run_search()` invokes the binary subprocess |
| F3 | Top-K results (K=10) extracted as ordered URI list per query per system. | URI regex captures from CLI output |
| F4 | Per-query MRR, P@1, P@5, NDCG@10 computed for both systems against the right-answer pattern. | Aggregate table in report |
| F5 | Paired Wilcoxon signed-rank test computed on per-query MRR differences. | Report includes W, p two-sided, p one-sided |
| F6 | Full per-query data (top-10 URIs both systems, all four metrics, first-relevant rank) dumped to JSON. | File exists at `/tmp/cupertino-search-eval-results.json` after run |

### 4.2 Non-functional

| ID | Requirement | Target | Current state |
|---|---|---|---|
| N1 | Total wall-clock for 50 queries × 2 systems | < 5 min | ~70 seconds on Studio (M4 Max), Phase 1 pilot 2026-05-20 |
| N2 | Reproducibility: same inputs produce identical output | Bit-identical JSON modulo SQLite tie-break ordering | Verified informally on pilot; formal verification pending |
| N3 | Dependencies | Python stdlib + SciPy only | Met; no third-party fetch beyond SciPy |
| N4 | Read-only against the systems under test | Never write to either DB or its WAL | The harness calls `cupertino search`, which is read-only by design |

---

## 5. Design Overview

```
                       50 queries × 2 systems
                                │
                                ▼
                ┌───────────────────────────────┐
                │      Query Corpus (5.2)       │
                │   [(query, right-answer       │
                │    URI regex), ...]           │
                └───────────────────────────────┘
                                │
                                ▼
                ┌───────────────────────────────┐
                │  Subprocess runner (6.1)      │
                │  cupertino search --limit 10  │
                │   ↓                           │
                │  URI extractor: parse top-10  │
                │   ordered list from stdout    │
                └───────────────────────────────┘
                       │              │
                  System A         System B
                       ▼              ▼
                ┌───────────────────────────────┐
                │  Per-query scorer (6.2)       │
                │   MRR, P@1, P@5, NDCG@10      │
                │   against right-answer regex  │
                └───────────────────────────────┘
                                │
                                ▼
                ┌───────────────────────────────┐
                │  Aggregator + significance    │
                │  (6.3, 8.1)                   │
                │   mean per metric             │
                │   paired Wilcoxon on MRR      │
                └───────────────────────────────┘
                                │
                                ▼
                ┌───────────────────────────────┐
                │  Report (6.4)                 │
                │   stdout: aggregate table,    │
                │     per-query table,          │
                │     stat tests                │
                │   JSON dump for archive       │
                └───────────────────────────────┘
```

Single Python script, no daemons, no service dependencies. Each component is a function in the same module. Tested as a unit by re-running.

---

## 6. Detailed Design

### 6.1 Subprocess runner

*Goal: turn one query into an ordered list of top-K URIs for one system.*

*Input: a binary path, a query string, K (default 10).*

*Output: a list of up to K URI strings, in rank order.*

The runner invokes `<binary> search "<query>" --limit <K>` via `subprocess.run`. It captures stdout, applies a single regex (`apple-docs|swift-evolution|hig|apple-archive|swift-org|swift-book) followed by `://[^\s\)]+`) to extract URIs in document order, deduplicates while preserving order, and stops at K. A 30-second per-call timeout bounds the worst case.

The two binaries are:
- `/opt/homebrew/bin/cupertino` (brew, queries `~/.cupertino/search.db`)
- `/Volumes/Code/DeveloperExt/public/cupertino/Packages/.build/release/cupertino` (dev binary; its `cupertino.config.json` baseDirectory determines which DB it queries; set to `~/.cupertino-dev` for the v1.2.0 comparison)

The runner does not modify either DB; `cupertino search` is read-only.

### 6.2 Per-query scorer

*Goal: compute four metrics for one (query, system) pair.*

*Input: ordered URI list (top-10), compiled right-answer regex.*

*Output: MRR, P@1, P@5, NDCG@10 per query.*

- **MRR** = 1 / rank-of-first-match; 0 if no match in top-10.
- **P@k** = (number of matches in top-k) / k.
- **NDCG@k** (binary relevance) = Σ rel_i / log₂(i+2) for i in 0..k-1, where rel_i = 1 if uri_i matches the pattern else 0. Each query has at most one canonical right answer in this design, so IDCG = 1/log₂(2) = 1; raw DCG ∈ [0, 1+...] and is reported without further normalisation.

For DCG@10 the value of an exact top-1 match is 1.0; a top-2 match is 0.6309; a top-10 match is 0.2890.

### 6.3 Aggregator

*Goal: produce overall means and the paired difference vector.*

For each of the four metrics, compute mean across all 50 queries for System A and System B. Delta = mean_B − mean_A. The per-query MRR difference vector feeds the significance test in §8.1.

### 6.4 Reporter

*Goal: present results in two forms.*

- **stdout**: aggregate metric table (brew vs new vs delta), Wilcoxon line, per-query rank table (so a reader can spot which queries shifted).
- **JSON dump** at `/tmp/cupertino-search-eval-results.json`: full per-query records including all top-10 URIs for both systems. This enables post-hoc inspection of any individual query and is the audit trail for the claim.

The stdout table format is plain text with column-aligned numbers. No colour, no terminal-control escapes (so the output is paste-friendly into reports and CHANGELOGs).

---

## 7. Data Model

### 7.1 Query corpus

The query corpus is a Python list of `Query` dataclass instances:

```python
@dataclass(frozen=True)
class Query:
    q: str         # the search text as the user would type it
    pattern: str   # regex matching the canonical right-answer URI
```

Storage: in-source (a Python list at the top of the script). Rationale: 50 entries with regex patterns is more readable as Python source than as TSV, and is easier to extend / annotate / version. If the corpus grows past ~200 queries we revisit and move to a TSV.

Query selection guidelines:
- Cover breadth: Swift standard library, Foundation, SwiftUI, UIKit, Combine, concurrency, framework roots
- Each query has exactly one canonical answer expressible as a URI regex
- The query text is what a developer would actually type, not a curated "best" form
- Multi-word and CamelCase queries are both represented
- Deprecated framework queries are represented (so we catch regressions there too)

### 7.2 Results JSON

Output dump at `/tmp/cupertino-search-eval-results.json`:

```json
{
  "n_queries": 50,
  "per_query": [
    {
      "query": "Hashable",
      "pattern": "^apple-docs://swift/hashable($|/)",
      "brew": { "top10": ["apple-docs://..."], "first_rank": 2, "mrr": 0.5, "p1": 0.0, "p5": 0.2, "ndcg10": 0.6309 },
      "new":  { "top10": ["apple-docs://..."], "first_rank": 1, "mrr": 1.0, "p1": 1.0, "p5": 0.2, "ndcg10": 1.0 }
    },
    ...
  ]
}
```

No schema version field yet; if the JSON shape ever changes incompatibly, add `"schema_version": 2` at that point.

### 7.3 Phase 2 hook: TREC qrels

When Phase 2 lands, the harness will accept an optional `--qrels <path>` argument pointing to a TSV in the standard TREC format:

```
qid 0 docid relevance
1 0 apple-docs://swift/hashable 1
1 0 apple-docs://foundation/anyhashable 1
2 0 apple-docs://swift/equatable 1
...
```

Where present, the qrels override the regex-based ground truth. The per-query scorer's relevance function becomes `(doc_uri in qrels[query]) → 1, else → 0` instead of `pattern.search(doc_uri)`. The rest of the pipeline is unchanged.

---

## 8. Algorithms / Protocols

### 8.1 Paired Wilcoxon signed-rank test

Rank-based metrics like MRR are bounded in [0, 1] and discrete, with a heavily right-skewed distribution (most queries land 1.0 or 0.5; few land 0.0). The Gaussian assumption of the paired t-test does not hold. The standard substitute, and the one IIR §8.6.3 recommends, is the paired Wilcoxon signed-rank test.

Compute per-query difference d_i = MRR_B(q_i) − MRR_A(q_i) for i in 1..N. Zero differences are dropped per the `zero_method="wilcox"` convention. The remaining differences are ranked by absolute value; the test statistic W is the sum of the positive-rank or negative-rank sum, whichever is smaller. The two-sided p-value tests "MRR_A ≠ MRR_B"; the one-sided p-value tests "MRR_B > MRR_A".

Implementation: `scipy.stats.wilcoxon(mrr_new, mrr_brew, zero_method="wilcox", alternative=...)`.

Minimum N for the test to have power: at least 6 non-zero pairs (below that the harness reports "too few non-zero pairs" and skips the statistic).

### 8.2 NDCG@10 with binary relevance

Per IIR §8.4. For a single query with at most one canonical right answer:

```
DCG@k = Σ_{i=0}^{k-1} rel_i / log₂(i + 2)
```

where `rel_i = 1` if the i-th result (0-indexed) is a match, else 0. IDCG = 1 (perfect ranking puts the one right answer first). NDCG@k = DCG@k / IDCG = DCG@k.

NDCG > 1 is impossible in single-answer mode, but the aggregate "NDCG@10 mean" across 50 queries can exceed 1 because the metric is summed (not averaged) within the perfect-IDCG normalisation. The reported metric in §6.4 is the per-query mean, which is bounded in [0, 1] only when each query has exactly one canonical right answer. When a query's pattern legitimately matches more than one document (e.g., a framework-root regex like `apple-docs://swiftui($|/[^/]*$)`), the DCG sums multiple gains and the per-query NDCG can exceed 1. This is a known accounting quirk; the metric remains useful for paired comparison.

### 8.3 Score sign convention

cupertino's internal BM25 scores are negative (lower is better), per `Search.Index.Search.swift`. The harness operates one level up — on the rendered URI ranking, not on raw scores — so the sign convention is internal to cupertino and not surfaced here. The reader of the harness output never sees a negative number.

---

## 10. Reliability and failure modes

| Failure mode | Detection | Mitigation |
|---|---|---|
| Binary not found at expected path | `subprocess.run` raises `FileNotFoundError` | Pre-flight check at script start; fail-fast with clear message |
| Binary points at the wrong DB | Top-10 returns wrong-source URIs; metrics are unexpectedly low | Pre-flight: read `cupertino.config.json` and assert the expected baseDirectory; report current config in the script header |
| Subprocess hangs | 30s per-call timeout | Skip the query (record empty top-10), continue; query counts as MRR = 0 |
| Query corpus has typos in regex | Test crashes at regex compile time | Compile-time check at script start (compile all patterns before any queries run) |
| Both systems return zero hits for a query | Both MRR = 0; that query contributes 0 to the Wilcoxon difference and is dropped by `zero_method="wilcox"` | Reported in the per-query table for human review |
| Result-parsing regex misses URIs in new CLI output format | Per-query top-10 unexpectedly short or empty | JSON dump shows raw top-10; cross-check by re-running `cupertino search` manually for a sample query |
| Pilot data leaks into a "real" run | None automatic | Pilot data is saved separately at `/tmp/cupertino-search-eval-pilot-*.json`; treat any file with `pilot` in the name as not-for-record |

### 10.1 What we explicitly do NOT recover

- **Cupertino binary crash during a query**: we record empty top-10 for that query and continue. The query contributes 0 to MRR. We do not attempt to retry, restart, or diagnose the binary; that is a separate concern.
- **Disagreement between the regex pattern and human judgment**: the design accepts this as the cost of Phase 1's cheapness. The mitigation is to upgrade to Phase 2 (human qrels) when the disagreement matters.

---

## 11. Security and privacy

No user data is read or written. The harness reads two `cupertino` binaries and queries two `search.db` files; both are public open-source artefacts. The harness writes a JSON file to `/tmp/`. No network access, no telemetry, no credentials.

---

## 12. Observability

- stdout: progress per query (`[N/50] query`), aggregate table, per-query table, statistics
- JSON dump at a fixed path
- No log file, no rotation, no separate verbosity level (the script is short enough to read end-to-end if debugging is needed)

---

## 13. Open questions

| Question | Resolution path |
|---|---|
| Does the query corpus need to be versioned in-repo (e.g., `scripts/eval/queries.py`) so reruns are auditable against a fixed corpus? | Likely yes; defer until the script is moved out of `/tmp/`. |
| Should the harness compare against `cupertino-docs`'s git history (diff index quality across corpus snapshots)? | Out of scope for v1; the design supports it but the second-corpus query path is not exercised. |
| Phase 2's human-qrels workflow: where do judgments live, who judges, how is kappa measured? | TBD in a follow-up design when Phase 2 is needed. |
| How does this interact with the `packages.db` and `samples.db` evaluation? | Same methodology, different query corpora and patterns. Defer to a per-database design doc when needed. |

---

## 14. Implementation plan

### 14.1 Phase 1 (classes A and B — canonical lookup and framework root)

1. **Land this design doc** on `develop` so the methodology is durable. *(This doc.)*
2. **Move the harness** from `/tmp/cupertino-search-eval.py` to `scripts/eval/search-quality-phase1.py`, versioned in the repo. Land in a follow-up PR.
3. **Move the query corpus** to `scripts/eval/queries/canonical-lookup.py` so it is a separate, versioned artefact (not co-mingled with harness logic). Path includes the class name so subsequent class corpora sit alongside.
4. **Run the harness against the brew DB vs the v1.2.0 new DB** as the first formal comparison. Publish results to `docs/audits/search-quality-v1.2.0-vs-v1.1.0.md`.

### 14.2 Phase 1.x — domain-specific class extensions (priority order)

Each is a separate small design + corpus + harness mode. None is in this design's scope.

| Phase | Class | Why this priority | What's needed |
|---|---|---|---|
| 1.1 | E. Deprecation-aware | Tests that the RRF and BM25F weights bias correctly between Swift and Obj-C duplicates. The single most visible failure mode for a user. | ~30 queries with both Swift and Obj-C canonical URIs; metric = paired sign test on rank-of-Swift < rank-of-ObjC |
| 1.2 | F. Cross-source canonical | Tests `Search.SmartQuery.sourceWeights` (apple-docs=3.0, swift-evolution=1.5, etc.). No existing test coverage. | ~25 queries with per-source canonical URIs; metric = "is top-1 from highest-authority source that has any match" |
| 1.3 | D. CamelCase fragment | Tests `symbol_components` column (#77) directly. Easy to write; high signal. | ~20 fragment queries (`Grid`, `Decoder`, `Session`) with sets of valid retrievals; metric = P@5 |
| 1.4 | C. Acronym / synonym | Tests `framework_aliases.synonyms`. Small corpus (the synonyms table itself is small). | ~15 acronym queries (`NFC`, `CK`, `CD`) with canonical framework URIs; metric = MRR |
| 1.5 | G. Prose / conceptual | Requires either human qrels or programmatic ground truth that admits multi-document relevance. Harder to design. | ~15 prose queries with per-query relevant-document sets (~3-5 docs each); metric = R-Precision |
| 1.6 | H. Symbol-attribute | Requires SQL-level relevance criteria, not URI-pattern criteria. | ~15 attribute queries (`@MainActor on View`, `async throws -> Result`) with relevance defined by a `doc_symbols` filter; metric = P@k only |

Phases 1.1 and 1.2 are the highest-value because they test query-side machinery (RRF source weights, deprecation discrimination) that has no other test coverage today.

### 14.3 Phase 2 — TREC-grade human pooling

Defer until the first situation that warrants it (a borderline Phase 1 result, an external defense of a ranking change, a customer-facing claim). The qrels TSV hook in §7.3 is the integration point. This phase still serves Criterion 1 (good search) only.

### 14.4 Phase 1.7 — anti-hallucination agent-end-to-end eval (Criterion 2)

The most important and most expensive piece. Phase 1.7 is its own design doc (`docs/design/anti-hallucination-eval.md`, not yet written). The shape:

| Element | Description |
|---|---|
| **Task corpus** | ~30 Swift coding tasks an Apple-platform agent might be asked to solve. Each task = (prompt, target platform, success criteria). Examples: "Write a SwiftUI view that observes a model and shows a list", "Migrate this Combine pipeline to async/await", "Make this type usable as a dictionary key in Swift 6". Hand-curated, small. |
| **Agent harness** | Wraps an LLM (Claude / GPT / Gemini) with two execution modes: (a) no grounding, (b) cupertino MCP grounding. Same prompt, same model, same temperature. |
| **Scoring rubric** | Per generated code: (1) does it compile with the latest Swift toolchain against the target platform SDK? (2) does every called symbol exist in the SDK? (3) does it respect availability for the target platform? (4) does it call deprecated APIs when a current alternative exists? Compile-and-symbol checks are mechanical; the deprecation check needs a curated "current alternative" map. |
| **Pairing** | Same task, same model, two grounding conditions. Paired McNemar's test on the binary outcome (compiles-and-correct vs not). |
| **Frequency** | Run on every major ranking-affecting change (BM25F weight tweak, new column, tokenizer change, source-weight tweak). Quarterly otherwise. Cost is mostly LLM API calls plus Swift toolchain time. |
| **Reporting** | "Cupertino grounding raised compile rate from X% to Y% on N tasks (McNemar p=Z)." Plus per-task breakdown for any task where cupertino-grounded was *worse* than ungrounded (an important failure to investigate). |

Phase 1.7's relationship to Phase 1:
- Phase 1 is a fast, cheap proxy for "is the right doc findable."
- Phase 1.7 is the slow, expensive ground truth for "did the agent then ship correct code."
- A Phase 1 regression demands explanation. A Phase 1.7 regression is a release blocker.

Phase 1.7 should be implemented after Phase 1 is in repo and the first formal v1.2.0-vs-v1.1.0 comparison is published, so the cheap layer is established before the expensive one. Estimated effort: 1-2 weeks for the harness, ongoing curation for the task corpus.

### 14.5 Sequencing summary

Read the phases in this order; do not skip:

| Phase | Criterion | Effort | Output |
|---|---|---|---|
| 14.1 | C1 (good search), class A+B | 1-2 hours | Phase 1 harness in repo, first formal comparison |
| 14.2.1-1.4 | C1, classes E/F/D/C | a few hours each | Extended class coverage |
| 14.2.5-1.6 | C1, classes G/H | a day each, plus human qrels for G | Prose + symbol-attribute coverage |
| 14.3 | C1, TREC-grade | days of human time per run | Defensible audit-grade comparison |
| 14.4 | **C2 (anti-hallucination)** | weeks | The real success measure |

Per the `feedback_code_changes_as_ideas_for_future` memory rule, every step from 14.1.2 onward and all of 14.2 / 14.3 / 14.4 is explicit follow-up work and is not landed by this design.

---

## 15. References

1. Manning, C. D., Raghavan, P., & Schütze, H. (2008). *Introduction to Information Retrieval*, Chapter 8. Cambridge University Press. https://nlp.stanford.edu/IR-book/html/htmledition/evaluation-in-information-retrieval-1.html
2. Voorhees, E. M. (1999). "The TREC-8 Question Answering Track Report." *Proceedings of the 8th Text REtrieval Conference (TREC-8)*, pp. 77–82. (MRR.)
3. Cormack, G. V., Clarke, C. L. A., & Büttcher, S. (2009). Reciprocal rank fusion outperforms Condorcet and individual rank learning methods. *Proceedings of SIGIR 2009*. (Referenced by cupertino's RRF in the production query path; not used by this harness.)
4. TREC overview, NIST: https://trec.nist.gov/overview.html
5. `mihaela-agents/Rules/universal/search-quality-eval.md` — the universal rule this design specialises.
6. `docs/architecture/database.md` — the system under test.
