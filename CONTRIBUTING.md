# Contributing to Cupertino

Thank you for your interest in contributing to Cupertino!

## Swift Native

**Cupertino is a Swift-native project. This is a priority and a prerogative.**

Many MCP servers are written in Node.js or Python. Cupertino takes a different path — we're built for Apple developers, using Apple's language, with Apple's tooling.

### External pull requests: Swift only

If you are submitting a pull request from outside the maintainer team, we will only accept:

- ✅ Swift source code
- ✅ Swift Package Manager manifest edits (`Package.swift`)

We will **not** accept external PRs that introduce:

- ❌ Node.js / JavaScript / TypeScript
- ❌ Python
- ❌ Shell scripts (maintainer-side tooling only — see below)
- ❌ Any other language or runtime

**No exceptions.** If you can't solve something in Swift, someone else can.

### Maintainer-side tooling

The repo carries shell scripts under `scripts/` (`check-canonical-db-shape.sh`, `check-canonical-literals.sh`, `check-changelog-touched.sh`, etc.), CI YAML under `.github/workflows/`, and configuration in `.pre-commit-config.yaml`. These are **maintainer-side infrastructure** — they belong to the developer workflow, not to the shipped product. External contributors do not extend or modify these files via PR. If you have an idea for a new check or script, open an issue first; the maintainer will decide whether to author it.

This keeps the shipped binary and its source tree Swift-only while leaving the maintainer free to use the right tool for build / install / CI infrastructure.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Test your changes thoroughly
6. Commit with clear messages
7. Push to your fork
8. Open a Pull Request

## Code Style

- Follow Swift conventions and best practices
- Use meaningful variable and function names
- Add documentation comments for public APIs
- Keep functions focused and concise

## Pull Requests

- Keep PRs focused on a single change
- Write a clear description of what your PR does
- Reference any related issues
- Be responsive to feedback

## Testing

Run the full suite from `Packages/`:

```bash
cd Packages
make test          # runs the whole suite (~40s)
```

### Troubleshooting: stale SwiftPM build

Swift 6.2 on macOS 26 has an incremental-build bug where adding, moving, or renaming a method on an `actor` can leave stale `.o` / `.swiftmodule` files with the wrong method-table layout. Async dispatch then lands in the wrong slot and trips a Swift stdlib `_precondition` at `Swift/arm64e-apple-macos.swiftinterface:14659` — "Not enough bits to represent the passed value" — with the stack pointing at a function that is **not** actually in the call path (linker ICF + symbolizer ambiguity).

Signs it's staleness, not a real bug:
- Stack trace points at code the failing test could not have reached
- Adding or removing a trivial method toggles the crash
- Git bisect blames a commit with no logical relationship to the trap
- `--parallel` / `--no-parallel` has no effect

Fix:

```bash
make test-clean    # wipes .build, then runs the suite
```

CI is unaffected (always a fresh build). This only bites local dev after method-surface changes on actors. Don't waste time adding debug prints, swapping `Int32()` for `Int32(clamping:)`, or bisecting — those are documented dead ends.

## Documentation

`docs/commands/` is hand-curated and mirrors the CLI surface. When you add, remove, or rename a flag, subcommand, or enum value, update the matching files **in the same change**:

- new flag `--foo` → author `docs/commands/<cmd>/option (--)/foo.md`
- removed flag → `git rm` its `.md`
- new enum value (`--type` / `--source` / …) → author `docs/commands/<cmd>/option (--)/<opt> (=value)/<value>.md` and update the hardcoded list inside `scripts/check-docs-commands-drift.sh`
- renamed flag or value → `git mv` then rewrite the body

A drift detector lives at `scripts/check-docs-commands-drift.sh`. Run it before opening a PR:

```bash
cd Packages && swift build         # builds the binary the script reads
cd ..
scripts/check-docs-commands-drift.sh
```

It diffs `cupertino <cmd> --help` against `docs/commands/<cmd>/option (--)/*.md` for every command (visible + hidden) and reports any structural drift (CLI flag without `.md`, `.md` without flag, enum value missing). Exit code 0 = clean, 1 = drift, 2 = invocation error.

The script doesn't validate prose inside the `.md` files — claims like default values, JSON output shapes, or sample output formatting need eyes. If you change a flag's default, an option's behavior, or a JSON encoder's struct, also re-read the corresponding doc.

## Questions?

Open an issue if you have questions or need guidance.
