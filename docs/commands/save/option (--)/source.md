# --source

Source id to build (repeatable). Replaces the pre-#1037 `--docs / --packages / --samples` triplet with per-source granularity.

## Synopsis

```bash
cupertino save --source <id> [--source <id>]...
```

## Description

Selects which source's database `cupertino save` will rebuild. Pass `--source <id>` multiple times to build several sources. Mutually exclusive with `--all`; at least one of `--source` or `--all` is required (bare `cupertino save` with no scope flag is a usage error post-#1037).

## Valid source ids

| id | DB target |
|---|---|
| `apple-docs` | `apple-documentation.db` |
| `swift-evolution` | `swift-evolution.db` |
| `hig` | `hig.db` |
| `apple-archive` | `apple-archive.db` |
| `swift-org` | `swift-documentation.db` (view-source, shared with `swift-book`) |
| `swift-book` | `swift-documentation.db` (view-source, shared with `swift-org`) |
| `samples` | `apple-sample-code.db` (BOTH the Sample.Index rich schema AND SampleCodeSource FTS rows; one DB, two table tracks per #1037) |
| `packages` | `packages.db` (standalone PackagesService pipeline) |

## Examples

```bash
# Build just the Apple Developer Documentation DB.
cupertino save --source apple-docs

# Build apple-documentation.db + hig.db.
cupertino save --source apple-docs --source hig

# Build samples (writes both rich + FTS tracks to apple-sample-code.db).
cupertino save --source samples
```

## Notes

Internal-dispatch granularity, current state (post the commit that added this flag): `--source <id>` resolves to bucket-level booleans (`buildDocs` / `buildPackages` / `buildSamples`) for now; passing any docs-style source today triggers the full docs runner, which still builds every docs-side DB. The per-source-id dispatch refactor (so `--source apple-docs` builds ONLY apple-documentation.db) lands in a follow-up commit. The CLI surface is final.

## Related

- `--all` – build every source's DB
- `cupertino fetch --source <id>` – download a source's raw corpus before `save`
- `cupertino doctor` – inspect per-source DB state
