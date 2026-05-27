# --source packages

Fetch Swift package source archives for `packages.db` indexing. Optionally also refresh the Swift Package Index metadata catalog (stars-sort, TUI-only) and write per-package availability sidecars.

## Synopsis

```bash
cupertino fetch --source packages                                       # priority archives only (default)
cupertino fetch --source packages --refresh-metadata                    # also run stage 1 (SPI metadata + stars)
cupertino fetch --source packages --refresh-metadata --skip-archives    # stage 1 only
cupertino fetch --source packages --annotate-availability               # archives + per-package availability.json
cupertino fetch --source packages --skip-archives --annotate-availability  # annotate an existing on-disk corpus, no network
```

## Description

Runs up to three stages. Post-[#1108](https://github.com/mihaelamj/cupertino/issues/1108):

- **Stage 1** (metadata refresh) is **opt-in** via `--refresh-metadata`. Its output is consumed only by the TUI's stars-sort view.
- **Stage 2** (archive download) is the default. It produces the on-disk corpus consumed by `cupertino save --source packages`.
- **Stage 3** (availability annotation) is opt-in via `--annotate-availability`.

### Stage 1, Metadata refresh (opt-in via `--refresh-metadata`)

Pulls the full Swift Package Index listing (~10,995 packages) and decorates each entry with GitHub repo metadata (stars, language, license, last-update timestamp, fork/archived status). Output: `swift-packages-with-stars.json` in the packages directory. Used to regenerate the embedded `SwiftPackagesCatalogEmbedded.swift` and to power package-related search/analysis in the TUI. Without `GITHUB_TOKEN` set, the per-package throttle (`Shared.Constants.Delay.packageFetchNormal = 1.2 s`) adds up to roughly 4 hours, which is why this stage is no longer the default.

### Stage 2, Priority archive download (default)

Reads the priority-packages list (`PriorityPackagesCatalog`), resolves the transitive dependency closure of each seed via `Package.swift` (and `Package.resolved` as fallback for apps), then downloads + extracts a tarball per package via `PackageArchiveExtractor`. The extractor pulls `https://codeload.github.com/<owner>/<repo>/tar.gz/<ref>` (HEAD → main → master fallback) and keeps a filtered subset: `README*`, `CHANGELOG*`, `LICENSE*`, `Package.swift`, all of `Sources/` + `Tests/`, every `.docc` article and tutorial, plus `Examples/` / `Demo/` directories. Each package gets a `manifest.json`. Anonymous codeload (no `GITHUB_TOKEN` needed) typically completes the 135-archive closure in ~100 seconds.

### Stage 3, Availability annotation ([#219](https://github.com/mihaelamj/cupertino/issues/219), opt-in via `--annotate-availability`)

Walks every `<owner>/<repo>/` subdir on disk and writes a per-package `availability.json` next to `manifest.json`. Captures:

- `Package.swift` `platforms: [...]` deployment-target block (mapped to `{iOS: 13.0, macOS: 10.15, …}`).
- Every `@available(...)` attribute occurrence in `.swift` files under `Sources/` and `Tests/`, with file path, line number, and parsed platform list.

Pure on-disk pass, no network. Idempotent. Regex-based; multi-line attrs aren't handled and hits aren't associated with specific declarations (AST upgrade is a follow-up). Runs whether or not stages 1 and 2 just executed, so you can re-annotate an existing corpus with `--skip-archives --annotate-availability`.

## Data Sources

1. **Swift Package Index API**, package listings (stage 1 only)
2. **GitHub API**, repository metadata (stars, description, language, license, …) for stage 1
3. **`codeload.github.com`**, anonymous source tarballs (stage 2)
4. **PriorityPackagesCatalog**, `~/.cupertino/selected-packages.json` (or the embedded fallback) drives which packages stage 2 downloads

## Output

| File | Stage | Purpose |
|------|-------|---------|
| `<owner>/<repo>/...` tree | 2 | Extracted source per priority package |
| `<owner>/<repo>/manifest.json` | 2 | Per-package fetch manifest |
| `<owner>/<repo>/availability.json` | 3 | Per-package deployment targets + `@available` occurrences |
| `swift-packages-with-stars.json` | 1 | Full SPI catalog with stars / metadata (TUI input) |
| `resolved-packages.json` (in base dir) | 2 | Cached dependency closure |

## Default Settings

| Setting | Value |
|---------|-------|
| Output Directory | `~/.cupertino/packages` |
| Stage 1 (`--refresh-metadata`) | off |
| Stage 2 (archive download) | on |
| Stage 3 (`--annotate-availability`) | off |
| GitHub auth | optional, not required for stage 2; strongly recommended for stage 1 |
| Estimated count | ~135 priority packages + transitive closure (stage 2); ~10,000 packages (stage 1) |

## Options

| Option | Description |
|--------|-------------|
| `--refresh-metadata` | Run stage 1 in addition to the default archive download (#1108) |
| `--skip-archives` | Skip stage 2 (pair with `--refresh-metadata` or `--annotate-availability`) |
| `--annotate-availability` | Run stage 3 (availability annotation) after the chosen stages, opt-in (#219) |
| `--limit <N>` | (stage 1) cap the number of packages fetched from SPI |
| `--start-clean` | (stage 1) discard any saved metadata-fetch checkpoint |
| `--output-dir <path>` | override the output directory |

`--skip-archives` without `--refresh-metadata` or `--annotate-availability` is an error (nothing to do).

## Examples

### Default, archive download only

```bash
cupertino fetch --source packages
```

### Refresh SPI metadata + stars (TUI use case)

```bash
cupertino fetch --source packages --refresh-metadata
```

### Refresh metadata only (e.g. before regenerating the embedded catalog), no archives

```bash
cupertino fetch --source packages --refresh-metadata --skip-archives
```

### Re-annotate an existing on-disk corpus, no network

```bash
cupertino fetch --source packages --skip-archives --annotate-availability
```

### Fetch a limited metadata sample

```bash
cupertino fetch --source packages --refresh-metadata --skip-archives --limit 100
```

### Custom output directory

```bash
cupertino fetch --source packages --output-dir ./my-packages
```

### Discard saved session and start over (stage 1)

```bash
cupertino fetch --source packages --refresh-metadata --start-clean
```

## Output File Structure (stage 1, when `--refresh-metadata` is passed)

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

- Build `packages.db` via `cupertino save --source packages` (default invocation, no flags)
- Refresh `SwiftPackagesCatalogEmbedded.swift` after Swift Package Index updates (`--refresh-metadata`)
- Provide source for `cupertino package-search` queries
- Analyse the Swift package ecosystem (stars, licences, activity) via stage 1's output

## Notes

- Stage 2 uses anonymous `codeload.github.com` (no token, no rate-limit pain).
- Stage 1 hits `api.github.com`, capped at 60 req/h without `GITHUB_TOKEN`. Setting the token raises the cap to 5,000 req/h.
- Pre-#1108 stage 1 ran by default. The flag rename `--skip-metadata` → `--refresh-metadata` is a breaking change for any script that used the opt-out shape.
- `--source all` invokes this command with default flags (stage 2 only).
