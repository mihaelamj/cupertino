# Design: Formal Corpus Structure (per-source folder layout + manifest schema)

## Status (2026-05-25)

Draft. Companion to `docs/design/per-source-db-split.md` (the
implementation arc for the per-source DB split epic). This doc is the
durable spec: it defines the on-disk shape of a source's raw corpus
folder, the repo-side `manifest.yaml` each source declares, and the
contract between the two that lets the indexer ingest a new source
without any per-source `switch` statement.

The user direction that motivates this doc (2026-05-25):

> let's define the docs structure in a formal way, so that the
> indexer can index new code, also adding new source does require a
> PR so remember that

This doc is the *what*. The implementation doc (per-source-db-split)
is the *how*. The schema spec (per-db-schema-spec) is the *output*
shape of each built DB. Three docs, one pipeline.

---

## 0. How to read this doc

Read sections in order if you have zero context. §1 explains why
cupertino has a "corpus" at all and what's currently inside it. §2
defines the canonical on-disk layout under `~/.cupertino-dev/corpus/`.
§3 defines the repo-side `docs/sources/<id>/manifest.yaml` schema.
§4 walks the indexer's pickup logic against §2 + §3. §5 walks
end-to-end through adding a hypothetical new source (WWDC transcripts
[#58]) to demonstrate the 4-file PR claim. §6 catalogues failure
modes. §7 lists the migration tasks to bring existing sources onto
this contract.

If you already know cupertino, jump to §3 (manifest schema) and §5
(worked example).

---

## 1. What "corpus" means in cupertino

cupertino fetches raw content from upstream (Apple's documentation
server, swift.org's git repo, swift-evolution's git repo, GitHub
archives, etc.) and stores it on disk before indexing it into the
shipped SQLite databases. The on-disk staging area is the **corpus**.

Once corpus is in place, `cupertino save` reads from corpus and writes
to the corresponding DB. The corpus exists separately from the DB so
that:

1. Re-indexing without re-fetching is possible (incremental schema
   changes, ranking-weight tweaks, postprocessor passes).
2. Diffing what Apple changed between two crawl snapshots is a `git
   diff` against the corpus directory (the corpus is git-tracked at
   `cupertino-docs` for the public mirror, per
   `corpus-as-git-time-series` memory).
3. Tests can run against a small fixture corpus without needing the
   full ~2.7 GB live corpus.

Today the corpus folder layout grew organically. Each source picked
its own subdirectory name and file extensions, the indexer learned
how to read each shape, and the binding lives implicitly in each
strategy's source code. This doc formalizes the contract so the
binding is declarative instead.

---

## 2. On-disk corpus layout

The canonical root is `~/.cupertino-dev/corpus/` (development) or
`~/.cupertino/corpus/` (production, owned by Homebrew). The layout
under that root is the same in both modes:

```
~/.cupertino-dev/corpus/
├── apple-documentation/
│   ├── manifest.json           ← runtime manifest (snapshot metadata)
│   ├── documentation/          ← Apple's JSON-API tree
│   │   ├── swiftui.json
│   │   ├── swiftui/
│   │   │   ├── view.json
│   │   │   └── ...
│   │   └── ...
│   └── tutorials/
├── hig/
│   ├── manifest.json
│   └── pages/                  ← HTML/JSON for each HIG page
├── apple-archive/
│   ├── manifest.json
│   └── guides/                 ← legacy programming guides
├── swift-evolution/
│   ├── manifest.json
│   └── proposals/              ← *.md
├── swift-documentation/
│   ├── manifest.json
│   ├── swift-org/              ← swift.org/documentation/* trees
│   └── swift-book/             ← swift.org/documentation/the-swift-programming-language/ trees
│                                  (view-source: same fetcher as swift-org,
│                                   tagged by URL prefix at index time)
├── apple-sample-code/
│   ├── manifest.json
│   └── projects/               ← one folder per sample project
└── swift-packages/
    ├── manifest.json
    ├── metadata/               ← GitHub + SwiftPM metadata JSON
    └── archives/               ← per-package source archives
```

### 2.1 Folder name = source id

The folder name MUST equal the source's canonical id
(`Search.SourceProvider.definition.id`, e.g. `apple-documentation`).
This is the single binding between corpus and code: given a corpus
folder, the indexer looks up the matching `SourceProvider` by id;
given a `SourceProvider`, the corpus folder it owns is at
`<corpusRoot>/<id>/`.

### 2.2 manifest.json (runtime snapshot)

Every corpus folder contains a `manifest.json` at its root. This is
the **runtime manifest**: written by the fetcher when content lands,
read by the indexer when content is ingested. Its shape:

```json
{
  "schemaVersion": 1,
  "sourceId": "apple-documentation",
  "fetchedAt": "2026-05-18T06:20:14+0200",
  "fetcherBinaryVersion": "1.2.0",
  "upstreamRevision": {
    "kind": "apple-docs-api",
    "snapshotDate": "2026-05-18",
    "sampledURL": "https://developer.apple.com/tutorials/data/index/swiftui"
  },
  "stats": {
    "fileCount": 412034,
    "byteCount": 2823914561
  }
}
```

The `upstreamRevision` block is source-specific (git sha for
swift-evolution, snapshot timestamp for apple-docs, GitHub commit
hash list for swift-packages). Each source's `manifest.yaml` (§3)
declares what shape its runtime manifest's `upstreamRevision` block
must have.

### 2.3 Why one folder per source instead of one mixed tree

Per-source isolation gives:

- A new source = a new folder + a new SPM target. Touches no other
  source's bytes on disk.
- `du -sh corpus/hig` answers "how big is HIG?" without grep.
- A failed re-fetch of one source can be rolled back by `rm -rf
  corpus/<id> && cupertino fetch --source <id>`.
- `git diff corpus/apple-documentation/` (against the public mirror)
  shows only apple-doc changes; cross-source noise removed.
- The per-source DB split (`<id>.db` per folder) becomes a 1:1 mapping
  from corpus folder to DB file.

---

## 3. Repo-side `docs/sources/<id>/manifest.yaml`

Each source ships a `manifest.yaml` in the repo at
`docs/sources/<source-id>/manifest.yaml`. This is the **declared
manifest**: the source's contract with the indexer, checked in to
git, reviewed at PR time, never written at runtime.

The repo path uses kebab-case source-id so the indexer can resolve
`docs/sources/<provider.definition.id>/manifest.yaml` mechanically.

### 3.1 Schema

```yaml
# Required: identity
sourceId: apple-documentation       # MUST match provider.definition.id
displayName: Apple Developer Documentation
description: |
  Apple's reference documentation for every framework, type, and
  symbol exposed via developer.apple.com/documentation.

# Required: where this source's bytes live on disk
corpusFolder: apple-documentation   # same as sourceId by convention

# Required: which DB the indexer writes to
destinationDB: apple-documentation  # canonical DatabaseDescriptor name

# Required: how the fetcher acquires content
fetcher:
  kind: apple-docs-api              # one of: apple-docs-api,
                                    #         git-clone,
                                    #         http-archive,
                                    #         github-api,
                                    #         file-bundle
  options:
    rootURL: https://developer.apple.com/tutorials/data/index
    requestDelaySeconds: 0.05

# Required: how the indexer walks the corpus folder
indexer:
  # Globs the indexer iterates, relative to corpusFolder root
  fileGlobs:
    - documentation/**/*.json
    - tutorials/**/*.json
  # Files matching these patterns are skipped (precedence over fileGlobs)
  excludes:
    - "**/_metadata.json"
  # Entry-point files the indexer treats specially (e.g. framework hubs)
  entryPoints:
    - documentation/*.json
  # Reference to the Swift type that owns extraction.
  # Must conform to Search.SourceIndexer and be in the source's SPM target.
  extractor: Search.AppleDocsExtractor

# Optional: view-source companions (see swift-documentation)
viewSources:
  - id: swift-book
    urlPrefix: https://docs.swift.org/swift-book/

# Optional: snapshot freshness policy
snapshotPolicy:
  staleAfterDays: 30
  refetchOn:
    - schema-bump
    - explicit-recrawl

# Optional: search-time properties
searchProperties:
  searchQuality: 1.0                # 0.0 - 1.0; HIG=0.9, sample-code=0.7
  intentDefault: reference           # one of: reference, conceptual, sample, news
  rankWeight: 1.0

# Required: what this source can answer (capabilities declaration)
# Read at runtime to gate which searchers / operations / MCP tools
# fan out to this source's DB. See §3.5 for vocabulary + semantics.
capabilities:
  searchers:                        # which search modes this DB answers
    - text                          # FTS5 plain-text query (every source has this)
    - symbols                       # `cupertino search-symbols`
    - property-wrappers             # `cupertino search-property-wrappers`
    - concurrency                   # `cupertino search-concurrency`
    - conformances                  # `cupertino search-conformances`
    - generics                      # `cupertino search-generics`
  operations:                       # which non-search ops this DB answers
    - read-by-uri                   # `cupertino read <uri>`
    - list-frameworks               # `cupertino list-frameworks`
    - resolve-refs                  # `cupertino resolve-refs`
  metadata:                         # typed feature flags about the rows
    hasMinPlatformVersion: true     # iOS/macOS/tvOS/watchOS/visionOS gating
    hasMinSwiftVersion: false       # only swift-packages / swift-evolution set this
    hasSampleCode: false            # only apple-sample-code sets this
    hasGenerics: true               # generics column populated
    hasDeprecationAttrs: true       # platform deprecation attrs preserved
    hasAvailabilityAttrs: true      # @available decorations preserved
    hasFrameworkColumn: true        # framework column populated (false for swift-evolution)
```

### 3.2 Required fields

`sourceId`, `displayName`, `corpusFolder`, `destinationDB`, `fetcher`,
`indexer`, `capabilities`. Missing any of these makes `cupertino
doctor` fail the source.

### 3.3 Optional fields

`description`, `viewSources`, `snapshotPolicy`, `searchProperties`.
Defaults are documented under each field; absence is not an error.

### 3.4 Why YAML for the declared manifest, JSON for the runtime manifest

YAML for the declared manifest because humans write it, review it in
diffs, and want comments. JSON for the runtime manifest because the
fetcher writes it programmatically, it's small, and tools that
inspect crash dumps read JSON natively.

### 3.5 Capabilities vocabulary (per-source feature contract)

User direction (2026-05-25):

> it will be easier for us to handle source by db. And then each
> source could inform us which searchers and operations it supports,
> like min version, code and similar, add that.

`capabilities` is the manifest's per-source feature contract. It is
read at runtime by the CLI dispatcher, by the MCP server's
tool-availability advertisement, and by `cupertino doctor`. The
union of all source capabilities tells the user what the installed
bundle can answer; the intersection tells the dispatcher which DBs
to fan-out a given query into.

#### 3.5.1 `searchers` (which search modes the DB answers)

A search mode here is a CLI subcommand or MCP tool that hits the DB
with a structured query. Allowed values today:

| Value | CLI / MCP surface | What it does |
|-------|-------------------|--------------|
| `text` | `cupertino search`, `mcp:search` | FTS5 plain-text query over title + content. Every search-bound source has this. |
| `symbols` | `cupertino search-symbols`, `mcp:search_symbols` | Filter rows by `doc_symbols.kind = 'symbol'` matching a name pattern. Requires a `doc_symbols` table. |
| `property-wrappers` | `cupertino search-property-wrappers` | Filter rows where the row's symbol kind matches a property-wrapper attribute. |
| `concurrency` | `cupertino search-concurrency` | Filter rows by concurrency attributes (`async` / `actor` / `@MainActor` / `Sendable` / `nonisolated` / `sending` / `isolated` / etc.). |
| `conformances` | `cupertino search-conformances` | Filter rows by declared protocol conformances. |
| `generics` | `cupertino search-generics` | Filter rows by generic constraints (`<T: View>` etc.). |
| `package-search` | `cupertino package-search` | Search SwiftPM package metadata + READMEs + Package.swift contents. swift-packages-only. |
| `sample-files` | `cupertino read-sample-file` | Read named source files from sample-code projects. apple-sample-code-only. |

A source's manifest lists ONLY the searchers its DB can actually
answer. swift-evolution.db (markdown proposals, no extracted symbols)
lists `[text]` and nothing else. apple-documentation.db lists the
full set except `package-search` + `sample-files`.

#### 3.5.2 `operations` (non-search ops the DB answers)

Operations are CLI subcommands / MCP tools that read the DB without
a structured query:

| Value | Surface | What it does |
|-------|---------|--------------|
| `read-by-uri` | `cupertino read <uri>` | Fetch one row by its URI. Every source has this. |
| `list-frameworks` | `cupertino list-frameworks` | Enumerate distinct framework values. apple-documentation only. |
| `list-samples` | `cupertino list-samples` | Enumerate sample-code projects. apple-sample-code only. |
| `resolve-refs` | `cupertino resolve-refs` | Resolve cross-doc references (relative URIs, `doc:` links). apple-documentation only. |

#### 3.5.3 `metadata` (typed feature flags)

Boolean flags describing what the DB's row shape carries. These
inform UI presentation (cupertino doctor's per-DB section), MCP
tool descriptions exposed to AI clients, and the CLI's
filter-construction logic (e.g. don't construct a `--min-ios 16`
filter against a DB whose `hasMinPlatformVersion` is false).

| Flag | Set on | Meaning |
|------|--------|---------|
| `hasMinPlatformVersion` | apple-documentation, hig, apple-archive, apple-sample-code | Rows carry iOS/macOS/tvOS/watchOS/visionOS first-available version. The `--min-ios <N>` etc. filters apply. |
| `hasMinSwiftVersion` | swift-evolution, swift-packages | Rows carry Swift toolchain version. The `--min-swift <N>` filter applies. |
| `hasSampleCode` | apple-sample-code | Rows are sample projects with source files (not docs). |
| `hasGenerics` | apple-documentation, swift-documentation | The `generic_constraints` column is populated. |
| `hasDeprecationAttrs` | apple-documentation, hig | `@available(*, deprecated)` attributes preserved per row. |
| `hasAvailabilityAttrs` | apple-documentation, hig, swift-documentation | `@available(iOS 16.0, *)` etc. preserved per row. |
| `hasFrameworkColumn` | apple-documentation, hig, apple-archive | The `framework` column is populated; `list-frameworks` works. |
| `hasProposalNumber` | swift-evolution | Rows have `SE-NNNN` identifiers; `--proposal SE-0123` filter applies. |
| `hasPackageMetadata` | swift-packages | Rows are SwiftPM packages with Package.swift + GitHub metadata; `package-search` operates on them. |

This list is the union of all flags any source needs. A source's
manifest lists ONLY the flags that are `true` for it; absent flags
are `false` by default. Adding a new flag is a 3-step PR: add the
flag to this doc's table, set it `true` on the manifest(s) that
need it, teach `cupertino doctor` to display it.

#### 3.5.4 How capabilities flow at query time

1. CLI parses the subcommand + flags.
2. Dispatcher resolves the **required capability set** for that
   subcommand (e.g. `search-symbols` requires `searchers:
   [symbols]`).
3. Dispatcher walks `registry.allEnabled`, filters to providers whose
   `capabilities.searchers` (or `operations`) contains the required
   value.
4. Dispatcher opens each matching provider's `destinationDB` and
   fans the query out.
5. Results are merged (cross-DB ranking weights derived from
   `searchProperties.searchQuality` + `searchProperties.rankWeight`).

A subcommand that no source can answer fails fast:
`error: no installed source supports 'package-search'; install via \`cupertino setup --source swift-packages\``.

#### 3.5.5 Capabilities vs viewSources

`viewSources` is a write-time concept (one strategy emits rows tagged
with two source-ids into one DB). `capabilities` is a read-time
concept (one DB answers some set of search modes). They don't
overlap. `swift-documentation.db` declares `viewSources: [swift-book]`
AND `capabilities.searchers: [text, symbols, ...]` because at write
time the swift-org strategy emits rows for both swift-org and
swift-book, and at read time the resulting DB answers text + symbol
queries for both.

#### 3.5.6 Capabilities matrix for the 7 settled sources

Authoritative table for what each source's manifest declares. Drives
`cupertino doctor` output, MCP tool advertisement, and the CLI
dispatcher's fan-out:

| Source | searchers | operations | metadata flags (true) |
|--------|-----------|------------|------------------------|
| `apple-documentation` | text, symbols, property-wrappers, concurrency, conformances, generics | read-by-uri, list-frameworks, resolve-refs | hasMinPlatformVersion, hasGenerics, hasDeprecationAttrs, hasAvailabilityAttrs, hasFrameworkColumn |
| `hig` | text | read-by-uri, list-frameworks | hasMinPlatformVersion, hasDeprecationAttrs, hasAvailabilityAttrs, hasFrameworkColumn |
| `apple-archive` | text | read-by-uri | hasMinPlatformVersion, hasFrameworkColumn |
| `swift-evolution` | text | read-by-uri | hasMinSwiftVersion, hasProposalNumber |
| `swift-documentation` (swift-org + swift-book view-source) | text, symbols, generics | read-by-uri | hasGenerics, hasAvailabilityAttrs |
| `apple-sample-code` | text, sample-files | read-by-uri, list-samples | hasMinPlatformVersion, hasSampleCode |
| `swift-packages` | text, package-search | read-by-uri | hasMinSwiftVersion, hasPackageMetadata |

This matrix is the cross-check between the manifest YAML and the
real CLI. CI's `check-source-manifests.sh` runs the union of these
columns against the binary's `--help` surface and fails on drift.

---

## 4. How the indexer uses the contract

`cupertino save` iterates the source registry. For each provider:

1. Resolve `docs/sources/<provider.definition.id>/manifest.yaml`.
   If the file doesn't exist, fail with `error: source '<id>' has no
   manifest at <path>; see docs/design/corpus-structure.md §3`.
2. Resolve corpus folder: `<corpusRoot>/<manifest.corpusFolder>/`.
   If the folder doesn't exist, fail with `error: source '<id>'
   has no corpus folder; run \`cupertino fetch --source <id>\` first`.
3. Read the runtime `manifest.json` inside the corpus folder. Verify
   `sourceId` matches.
4. Walk `manifest.indexer.fileGlobs`, applying
   `manifest.indexer.excludes`. For each match, call the
   `provider.makeIndexer()` returned `Search.SourceIndexer` with the
   file's content.
5. Indexer returns `Search.SourceItem` rows. IndexBuilder writes
   them to `<destinationDB>.db` opened via the matching
   `DatabaseDescriptor`.

No `switch source.id` ever runs inside the IndexBuilder. The binding
flows manifest → registry → indexer.

### 4.1 Per-DB dispatch

The composition root groups providers by `destinationDB`:

```swift
let groupedByDB: [Shared.Models.DatabaseDescriptor: [any Search.SourceProvider]] =
    Dictionary(grouping: registry.allEnabled, by: { $0.destinationDB })

for (descriptor, providers) in groupedByDB {
    let db = try await Search.Index(dbPath: descriptor.path, ...)
    for provider in providers {
        try await ingest(provider: provider, into: db)
    }
}
```

For the agreed names, this gives 7 DBs opened in parallel
(apple-documentation / hig / apple-archive / swift-evolution /
swift-documentation / apple-sample-code / swift-packages), and
`swift-documentation` is the only one receiving rows from more than
one logical source-id (swift-org + swift-book, distinguished by the
URL-prefix tag inside SwiftOrgStrategy).

---

## 5. Worked example: adding WWDC transcripts as a new source

Hypothetical new source [#58]. Demonstrates the 4-file PR claim.

### 5.1 The 4 files

```
Packages/Sources/WWDCSource/WWDC.Definition.swift       (new)
Packages/Sources/WWDCSource/WWDCTranscriptStrategy.swift (new)
Packages/Sources/CLI/CLIImpl+ProductionRegistry.swift   (1-line append)
docs/sources/wwdc/manifest.yaml                          (new)
```

Plus 1 line in `Packages/Package.swift` to declare the SPM target;
counted under "infrastructure" not "source code" because every SPM
target needs this and it's not editing an existing source.

### 5.2 `WWDC.Definition.swift` (illustrative)

```swift
import SearchModels
import SharedModels

extension Search {
    public enum WWDCSource {
        public static let provider: any Search.SourceProvider = Provider()

        private struct Provider: Search.SourceProvider {
            let definition = Search.Source(
                id: "wwdc",
                displayName: "WWDC Session Transcripts",
                searchQuality: 0.85,
                intentDefault: .reference
            )

            let destinationDB = Shared.Models.DatabaseDescriptor.wwdc  // new DB

            func fetchInfo() -> Search.FetchInfo { ... }
            func makeStrategy(env: Search.IndexEnvironment) -> any Search.Strategy { ... }
            func makeIndexer() -> any Search.SourceIndexer {
                WWDCTranscriptStrategy(/* deps */)
            }
        }
    }
}
```

### 5.3 `docs/sources/wwdc/manifest.yaml`

```yaml
sourceId: wwdc
displayName: WWDC Session Transcripts
description: |
  Searchable transcripts of WWDC sessions, fetched from
  developer.apple.com/videos/play/wwdc<year>/<id>/.

corpusFolder: wwdc
destinationDB: wwdc

fetcher:
  kind: apple-docs-api
  options:
    rootURL: https://developer.apple.com/videos/play/

indexer:
  fileGlobs:
    - sessions/**/*.json
  entryPoints:
    - sessions/index.json
  extractor: Search.WWDCTranscriptExtractor

searchProperties:
  searchQuality: 0.85
  intentDefault: reference
  rankWeight: 0.9

capabilities:
  searchers:
    - text
  operations:
    - read-by-uri
  metadata:
    hasMinPlatformVersion: true     # WWDC sessions are tagged by year + platform
    hasAvailabilityAttrs: false     # transcripts don't carry @available
```

### 5.4 Composition-root append (the one edit to existing code)

```swift
// CLIImpl+ProductionRegistry.swift
extension CLIImpl {
    static func makeProductionSourceRegistry() -> Search.SourceRegistry {
        Search.SourceRegistry(providers: [
            AppleDocs.provider,
            HIG.provider,
            AppleArchive.provider,
            SwiftEvolution.provider,
            SwiftOrg.provider,
            SampleCode.provider,
            Packages.provider,
            Search.WWDCSource.provider,   // ← the one line added
        ])
    }
}
```

That is the entire surface. No existing source's code is touched.
No `switch` is updated. No registry dictionary is keyed by string.

### 5.5 What the test for this PR proves

`Issue1033AllSourcesRoundtripTests` already iterates the production
registry. Adding the WWDC provider extends the sweep automatically:

- Pin 1 (per-source roundtrip): the test writes a fixture row tagged
  `wwdc`, queries it back, asserts the source-id roundtrips. Green.
- Pin 2 (cross-source query): the test writes one row per source
  with a shared term, queries, asserts every source appears in the
  result. Green (with the per-DB split, this becomes a fan-out
  query; the test's shape doesn't change).
- Pin 3 (per-source `--source` filter): the test asserts `--source
  wwdc` returns only wwdc rows. Green.
- Pin 4 (destinationDB exclusion): the test asserts each provider's
  indexer is in the dict for its own destinationDB, not in others'.
  Green.

A new test pinning the WWDC-specific manifest shape (file globs,
extractor type) ships in the same PR; the existing registry-iterated
pins remain unchanged.

---

## 6. Failure modes

Catalogue of what goes wrong + how it's caught.

### 6.1 Missing manifest.yaml

A new source target ships without `docs/sources/<id>/manifest.yaml`.
`cupertino doctor` fails on first run; `cupertino save` refuses to
index that source. Caught at PR time by a new CI check
(`check-source-manifests.sh`).

### 6.2 sourceId mismatch

The repo manifest declares `sourceId: foo` but the provider's
`definition.id` is `bar`. `cupertino doctor` fails:
`error: source 'bar' has manifest declaring 'foo'`.

### 6.3 corpusFolder mismatch

Manifest declares `corpusFolder: apple-docs` (old name) but the
provider's id is `apple-documentation` (new name). The indexer can't
find the corpus. Caught by `cupertino doctor` before any save.

### 6.4 fileGlobs match nothing

Manifest declares `fileGlobs: ['**/*.txt']` but corpus contains only
`.json` files. `cupertino save` logs `warn: source '<id>' matched 0
files` and proceeds. Test pins catch this for the canonical sources
(Issue1033 fixtures), and CI's "Query batteries smoke" job catches
production drift (its asserts include per-source non-empty result
sets for landmark queries).

### 6.5 Extractor type missing

Manifest declares `extractor: Search.NonExistentExtractor`. Caught at
compile time (the SPM target won't build). The extractor field is a
documentation aid; the actual binding is the
`provider.makeIndexer()` return type.

### 6.6 destinationDB references non-existent descriptor

Manifest declares `destinationDB: foo`. The provider's
`destinationDB` property is typed as `Shared.Models.DatabaseDescriptor`
(a Swift static), so this never compiles. Manifest field is a
human-readable cross-check, not the binding.

### 6.7 Runtime manifest.json missing inside a corpus folder

Indexer falls back to `fileGlobs` discovery + logs a warning. Source
still indexes, but `cupertino doctor` reports the corpus as
"unattributed" (snapshot date + upstream revision unknown).

### 6.8 viewSource URL prefix overlap

Two sources declare the same `viewSources[].urlPrefix`. Caught at
registry assembly time:
`fatal: viewSource urlPrefix '<x>' claimed by both '<a>' and '<b>'`.

---

## 7. Migration: bringing existing sources onto this contract

The per-source DB split epic (`per-source-db-split.md`) is the
implementation vehicle. Per-source manifests land alongside each
source's `destinationDB` flip. Order:

| Step | What changes | Why this order |
|------|--------------|----------------|
| 1 | Add `DatabaseDescriptor` statics for the 5 new DBs + rename samples/packages | Subsequent steps can reference them. |
| 2 | Add `CorpusManifest` model type to `SharedModels` | Manifest loader needs the type. |
| 3 | Add `docs/sources/<id>/manifest.yaml` for all existing sources | Provides the manifests the loader will read. |
| 4 | Add `Search.SourceProvider.corpusManifest` property (computed from the YAML at composition time) | Wires manifest into the registry. |
| 5 | One source at a time: flip `destinationDB` to its own DB; update IndexBuilder to honor the dispatch | Smallest step, suite green at each commit. |
| 6 | Migration shim: split the existing `search.db` bundle into the 5 per-source DBs once on `cupertino setup` upgrade | Existing users keep their bundle. |
| 7 | `cupertino setup` rewires to fetch per-DB bundle files | Bundle ships in new shape. |

Each step is reversible up through step 5. Step 6 is irreversible
once a user's local `~/.cupertino` is migrated; the migration is
gated behind a clear console prompt.

---

## 8. Open questions before implementation

- **YAML parser dependency.** SharedModels currently has no YAML
  dependency. Options: add Yams (the canonical Swift YAML lib, MIT,
  one Foundation-only dep), switch the manifests to JSON (loses
  comments, slightly less reviewable), or hand-roll a minimal YAML
  parser for the subset we need (8 keys, no anchors, no flow style).
  Recommend Yams; the dependency cost is acceptable for the spec's
  reviewability gain.
- **manifest.yaml vs manifest.json for the declared manifest.**
  YAML wins on reviewer ergonomics; JSON wins on dep simplicity.
  Open for user call.
- **Stronger compile-time binding.** The current proposal uses a YAML
  manifest as the spec but binds `destinationDB` + `corpusFolder` via
  Swift code (manifest field is human-readable cross-check). An
  alternative: code-gen a Swift extension from the YAML at build time
  so the manifest IS the binding. Defer to a follow-up if drift
  becomes a real problem; today the cross-check is sufficient and
  the build-time codegen adds maintenance surface.
- **CI check shape.** `check-source-manifests.sh` would walk
  `docs/sources/*/manifest.yaml`, validate against the JSON-schema
  equivalent, cross-check that every `sourceId` in YAML appears in
  the production registry (and vice versa), cross-check that every
  `corpusFolder` matches the source-id by convention. Lightweight
  shell + jq or yq; runs in <2s.

---

## References

- Companion implementation arc: `docs/design/per-source-db-split.md`
- Output-shape spec: `docs/design/per-db-schema-spec.md`
- Pluggability rule of record: `mihaela-agents/Rules/swift/gof-di-rules.md` §3 (Protocol seams + DI)
- Memory: `cupertino-per-source-db-names-agreed`, `feedback_sources_100pct_pluggable`, `cupertino_file_based_db_invariant`
- Tracking: per-source DB epic (this branch's PR)
