# samples

Sample code projects from GitHub (recommended)

## Synopsis

```bash
cupertino fetch --type samples
```

## Description

Crawls sample code projects directly from GitHub. This is the **recommended** way to populate sample-code data — it pulls live sources (Sources/, Tests/, Package.swift, README, .docc/) from each project's GitHub repository.

Different from `--type code`, which scrapes Apple's bundled sample-code catalog at `developer.apple.com/sample-code` (HTML + zip downloads). `samples` is the GitHub path; `code` is the Apple-catalog path.

## Output

Default output directory: `~/.cupertino/sample-code/<owner>/<repo>/` per project.

Each project directory contains:
- `README.md`, `LICENSE`, `Package.swift`
- Full `Sources/` and `Tests/` trees
- `.docc/` articles and tutorials (when present)
- `Examples/` / `Demo/` directories
- Per-project `manifest.json` (owner, repo, branch, fetched-at, file count)

## Typical Size

- Hundreds of projects, tens of MB to single-digit GB depending on which projects are crawled.
- Source code only — no compiled artifacts.

## Examples

### Fetch all priority sample projects
```bash
cupertino fetch --type samples
```

### Then build the index
```bash
cupertino save --samples
```

## Notes

- Replaces the older `--type code` Apple-catalog path for everyday use.
- Project list is bundled in `Resources` (priority-package catalog).
- Resumable: re-running picks up where the last fetch left off.
- Pair with `cupertino save --samples` to populate `samples.db`.
