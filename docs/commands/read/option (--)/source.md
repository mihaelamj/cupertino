# --source

Disambiguator for non-URI identifiers

## Synopsis

```bash
cupertino read <identifier> --source <name>
```

## Description

`cupertino read` dispatches across docs / samples / packages by inferring from identifier shape (URI scheme → docs; otherwise tries samples then packages). When the auto-inference can't tell sample-file paths from package paths apart, `--source` resolves it. `cupertino search` always emits `--source` in its `Read full:` hint, so the command is unambiguous when copied verbatim. ([#239](https://github.com/mihaelamj/cupertino/issues/239) follow-up)

## Values

| Value | DB | Identifier shape |
|---|---|---|
| `apple-docs`, `apple-archive`, `hig`, `swift-evolution`, `swift-org`, `swift-book` | `search.db` | URI |
| `samples`, `apple-sample-code` | `samples.db` | slug or `<projectId>/<path>` |
| `packages` | `packages.db` | `<owner>/<repo>/<relpath>` |

## Default

Auto-detected:
- URI scheme present → docs
- Otherwise: try samples first, fall through to packages on miss.

## Examples

### Sample project (slug)
```bash
cupertino read swiftui-adopting-drag-and-drop-using-swiftui --source samples
```

### Sample file
```bash
cupertino read swiftui-foo/Sources/main.swift --source samples
```

### Package source file
```bash
cupertino read pointfreeco/swift-navigation/Sources/.../UIKitNavigation.md --source packages
```

### Docs URI (auto-detected, --source optional)
```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view"
```

## Notes

- Backed by `Services.ReadService.resolveSource(...)` + per-backend dispatchers.
- `--source samples` explicit invocations do NOT silently fall through to packages on miss; they error with the offending identifier so a typo is caught.
- Auto-source mode (no `--source`) chains samples → packages and reports `notFoundAnywhere` if both miss.
