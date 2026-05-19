# Postmortems

Retrospective writeups of incidents whose root cause and recovery are worth recording for future contributors. Section structure follows the consensus across published big-tech postmortems (Google SRE, Amazon COE, Meta SEV, Microsoft Azure PIR, GitLab handbook RCA, Stripe, Cloudflare).

## When to write a postmortem

Use this folder when:

- A release-blocker bug shipped and the recovery is worth recording
- A long-running job lost meaningful work (hours of compute, dropped data)
- A release had to be rolled back or patched out-of-band
- A security finding surfaced (even with no exploitation)
- Any failure where a future contributor would benefit from knowing the timeline, the root cause, and the lessons

Do NOT write one for routine bug fixes; the GH issue and the commit message are enough context for those.

## How postmortems differ from the other `docs/` folders

| Folder | Time horizon | Audience | Purpose |
|---|---|---|---|
| `docs/design/` | Forward-looking | Future implementers | "What we're building, and why" |
| `docs/postmortems/` | Backward-looking | Future maintainers | "What broke, why, and what we learned" |
| `docs/audits/` | Snapshot-in-time | Reviewer / next session | One-off correctness sweep or raw crash log |
| `docs/handoff/` | Cross-session | Next Claude / next Mac | Continuity of in-flight work |
| `docs/plans/` | Forward-looking | Self + reviewer | Multi-step implementation plan, deleted after execution |
| `docs/commands/` | Living reference | CLI users | Per-command, per-option reference; mirror of the real CLI |

A postmortem and a tracking issue are complementary, not duplicates. The issue says "what to fix"; the postmortem says "what we learned about why this happened and how the system let it happen."

## File naming

`YYYY-MM-DD-<slug>.md` where the date is the incident date (not the writeup date) and the slug is terse and topical.

Examples:

- `2026-05-18-save-symlink-enotdir.md`
- `2026-03-04-bundle-schema-overwrite.md`

## Template

`_TEMPLATE.md` is byte-identical to `mihaela-agents/Rules/universal/templates/postmortem.md`. Copy it to start a new postmortem.

## Status lifecycle

Each postmortem has a status field at the top:

- **draft**: still being written; facts may shift as investigation continues
- **settled**: finalized; corrections only
- **superseded**: replaced by a newer, more accurate writeup; the superseding doc is linked from the metadata block

A postmortem can be drafted before the fix lands and revised as the fix ships; mark it `settled` once the resolution section reflects what actually shipped.

## Index

| Date | Slug | Tracking | Severity |
|---|---|---|---|
| 2026-05-18 | [save-symlink-enotdir](2026-05-18-save-symlink-enotdir.md) | #779 | release-blocker |
