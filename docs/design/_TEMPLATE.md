# Design: [Subsystem name]

<!--
HOW TO USE THIS TEMPLATE
========================
Copy this file to docs/design/<slug>.md. Fill in the sections below.
Delete sections that don't apply to your design (e.g., a pure refactor
won't need §10 Scalability). The annotation lines (italics under each
heading) explain what goes in that section; delete them as you write.

Status values:
  - draft:      actively being written; not yet a commitment
  - accepted:   the design is the plan; code should match
  - superseded: replaced by a newer doc; link to it in the Status block
  - rejected:   explored, decided against; keep for record

Solo-author note: this template assumes one author/owner (you). Don't
add stakeholder, reviewer, or approval fields. If you ever need them,
add them then; don't pre-create them now.
-->

| Field | Value |
|---|---|
| **Status** | draft |
| **Created** | YYYY-MM-DD |
| **Last revised** | YYYY-MM-DD |
| **Tracking issue** | #NNN (or "none") |
| **Companion docs** | links to related design docs, ADR children, principles |

---

## TL;DR

*One paragraph, three to five sentences. What is this, why does it exist, what's the headline design decision. A reader who stops here should know whether to keep reading. No section headers; no bullets.*

---

## 1. Context

*What problem are we solving and why now. Two to four short subsections work well:*
- *1.1 What's the user-facing or system-facing problem*
- *1.2 Why the obvious approaches don't work (one sentence each)*
- *1.3 What changed recently that makes this worth doing now (optional)*

*If you can't articulate why this matters in a paragraph, the design isn't ready.*

---

## 2. Goals

*Prioritized list. Pick a priority scheme and stick to it:*
- *P0 = release blocker / commitment*
- *P1 = high priority, not a blocker*
- *P2 = nice to have*

*Each goal is verifiable. "Improve performance" is not a goal. "p99 search latency under 100ms on the v1.1.0 bundle" is.*

### P0
- **G1**: [one specific, verifiable goal]
- **G2**: ...

### P1
- **G3**: ...

### P2
- **G4**: ...

---

## 3. Non-goals

*Explicit non-goals so future-you (or future contributors) don't waste time re-proposing them. The mistake to avoid: leaving non-goals unstated and re-litigating the same rejection every six months.*

*Each non-goal should explain why it's out of scope, briefly. "We're not building X because Y" beats "X is out of scope" alone.*

- **NG1**: [thing we are NOT doing]. *[Why]*.
- **NG2**: ...

---

## 4. Requirements

*If goals are the "what", requirements are the "how well". Tables work well here.*

### 4.1 Functional

| ID | Requirement | Verified by |
|---|---|---|
| F1 | [behaviour the system must exhibit] | [test name, manual check, doc reference] |
| F2 | ... | ... |

### 4.2 Non-functional

| ID | Requirement | Target | Current state |
|---|---|---|---|
| N1 | [latency / throughput / size / availability] | [quantified target] | [where we are today] |
| N2 | ... | ... | ... |

*The "Current state" column is the key honesty check. If you can't fill it in, you haven't measured yet.*

---

## 5. Design Overview

*High-level only. The reader should understand the shape of the system from this section alone, without diving into §6+. Two things go here:*

- *A diagram (ASCII art is fine; mermaid if it renders where this lives)*
- *A short paragraph naming the major components and how they connect*

*Defer detail to §6+.*

```
[diagram showing the major components and data flow]
```

---

## 6. Detailed Design

*One subsection per major component or stage. Aim for "a reader could implement this from the doc" depth, not "a reader could critique the approach" depth.*

*Common pattern for pipelines: §6 covers stage 1, §7 stage 2, §8 stage 3, etc. Each stage section covers: goal, input, output, key algorithms, failure handling.*

### 6.1 [Component / stage name]

*Goal: one sentence.*

*Input: what arrives at this stage's boundary.*

*Output: what leaves this stage's boundary.*

*Body: how it works. Include code references where useful (file path + symbol name, not line numbers, since those rot). Tables for branching logic, ASCII diagrams for flow.*

### 6.2 [Next component / stage]

*...*

---

## 7. Data Model

*If the design touches storage, document the schema here. Otherwise delete this section.*

*Include the SQL (or equivalent) for each table, a column-by-column rationale for non-obvious columns, and the indexes. A reader should not have to grep the codebase to know what's in the DB.*

```sql
CREATE TABLE example (
  ...
);
```

*Why these columns and not others: ...*

---

## 8. Algorithms / Protocols

