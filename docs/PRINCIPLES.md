# Cupertino Engineering Principles

These are the principles the cupertino refactor stands on. Specific rules
(code style, package shape, DI mechanics) live in `AGENTS.md`,
`CLAUDE.md`, the imported `mihaela-agents/Rules/` set, and the per-area
docs under `docs/`. This file is the **why** behind those rules: the
short list of stances we re-derive everything else from.

If a rule and a principle disagree, the principle wins and the rule
gets updated.

---

## 1. Lossless URIs

Two different Apple URLs **must** produce two different URIs by
construction. The URI literally encodes the URL path under
`/documentation/`: framework slug, then every remaining segment joined
by `/`. Lowercased + fragment / query stripped + sub-page underscores
to dashes per the canonicalisation in `Shared.Models.URLUtilities.normalize(_:)`
(#283, #285).

No hashing. No truncation. No special-character sanitisation at the URI
layer. The shape is reversible: any URI consumer can recover the source
URL by string substitution.

Why: probabilistic disambiguators (8-byte SHA suffixes, 32-bit hash
caps) carry a non-zero collision floor at any corpus size. Lossless
removes the entire class of collisions before they happen, and gives us
URIs that are debuggable by eye.

Helper: `Shared.Models.URLUtilities.appleDocsURI(from:)` /
`appleDocsURI(fromString:)`.

## 2. Handle collisions at the door

Detect duplicate or colliding URIs at the **input boundary**, before
any DB write. Not via SQLite `UNIQUE` constraint catch, not via a
later audit pass.

The "door" is the import / `cupertino save` entry point. Each row that
crosses the door:

1. Compute its URI from its source URL.
2. Look up that URI in a per-run "seen" map (and / or the existing
   index, depending on mode).
3. Classify before writing.

The point of the door is to make the indexer's invariants visible at
the entry, where the source URL and the raw content are still in hand.
By the time you're catching a constraint error inside SQLite, the
context that would have told you which collision class this is has
been thrown away.

## 3. Don't let content be lost at the door

Collision handling **must never silently drop a row whose content
differs from the row it collided with**. Be meticulous when you decide
two rows are "the same."

### Equivalence tiers (must pass ANY to collapse)

| Tier | Match criteria | Action |
|---|---|---|
| A | same URI + same `contentHash` | Collapse silently (byte-identical) |
| B | same URI + same canonical title | Collapse, but **pick richest variant** (see below). Log every losing variant's source path + contentHash. |
| C | same URI + **different** canonical title | **Do not collapse.** First-arrived stays in index; second surfaced as `collision`, source path recorded. |

Tier A is byte-equal proof. Tier B leans on the fact that Apple's
server-side case-insensitive routing serves one logical page per
canonical URL, so a same-URI cluster is provably the same page even
if rendering drifted between crawls. Tier C is the URI canonicalization
itself colliding two distinct pages — the only case where we could
truly lose content.

### Richest-variant selection (deterministic)

1. More non-empty fields among `{abstract, declaration, sections,
   codeExamples, rawMarkdown}`
2. Tie → larger total byte length across those fields
3. Tie → first arrived

The "pick richest" rule guarantees a populated abstract never loses to
an empty one, a full declaration never loses to an empty one, and so
on. Drift between crawls becomes a monotonic improvement, not a
silent downgrade.

### Logging guarantees

For every collapsed row, the per-doc log records:

- the chosen variant's source path and contentHash
- every losing variant's source path and contentHash

For every tier-C collision, the log records both source paths, both
content hashes, both titles, both abstracts — plus a `.error`-level
log line and a structured `CollisionRecord` in the save report. The
source files are still on disk, so an auditor can always diff and
recover. The index is one storage location; the corpus is another.
Tier-C non-zero at end of run → save exits non-zero with a "work-
not-done" banner.

### Why this principle exists

BUG 1 in main's 2026-05-15 real-life test report. The pre-#293
indexer's `INSERT OR REPLACE` silently dropped Apple docs because
their URLs shared a leaf name with a sibling. The `.lastPathComponent`
URI shape was the root cause; the silent overwrite was the trap that
made the data loss invisible until a user hit it. The lossless URI
(principle 1) and the door check (principle 2) prevent the root cause;
the tiered, meticulous equivalence test prevents the trap from ever
mattering again.

## 4. Be smart at the input. Don't let garbage in.

Pre-INSERT validation at the door. Reject and count, by reason:

- Empty title.
- Empty content / content under a small threshold.
- Placeholder strings: bare `"Error"`, bare
  `"Apple Developer Documentation"`, JS-disabled fallback templates.
- HTTP error response bodies (403, 404, 500, 502, 503) reaching the
  indexer (defence-in-depth for #284).
- URI helper miss (URL doesn't decompose into a documentation URI).

Each rejection class gets a counter in `Search.IndexStats`. The
`cupertino save` final report surfaces all classes with non-zero
counts. The crawl-side filter at #284 / #289 / #291 is the first line
of defence; the indexer-side filter here is defence-in-depth so any
single layer failing doesn't ship bad rows.

## 5. One order of magnitude over the task

Design for 40M docs when today's corpus is 400K. Pick algorithms whose
memory and time profile hold at the larger scale.

Concretely:

- Per-row work at the door is `O(log N)` or `O(1)` against the URI
  index. No `O(N)` scans during normal import.
- Per-run memory is bounded by URI count, not by document size or
  content. Materialised hashmaps with HTML bodies don't fit at 40M;
  hashmaps of `URI to (canonical-title-hash, content-hash)` do.
- If the obvious data structure stops fitting at the 10x target,
  switch to a streaming / probabilistic structure (bloom filter +
  DB lookup on hit) before the 1x target trips it.

Why: re-indexing the bundle takes hours; re-crawling Apple takes
half a day. Algorithms that fall over at scale fall over slowly and
quietly. The "10x headroom" rule keeps us from shipping a structure
that works on the laptop and bricks on the build farm.

Carmack-on-NeXT, not Carmack-on-PC. The day you need the headroom is
the day you don't have time to retrofit it.

## 6. Correctness first

Correctness ranks above re-index cost, build time, refactor cost,
refactor scope.

If a fix needs a 12-hour re-index, take the 12-hour re-index. If a fix
needs a re-crawl, take the re-crawl. The cost of shipping wrong data
is paid by every user every query, forever; the cost of correctness is
paid once.

This principle is **why** the previous five exist. They're operational
expressions of "correctness first" at the import layer.

---

## Companion docs

- `docs/ARCHITECTURE.md` — package layout, layer rules.
- `docs/package-import-contract.md` — what each package may import.
- `AGENTS.md` — agent-facing rule index.
- `CLAUDE.md` — project-level focus + workflow.
