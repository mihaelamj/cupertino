# Audit + PR-body methodology

Living doc for the conventions the ironclad-sweep audits surfaced. Each
section is rooted in a specific lesson from a specific audit pass; the
audit doc that triggered it is named in the section header. Update when
a new lesson lands.

## PR body & CHANGELOG: test count claims (#735)

**Trigger**: PR #731's body claimed "50 tests / 8 suites" — actually 41
`@Test` directives across 7 `@Suite` declarations. The 50/8 numbers
were runtime case counts (with parametrised expansion) reported without
labelling. Substance shipped correctly; the description inflated the
metrics.

**Convention**:

- For the **canonical "tests" count** in a PR body or CHANGELOG entry,
  use the `@Test` directive count — the durable spec count that
  doesn't change when the test runner expands parametrised cases:
  ```bash
  grep -c '^[[:space:]]*@Test' <test-file.swift>
  ```
- For the **"suites" count**, use the `@Suite` declaration count:
  ```bash
  grep -c '^@Suite' <test-file.swift>
  ```
- If you want to cite the runtime case count (interesting for
  parametrised tests), label it explicitly: *"42 runtime cases
  including parametrised expansion"*. Never report it bare as the
  "test count" — Swift Testing's runtime expansion is transport
  behaviour, not specification.
- For multi-file PRs, sum across all touched test files:
  ```bash
  grep -hc '^[[:space:]]*@Test' Packages/Tests/.../Issue<N>*.swift | paste -sd+ | bc
  ```

**Why**: a PR's test claim is read months later as evidence of coverage.
If the claim's "50 tests" can mean 41 directives or 50 runtime cases
depending on which day you ran it, the audit trail is unreliable.
Pick the durable number, label clearly when you cite the alternative.

## Source-comment promises about "before merge" / "next PR" / "release"

**Trigger**: PR #731 source comment on the deprecated `appliesFilter` /
`silentlyIgnoresFilter` aliases said *"will be removed before merge."*
PR merged with the aliases in place. The comment was a lie at merge
time. Fixed in PR #736 (#734 close) by deleting the aliases entirely
since they had zero callers.

**Convention**:

- **Don't write source comments asserting what "will" happen at a
  future event** (before merge / next PR / next release) unless the
  comment is in the same commit as the action it asserts.
- If the comment is necessary as scaffolding, name the **expected
  retention window** instead: *"Retained through v1.2.x for back-compat;
  removed in v1.3."* — verifiable rather than aspirational.
- Pre-merge critic pass: grep your own diff for *"will be"* / *"before
  merge"* / *"next PR"* and verify each one against the actual merge
  state.

**Why**: source comments are read decades later by people debugging.
A "will be removed before merge" annotation on code that's still
present 6 months post-merge is more confusing than no annotation. The
annotation outlives the intention.

## Audit document location (#733)

See [`README.md`](README.md). Lowercase-hyphen filenames under
`docs/audits/`, never at repo root. Self-references in audit docs use
the post-rename filename.

## Closure protocol (Stage E — pending)

This section reserved for the Stage E methodology change: every issue
closure should carry **(a) the merging PR**, **(b) which acceptance
bullets are covered**, **(c) where the regression lock lives** (test /
lint / CI guard / explicit no-lock note with rationale).

Filed as Stage E of the ironclad sweep; will be backfilled here when
that stage lands.

## Patterns the audit looks for (Stage A finding)

From `closure-replay-2026-05-17.md`'s "Findings on the audit
methodology itself" section, these are the patterns Stage A protects
against — list them here in case the audit doc is later archived.

1. **Single-keyword grep is insufficient.** A grep that finds something
   somewhere proves nothing about whether the *acceptance bullet's
   specific shape* shipped. Verify the keyword would have been unique
   to the unshipped bullet — if it would also appear in shipped code,
   the grep isn't a probe, it's a vibe check.
2. **CHANGELOG entries have content-shape requirements.** "Entry
   exists in CHANGELOG" is not the same as "the data the bullet asked
   for is in the entry." If the bullet asks for a wall-clock
   benchmark and the entry only reports index-size delta, the bullet
   is unmet.
3. **Reindex-gated closures** ship code that takes effect only after a
   subsequent `cupertino save --docs`. The live DB shape is the test
   of record. v1.2.0 release ceremony is the natural re-assertion
   point.
4. **Cross-repo closures require explicit cross-repo verification.**
   First-pass audits stay within `cupertino/`; deep passes need to
   walk the sibling repo. Documented as no-lock when the cross-repo
   verification can't be automated (#624's skill in `mihaela-agents`).
5. **Scope reductions need closing comments that NAME the dropped
   bullets**, not just describe what shipped. A silent scope drop
   reads identically to an honest one until the audit replays the
   original acceptance list.

These five patterns are how the audit catches false closures. Future
audit passes should start from this list and probe each pattern
explicitly per issue under review.
