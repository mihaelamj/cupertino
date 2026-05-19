# Postmortem: [What happened, terse and dated]

<!--
HOW TO USE THIS TEMPLATE
========================
Copy this file to docs/postmortems/YYYY-MM-DD-<slug>.md. Fill in the
sections below. Delete sections that don't apply (e.g., a simple
build break doesn't need §8 Background / Architecture). The
annotation lines (italics under each heading) explain what goes in
that section; delete them as you write.

When to write a postmortem (vs. just closing the bug):
  - A release-blocker bug shipped, was caught, and the recovery is
    worth recording
  - A long-running job lost meaningful work
  - Data loss, partial or full
  - A security finding (even if no exploitation occurred)
  - A release that had to be rolled back or patched out-of-band
  - Any failure where a future contributor would benefit from knowing
    the root cause, the timeline, and what we learned

When NOT to write one:
  - A routine bug fix where the GH issue + the commit message are
    enough context
  - A typo, a doc fix, a refactor
  - Anything where the cost of writing the postmortem exceeds the
    cost of someone re-deriving the lesson

Status values:
  - draft:    still being written; facts may shift
  - settled:  the postmortem is final; corrections only
  - superseded: replaced by a newer, more accurate writeup; link to it

Solo-author note: this template assumes one author/owner (you).
Don't add multi-reviewer / sign-off fields. The "Follow-ups" table
tracks issues filed, not who owes whom.

Section order follows the consensus across published big-tech
postmortems (Google SRE, Amazon COE, Meta SEV, Microsoft Azure PIR,
GitLab handbook RCA, Stripe, Cloudflare): Summary, Impact, Timeline,
Detection, Root Cause, Resolution, Follow-ups. Optional Background /
Architecture is the Cloudflare-style §8 for incidents whose root
cause needs system-shape context to make sense.
-->

| Field | Value |
|---|---|
| **Status** | draft |
| **Incident date** | YYYY-MM-DD |
| **Document created** | YYYY-MM-DD |
| **Last revised** | YYYY-MM-DD |
| **Tracking issue** | #NNN |
| **Severity** | release-blocker / data-loss / cost / annoyance |
| **Companion docs** | other postmortems, design docs, audit logs |

---

## TL;DR

*Three to five sentences. What failed, when, who or what was affected, what the headline cause was, what shipped to prevent recurrence. A reader who stops here should know whether this is relevant to their work.*

---

## 1. Summary

*Two to three paragraphs of plain narrative. What happened, in order, in prose. No bullets. The detailed sections below add structure; this is the "tell it like a story" recap that gives the reader the shape of the incident before they read §2 onwards.*

---

## 2. Impact

*Quantified where possible, qualitative otherwise.*

- *Who was affected (which users / builds / bundles / installation paths)*
- *What was lost (hours of compute, data, work, money, trust)*
- *Whether any released artefact carries the bug, and which versions*
- *If nobody outside the developer was affected, say so explicitly. Honest scoping matters; don't inflate.*

*"What was at risk but did NOT happen" goes in §7.3 (Where we got lucky), not here.*

---

## 3. Timeline

*Single timezone, terse, one event per line. UTC for distributed teams; project-local time for solo-author work. Match the convention the project already uses.*

| Time | Event |
|---|---|
| YYYY-MM-DD HH:MM | [event] |

*Include: the action that introduced the bug (if known), the action that triggered the failure, detection, mitigation, root-cause identified, fix shipped. Be specific to the minute when timestamps are available; round to the hour otherwise.*

---

## 4. Detection

*How did we notice the failure? Was it: user reported / CI failed / our own grep / log inspection / a downstream consumer / external monitoring / chance?*

*If detection lagged the failure, by how long, and why. Long detection is its own follow-up item; file it in §7.2.*

---

## 5. Root Cause

*The actual defect, with code references. Use file path + symbol name (no line numbers, since they rot).*

*Distinguish:*

- ***Trigger***: *the action that exposed the bug (the user input, the launch, the env state). The same defect can have different triggers.*
- ***Root cause***: *the latent defect that the trigger met.*
- ***Contributing factors***: *things that made the failure more likely, more costly, or harder to detect, but aren't the defect itself.*

*If the cause is non-obvious, do 5-Whys here:*

1. *Why did X fail? Because Y.*
2. *Why did Y happen? Because Z.*
3. *... (continue until the chain reaches a causal root, not just a symptom)*

*Stop when the next "why" would require speculation. It's fine to land at "this Foundation API behaves this way; we relied on it not behaving this way."*

---

## 6. Resolution

*What shipped to fix it. Reference the PR, the commit, the released version. If the fix is partial (workaround in place, real fix pending), state that and link the tracking issue for the real fix.*

*If anything is NOT being fixed (accepted risk), say so and explain why.*

*Sub-sections that often help:*

- *Mitigation (short-term, what we did to stop the bleeding)*
- *Fix (long-term, what shipped to prevent recurrence)*
- *Verification (how we know the fix works)*

---

## 7. Follow-ups

### 7.1 Fixed by this postmortem

*The PR(s) that this postmortem accompanies, plus any defense-in-depth that went out at the same time.*

### 7.2 Filed for later

| Item | Issue | Reason |
|---|---|---|
| ... | #NNN | ... |

### 7.3 Where we got lucky

*Things that COULD have made this much worse but didn't. Useful for spotting fragility we're depending on without realizing.*

- *Item 1: what didn't happen, and what would have made it happen.*
- *...*

### 7.4 Lessons

*One to three things future-self (or future contributors) should remember. Plain language, not platitudes.*

*"Don't trust fileExists(atPath:) as a proxy for contentsOfDirectory(at:) readability" beats "we should be more careful with file system APIs".*

---

## 8. Background / Architecture (optional)

*Include only when the reader needs to understand a non-obvious piece of the system to make sense of the root cause. Cloudflare-style: a diagram + short prose. If the root cause is self-contained (single function, well-known API), skip this section.*

---

## 9. References

### Internal

- *Other postmortems on adjacent failures*
- *Design docs that describe the affected subsystem*
- *Audit logs / crash logs attached to the tracking issue*

### External

- *Vendor bug reports, language spec sections, Foundation/SDK release notes, papers, anything that informs the root-cause explanation. Inline citation format (Author Year) in the body; full citation here.*
