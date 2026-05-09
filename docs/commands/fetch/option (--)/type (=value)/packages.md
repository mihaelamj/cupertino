# --type packages

Fetch Swift Package Documentation: metadata catalog (Swift Package Index + GitHub stars) plus the priority-package source archives in a single run.

## Synopsis

```bash
cupertino fetch --type packages
cupertino fetch --type packages --skip-archives                     # metadata only
cupertino fetch --type packages --skip-metadata                     # archives only
cupertino fetch --type packages --annotate-availability             # all three stages
cupertino fetch --type packages --skip-metadata --skip-archives \
                                --annotate-availability             # annotation pass over an existing on-disk corpus
```

## Description

Runs up to three stages. Stages 1 and 2 run by default; stage 3 is opt-in. Any stage can be skipped via the corresponding flag (#217 merged the previous separate `--type package-docs` into stage 2; #219 added stage 3).

### Stage 1 — Metadata refresh

Pulls the full Swift Package Index listing and decorates each entry with GitHub repo metadata (stars, language, license, last-update timestamp, fork/archived status). Output: `swift-packages-with-stars.json` in the packages directory. Used to regenerate the embedded `SwiftPackagesCatalogEmbedded.swift` and to power package-related search/analysis.

### Stage 2 — Priority archive download

Reads the priority-packages list (`PriorityPackagesCatalog`), resolves the transitive dependency closure of each seed via `Package.swift` (and `Package.resolved` as fallback for apps), then downloads + extracts a tarball per package via `PackageArchiveExtractor`. The extractor pulls `https://codeload.github.com/<owner>/<repo>/tar.gz/<ref>` (HEAD → main → master fallback) and keeps a filtered subset: `README*`, `CHANGELOG*`, `LICENSE*`, `Package.swift`, all of `Sources/` + `Tests/`, every `.docc` article and tutorial, plus `Examples/` / `Demo/` directories. Each package gets a `manifest.json`.

### Stage 3 — Availability annotation ([#219](https://github.com/mihaelamj/cupertino/issues/219), opt-in via `--annotate-availability`)

Walks every `<owner>/<repo>/` subdir on disk and writes a per-package `availability.json` next to `manifest.json`. Captures:

- `Package.swift` `platforms: [...]` deployment-target block (mapped to `{iOS: 13.0, macOS: 10.15, …}`).
- Every `@available(...)` attribute occurrence in `.swift` files under `Sources/` and `Tests/`, with file path, line number, and parsed platform list.

Pure on-disk pass — no network. Idempotent. Regex-based; multi-line attrs aren't handled and hits aren't associated with specific declarations (AST upgrade is a follow-up). Runs whether or not stages 1 and 2 just executed, so you can re-annotate an existing corpus with `--skip-metadata --skip-archives --annotate-availability`.

## Data Sources

1. **Swift Package Index API** — package listings
2. **GitHub API** — repository metadata (stars, description, language, license, …) for stage 1; tarball download for stage 2
3. **PriorityPackagesCatalog** — `~/.cupertino/selected-packages.json` (or the embedded fallback) drives which packages stage 2 downloads

## Output

| File | Stage | Purpose |
|------|-------|---------|
| `swift-packages-with-stars.json` | 1 | Full SPI catalog with stars / metadata |
| `<owner>/<repo>/...` tree | 2 | Extracted source per priority package |
| `<owner>/<repo>/manifest.json` | 2 | Per-package fetch manifest |
| `resolved-packages.json` (in base dir) | 2 | Cached dependency closure |

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/packages` |
| GitHub auth | optional but strongly recommended (rate limits) |
| Estimated count | ~10,000 packages (stage 1) + ~50–200 packages (stage 2 closure) |

## Options

| Option | Description |
|--------|-------------|
| `--skip-metadata` | Skip stage 1 and run only the archive download |
| `--skip-archives` | Skip stage 2 and run only the metadata refresh |
| `--annotate-availability` | Run stage 3 (availability annotation) after the chosen stages — opt-in (#219) |
| `--limit <N>` | (stage 1) cap the number of packages fetched from SPI |
| `--start-clean` | (stage 1) discard any saved metadata-fetch checkpoint |
| `--output-dir <path>` | override the output directory |

Passing both `--skip-metadata` and `--skip-archives` without `--annotate-availability` is an error (nothing to do).

## Examples

### Default — both stages

```bash
cupertino fetch --type packages
```

### Refresh metadata only (e.g. before regenerating the embedded catalog)

```bash
cupertino fetch --type packages --skip-archives
```

### Download archives only (when metadata is already current)

```bash
cupertino fetch --type packages --skip-metadata
```

### Fetch a limited metadata sample

```bash
cupertino fetch --type packages --skip-archives --limit 100
```

### Custom output directory

```bash
cupertino fetch --type packages --output-dir ./my-packages
```

### Discard saved session and start over

```bash
cupertino fetch --type packages --start-clean
```

## Output File Structure (stage 1)

```json
{
  "version": "1.0",
  "lastCrawled": "2026-05-03",
  "source": "Swift Package Index + GitHub API",
  "count": 9699,
  "packages": [
    {
      "owner": "apple",
      "repo": "swift-nio",
      "url": "https://github.com/apple/swift-nio",
      "description": "Event-driven network application framework",
      "stars": 7500,
      "language": "Swift",
      "license": "Apache-2.0",
      "fork": false,
      "archived": false,
      "updatedAt": "2026-04-15T10:30:00Z"
    }
  ]
}
```

## Use Cases

- Refresh `SwiftPackagesCatalogEmbedded.swift` after Swift Package Index updates
- Build `packages.db` via `cupertino save --type packages`
- Provide source for `cupertino package-search` queries
- Analyse the Swift package ecosystem (stars, licences, activity)

## Notes

- A GitHub token (`GH_TOKEN`) is strongly recommended — without it stage 1 hits the unauthenticated rate limit (60 req/h) very quickly and stage 2 can stall on tarball downloads.
- Stages run sequentially; if stage 1 fails, stage 2 is still attempted (priority list comes from `PriorityPackagesCatalog`, not from the metadata catalog).
- `--type all` invokes this command and so picks up both stages by default.
