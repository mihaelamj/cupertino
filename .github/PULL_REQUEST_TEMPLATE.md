<!-- Thanks for contributing to Cupertino. Please read CONTRIBUTING.md first. -->

## Summary

<!-- What does this PR change, and why? One or two sentences focused on the "why". -->

## Linked issue

<!-- e.g. "Closes #123". Cupertino is issue-first: every non-trivial PR references an issue. -->

## Test plan

<!-- How did you verify this? Cite the commands you ran and their pass/fail result.
     "It compiles" is not a test plan. -->

```bash
cd Packages && make test
```

## Checklist

- [ ] Targets `develop`, not `main` (external PRs to `main` are rejected by CI).
- [ ] Swift-only if you are an external contributor (see CONTRIBUTING.md); maintainer-side tooling is maintainer-only.
- [ ] Tests added or updated for the change, and the full suite passes locally.
- [ ] `CHANGELOG.md` updated under the correct section for any non-trivial change.
- [ ] `docs/commands/` updated in the same PR if a CLI flag, subcommand, or enum value changed.
- [ ] Cross-references use issue numbers and symbol names, not line numbers; every cited file path exists.
