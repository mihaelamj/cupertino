# samples

Sample code projects source (samples.db, populated by `cupertino save --samples`)

## Synopsis

```bash
cupertino search <query> --source samples
```

## Description

Filters search results to only include sample code projects. Searches the dedicated `samples.db` (built by `cupertino save --samples`) which holds README text + per-source-file content for every sample project crawled from GitHub via `cupertino fetch --type samples`.

## Content

- **Project metadata** (name, README, license, deployment targets)
- **Source file content** indexed by relative path (`Sources/Foo.swift`, `Tests/...`)
- **Framework associations** derived from import statements
- **Symbol-level AST** entries for `@Observable`, `@MainActor`, async functions, `View` conformances, etc.

## Typical Size

- Driven by which projects are crawled — see `cupertino fetch --type samples`
- `~/.cupertino/samples.db` schema v3
- Hundreds of projects → tens of thousands of indexed files

## Examples

### Search for SwiftUI sample code
```bash
cupertino search "SwiftUI animation" --source samples
```

### Find @Observable usage in samples
```bash
cupertino search "@Observable" --source samples
```

### Find concurrency patterns
```bash
cupertino search "actor reentrancy" --source samples
```

## URI Format

Results use the `samples://` URI scheme. The CLI's `cupertino read --source samples <uri>` and the MCP `read_sample` / `read_sample_file` tools resolve these.

## How to Populate

```bash
# Fetch sample projects from GitHub (uses bundled priority list)
cupertino fetch --type samples

# Build samples.db
cupertino save --samples
```

## Use Cases

- **Learning** — find working examples of an API in real projects
- **Pattern-matching** — see how others structure code around a type or framework
- **Cross-reference** — pair with `--source apple-docs` to read the doc + see usage

## Notes

- Different from `--source apple-archive` (legacy programming guides) and `--source apple-docs` (modern API reference).
- Skipped automatically if `samples.db` is missing — see `cupertino doctor`.
