# --search-db

Override the docs database path.

## Synopsis

```bash
cupertino read <uri> --search-db <path>
```

## Description

Post-#1037 every docs source owns its own SQLite file (`apple-documentation.db` for apple-docs, `hig.db` for HIG, `apple-archive.db` for the legacy archive, `swift-evolution.db` for proposals, `swift-org.db` + `swift-book.db` for the Swift website + book). The default routing for `cupertino read` resolves the URI's scheme through the production source registry and opens the matching per-source file.

When `--search-db <path>` is set, EVERY docs source-id routes to the override URL for the duration of the call (legacy single-DB debug semantic). This lets you point the read command at a snapshot DB, a custom-built index, or a test fixture without modifying the production install.

## Default

Resolved through the production source registry: `~/.cupertino/apple-documentation.db` for `apple-docs://`, `~/.cupertino/hig.db` for `hig://`, etc. Use `cupertino doctor` to see the canonical per-source paths.

## Examples

### Read from a snapshot apple-documentation.db

```bash
cupertino read "apple-docs://swiftui/documentation_swiftui_view" --search-db ~/snapshots/apple-documentation.db
```

### Redirect every docs source-id to a single custom file

```bash
# All URIs (apple-docs, hig, swift-evolution, swift-org, swift-book, apple-archive)
# route to /tmp/my-docs.db with --search-db set.
cupertino read "hig://patterns/launching" --search-db /tmp/my-docs.db
cupertino read "swift-evolution://SE-0302" --search-db /tmp/my-docs.db
```

### Read against a relocated dev install

```bash
cupertino read "apple-docs://swift/documentation_swift_array" --search-db ~/.cupertino-dev/apple-documentation.db
```

## Use Cases

- **Multiple indexes**: read from a separate dev / staging index without touching production
- **Testing**: read against a fixture DB built per-test-suite
- **Snapshots**: read from a saved historical bundle to compare doc evolution
- **Custom builds**: read against the output of a custom `cupertino save` run

## Creating a Custom Database

```bash
# Fetch documentation into a custom base directory
cupertino fetch --source apple-docs --output-dir ~/custom-docs

# Build the index under that base directory
cupertino save --base-dir ~/custom-docs --source apple-docs

# Read using the custom per-source DB
cupertino read "apple-docs://swiftui/documentation_swiftui_view" \
  --search-db ~/custom-docs/apple-documentation.db
```

## Notes

- Tilde (`~`) expansion is supported.
- The override file must exist; the read fails with an explicit diagnostic when it does not.
- When set, the override overrides ALL docs source-ids, not just apple-docs. To read from per-source files individually, run `cupertino read` without the flag.
- The override does not affect `--sample-db` or `--packages-db`; samples and packages still resolve through their own per-DB flags.