*If a non-trivial algorithm or wire protocol is load-bearing for the design, document it separately here. Ranker pipelines, fusion math, consensus protocols, etc.*

*Diagrams + prose explanation + cited references for non-obvious choices.*

---

## 9. Scalability Analysis

*If the design has a "how does this break at N×" question, answer it here.*

*Pattern that works: state current scale, state target headroom (e.g., 10×), then per-component analysis showing where each component breaks. Conclude with "where scaling hurts first" so the next reader knows what to watch.*

### 9.1 Current scale

| Quantity | Value |
|---|---|
| ... | ... |

### 9.2 Target headroom

*What scale we're designing for and why (1 sentence).*

### 9.3 Per-component analysis

*One bullet per component. State the limit and the resource that runs out.*

### 9.4 Where scaling hurts first

| Component | Scales to | Limit |
|---|---|---|
| ... | ... | ... |

---

## 10. Reliability & Failure Modes

*The failure-mode matrix. One row per realistic failure. The "Mitigation" column is what makes this useful: it's the contract for what the design promises under failure.*

| Failure mode | Detection | Mitigation |
|---|---|---|
| [thing that can go wrong] | [how we notice] | [how we recover] |
| ... | ... | ... |

*Optional subsection: "What we explicitly do NOT recover": failures we acknowledge but accept, with reasoning.*

---

## 11. Security & Privacy

*Threat model: who could attack this, what could they do, what stops them.*

*Data collection: what user data flows through this design. Default to "none". If non-zero, state retention, opt-out, and review status.*

*Network access at runtime: what sockets does this open in normal operation.*

| Threat | Vector | Mitigation |
|---|---|---|
| ... | ... | ... |

---

## 12. Observability

*Three subsections usually:*

- *Logging: subsystem, categories, log levels*
- *Progress / status signals: what the user sees during long operations*
- *Inspection tools: doctor commands, audit logs, save reports*

---

## 13. Testing Strategy

*Test pyramid: unit / integration / e2e counts and tools. CI gates that block PRs. Pre-release regression locks if any.*

---

## 14. Rollout & Migration

*If this design changes existing behaviour, how does it ship.*

- *Distribution channels (Homebrew / direct binary / source)*
- *Version policy (when does the version bump, when does the DB schema bump)*
- *Backward compatibility (what older versions can/can't read the new format)*
- *Migration: in-place vs. rebuild-from-source. State the choice and why.*

---

## 15. Alternatives Considered

*One subsection per alternative. The pattern that works for a solo author writing for future-self:*

### 15.1 [Alternative name]

**Considered**: *what we evaluated*

**Rejected**: *why we didn't pick it (concrete, not "for various reasons")*

**Cost paid**: *what we give up by not picking this alternative (be honest)*

### 15.2 ...

*Aim for 5-10 alternatives. Fewer than 3 usually means you haven't actually explored the space; more than 12 usually means you're documenting every passing thought.*

---

## 16. Open Questions & Risks

### Open

| ID | Question | Tracking |
|---|---|---|
| Q1 | [unresolved design question] | [issue # or "open"] |

### Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | [thing that could derail this] | low / med / high | low / med / high | [what we'll do] |

*Likelihood × Impact gives an implicit ranking. R1 = high × high gets attention first.*

---

## 17. Future Work

*Deliberately out of scope for this design but worth flagging for sequencing.*

- *Item 1: brief description + when (next phase / version / never)*
- ...

*This is the section where solo authors leave breadcrumbs for future-self. Be specific enough that future-you can recover the thought.*

---

## 18. Decision Sub-Docs (ADR children)

<!--
This section is the "ADR-style cross-link" pattern. When a sub-decision
of this design is non-trivial enough to deserve its own document, write
it as a separate file under docs/design/<parent>-<sub>.md and link it
here. The parent doc stays at the "shape of the system" level; the
child docs are per-decision deep dives.

`docs/architecture/database.md` and `docs/design/post-processor.md` are an example: post-processor is
a child of cupertino, focused on one stage of the pipeline.
-->

| Sub-doc | Decides | Status |
|---|---|---|
| [`<slug>.md`](<slug>.md) | [what this sub-doc settles] | draft / accepted / superseded |

---

## 19. References

### Internal

*Other design docs, principles, audits, contracts in this repo.*

- `docs/PRINCIPLES.md`: short description
- ...

### External

*Papers, specs, blog posts, books. Inline citation format (Author Year) in the body of the doc; full citation here.*

- Author, Title (Year), link if available
- ...

### Roadmap

- GitHub issue [#NNN](url): one-line description
- ...
