---
name: Bug report
about: Something that ships incorrectly. For new work, use the Feature template.
title: ""
labels: bug
---

## Status (YYYY-MM-DD)

<!--
Mandatory at filing time. Replace YYYY-MM-DD with today's date.

Update this block when state changes (root cause found, fix in
flight, fix merged, awaiting release, closed). Convention per the
ironclad-sweep audits in `docs/audits/methodology.md`.

If brand-new: "Filed YYYY-MM-DD. Reproduced on commit <sha>."
-->

Filed YYYY-MM-DD.

## Symptom

What goes wrong. Verbatim command + actual output where applicable.

## Expected

What should happen instead.

## Reproduce

Minimal steps. Cite the commit SHA the symptom reproduces on.

```bash
# Commands here
```

## Environment

- cupertino version: `cupertino --version`
- OS:
- Install path: brew / source / dev-binary

## Acceptance

<!-- The fix isn't done until the bug can't recur. Pin a regression
test that fails before the fix and passes after. Per Carmack
discipline (#673): close the class of bug, not just the instance. -->

- [ ] Root cause identified and named in the fix PR
- [ ] Regression test pinned: `Issue<N><Concern>Tests` (or equivalent)
- [ ] CHANGELOG entry under `### Fixed`
- [ ] If the bug surfaced a class-of-bug (multiple sites at risk),
      audit + fix the rest in the same PR or a follow-up named here

## Related

<!-- Cross-references and prior art. File paths cited here must
exist at filing time (mechanical check:
`scripts/check-issue-body-staleness.sh`). -->

-
