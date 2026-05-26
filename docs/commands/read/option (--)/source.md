# --source

Disambiguator for non-URI identifiers.

## Synopsis

```bash
cupertino read <identifier> --source <name>
```

## Description

`cupertino read` dispatches across docs / samples / packages by inferring from identifier shape (URI scheme -> docs; otherwise tries samples then packages). When the auto-inference can't tell sample-file paths from package paths apart, `--source` resolves it. `cupertino search` always emits `--source` in its `Read full:` hint, so the command is unambiguous when copied verbatim ([#239](https://github.com/mihaelamj/cupertino/issues/239) follow-up).

Post-#1037 each docs source owns its own SQLite file; `--source` ALSO drives the per-source DB lookup for non-URI identifiers (e.g. `cupertino read some-slug --source hig` opens `hig.db`). For URI identifiers the scheme is the canonical disambiguator; passing `--source` with a URI is allowed only when both agree.

## Values

| Value | DB | Identifier shape |
|---|---|---|
| `apple-docs` | `apple-documentation.db` | URI (`apple-docs://...`) or slug |
| `apple-archive` | `apple-archive.db` | URI (`apple-archive://...`) or slug |
| `hig` | `hig.db` | URI (`hig://...`) or slug |
| `swift-evolution` | `swift-evolution.db` | URI (`swift-evolution://...`) or slug |
| `swift-org` | `swift-org.db` | URI (`swift-org://...`) or slug |
| `swift-book` | `swift-book.db` | URI (`swift-book://...`) or slug |
| `samples` (alias: `apple-sample-code`) | `apple-sample-code.db` | slug or `<projectId>/<path>` |
| `packages` | `packages.db` | `<owner>/<repo>/<relpath>` |

## Default

Auto-detected:
- URI scheme present -> docs (per-source DB picked from the scheme)
- Otherwise: try samples first, fall through to packages on miss

## URI vs --source disagreement

When a URI identifier carries a scheme AND `--source` is given, the two must match. Pre-#1039 a mismatch silently routed to the `--source` backend and returned `docsNotFound` against the wrong DB; post-#1039 the CLI rejects the mismatch with an explicit diagnostic before opening any file:

```
❌ --source 'apple-docs' disagrees with URI scheme 'hig'. Drop --source (the URI is unambiguous) or change one to match the other.
```

The `samples` <-> `apple-sample-code` alias pair is treated as equivalent.

## Examples

### Sample project (slug)

```bash
cupertino read swiftui-adopting-drag-and-drop-using-swiftui --source samples
```

### Sample file

```bash
cupertino read swiftui-foo/Sources/main.swift --source samples
```

### Sample project via the alias

```bash
cupertino read swiftui-adopting-drag-and-drop-using-swiftui --source apple-sample-code
```

### Package source file

```bash
cupertino read pointfreeco/swift-navigation/Sources/.../UIKitNavigation.md --source packages
```

### Docs URI (auto-detected, --source optional)

```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view"
```

### Non-URI docs identifier with explicit source

```bash
cupertino read standard-button-doc-slug --source hig
```

## Notes

- Backed by `Services.ReadService.resolveSource(...)` + per-backend dispatchers.
- `--source samples` explicit invocations do NOT silently fall through to packages on miss; they error with the offending identifier so a typo is caught.
- Auto-source mode (no `--source`) chains samples -> packages and reports `notFoundAnywhere` if both miss.
- For docs URIs the scheme is the canonical disambiguator; the `--source` flag is then optional + must match if given.
