# Roadmap Maintenance Protocol

This document is the maintainer-facing companion to the public roadmap in
GitHub issue #183. Keep #183 readable for newcomers. Put the update rules,
release hygiene, and agent handoff protocol here.

## Source Of Truth

Keep these three surfaces aligned whenever roadmap state changes:

1. GitHub issue #183: public roadmap, phase table, side tracks, design
   constraints, open questions, and changelog.
2. Release milestones: per-version issue groupings used to decide what has
   shipped and what is still awaiting a tag.
3. GitHub project board #3: kanban state for active and queued roadmap work.

If these disagree, update #183 first, then the milestone or project-board state,
then append a changelog line to #183 recording what changed.

## Required Update Sequence

Use this sequence for every roadmap state transition:

1. Update the affected row or paragraph in issue #183.
2. Update the matching milestone, label, or project-board item.
3. Append one short entry to the changelog section at the bottom of #183.
4. Link the implementation PR, release issue, or audit note that justified the
   change.

Silent edits are not allowed. Every roadmap edit needs a changelog entry, even
when the edit only corrects stale wording.

## Common State Changes

| Change | Required roadmap edit |
|---|---|
| Phase moves from next to in-flight | Update the phase status cell and current-state paragraph in #183 |
| Phase finishes | Mark the phase done only after the release tag carrying it is pushed |
| Release plan issue opens | Link it from the matching phase row |
| Epic opens or closes | Add or remove the side-track row in #183 |
| Open question is answered | Strike the question, record the answer, and add a changelog line |
| Design constraint changes | Add a dated constraint entry and a changelog line |
| Milestone is created, renamed, reassigned, or closed | Update the milestone cell in #183 and add a changelog line |
| Project-board item moves in a way #183 does not reflect | Update #183 or move the board item back |

## Release Discipline

"Closed" means shipped, not merely merged. A fix that has merged but is not in a
tagged release stays open with:

- `fixed: awaiting release`
- `fix-in: vX.Y.Z`
- the target milestone

When a release tag is pushed, batch-close issues in that milestone that carry
`fixed: awaiting release`, then update #183 in the same maintenance pass.

## Branch And Tag Policy

The current workflow uses a paired `develop` and `main` model:

- External and feature PRs target `develop`.
- `main` is reserved for maintainer-driven release promotion.
- Release preparation can happen on `release/vX.Y.Z` branches.
- Promotion from `develop` to `main` is a maintainer action after release
  readiness checks pass.
- Auto-delete-on-merge is enabled, so branch names should not be treated as
  durable state.

Do not describe the old pre-v1.0 `packages-overhaul` staging branch as current
workflow. It is historical context only.

## Label Conventions

Use these labels consistently in roadmap and release tracking:

- `priority: high`, `priority: medium`, `priority: low`
- `complexity: low`, `complexity: medium`, `complexity: high`
- `good first issue`
- `big-win`
- `help wanted`
- `bug`, `enhancement`, `documentation`
- `transitional`
- `fixed: awaiting release`
- `fix-in: vX.Y.Z`
- `blocked_by_N`

When a new roadmap label convention appears, add it here and record the change
in #183.

## Agent Handoff Rules

Agents working on roadmap or release-state tasks should:

1. Read #183 before editing roadmap state.
2. Read this file before moving milestones, labels, or project-board items.
3. Prefer public repository state over stale private memory files.
4. Treat old v1.0.0 prep notes as historical unless #183 or a current issue
   explicitly points to them.
5. Never close a roadmap issue just because its PR merged. Wait for the release
   tag.

If a private memory file conflicts with #183, this document, or current GitHub
state, update the public source and mention the conflict in the changelog entry.
