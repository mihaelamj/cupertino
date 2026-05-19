# Postmortem: `cupertino save` aborted on symlinked optional source dir, lost the apple-docs run's enrichment passes

| Field | Value |
|---|---|
| **Status** | settled |
| **Incident date** | 2026-05-18 |
| **Document created** | 2026-05-19 |
| **Last revised** | 2026-05-19 (settled after PR #788 fix + Issue779OptionalDirSymlinkTests landed) |
| **Tracking issue** | [#779](https://github.com/mihaelamj/cupertino/issues/779) |
| **Severity** | release-blocker (v1.2.0 ceremony was blocked) |
| **Companion docs** | [docs/audits/issue-779-reindex-crash-20260518.log](../audits/issue-779-reindex-crash-20260518.log); [docs/handoff/2026-05-18.md](../handoff/2026-05-18.md) |

---

## TL;DR

The pre-v1.2.0 reindex of `~/.cupertino-dev/search.db` crashed at the 11h15m mark, immediately after the apple-docs strategy persisted 351,495 rows. The proximate symptom was `Error: The file "swift-evolution" couldn't be opened.`; the actual cause was that `FileManager.contentsOfDirectory(at:)` (URL variant) does not follow a directory-symlink at the leaf URL, and the four optional source directories in the dev layout (`~/.cupertino-dev/{swift-evolution,swift-org,archive,hig}`) are all symlinks into `~/.cupertino/`. The apple-docs work persisted in the DB but was unusable because the three enrichment passes (`registerFrameworkSynonyms`, `applyAppleStaticConstraints`, `propagateConstraintsFromParents`) run after the source-strategy loop and never fired. Fix is a one-line `url.resolvingSymlinksInPath()` in `Indexer.DocsService.optionalDir`, with a per-strategy `do/catch` in `Search.IndexBuilder.buildIndex` as defense in depth.

---

## 1. Summary

On 2026-05-18 at 06:20 Zagreb, a Claude session launched `cupertino save --docs --docs-dir ~/.cupertino/docs --base-dir ~/.cupertino-dev --yes` via `~/bin/reindex-cupertino-dev.sh`. The save proceeded through the apple-docs strategy for 11h15m, indexing 351,495 documentation files across 398 frameworks and writing them into `~/.cupertino-dev/search.db`. At 17:35 Zagreb, immediately after the apple-docs scan summary line, the process exited non-zero with `Error: The file "swift-evolution" couldn't be opened.`. The three enrichment passes never ran because they live after the source-strategy `for`-loop in `Search.IndexBuilder.buildIndex` and the loop aborted on the first strategy throw.

The next morning a second save was launched manually. Per `Indexer.DocsService.run`, its first action was to `removeItem(at: searchDBURL)`, wiping the 11h-old apple-docs DB. The second save was killed two minutes in once it became clear it would hit the same crash 11h later.

The initial investigation in the comments thread of #779 misdiagnosed the cause twice (first as `NSFileReadNoSuchFileError` code 260, then as `EMFILE` / file-descriptor leak), based on the bare Cocoa error string `The file "X" couldn't be opened.` and the absence of a "because…" suffix. Both diagnoses fit narratives. Neither fit the evidence. A reproduction in a fresh single-FD Swift process surfaced the actual underlying error: `NSPOSIXErrorDomain` code 20, `ENOTDIR`. From there the root cause traced quickly to the documented but easy-to-miss divergence between `FileManager.contentsOfDirectory(at:)` (URL variant, does not follow leaf directory-symlinks) and `FileManager.contentsOfDirectory(atPath:)` (String variant, does).

---

## 2. Impact

- **Compute lost**: ~11h15m of single-machine wall time on the Studio. The apple-docs SQLite writes had been WAL-checkpointed before the crash, so the 351,495 rows survived in `search.db`, but they were unusable without the three enrichment passes (synonyms, static constraints, parent propagation). The DB was overwritten the next day by the second save's `removeItem(at:)` call.
- **Release impact**: v1.2.0 ceremony blocked. The bundle build depends on a fully-enriched DB.
- **User-facing impact**: zero. Typical brew users (`brew install mihaelamj/tap/cupertino` + `cupertino setup`) get the v1.0.2 bundle which is unaffected; their `~/.cupertino/` layout has no symlinks and never triggers this code path.
- **Bundles affected**: none shipped. The v1.0.x bundles do not carry this defect because they were built with a different layout. The defect exists in develop's `Indexer.DocsService.optionalDir` since the dev/brew split was introduced, but only surfaces when the optional source dirs are symlinks.
- **Brew DB safety**: `~/.cupertino/search.db` was never touched, verified before and after by the launcher script's pre-flight check.

---

## 3. Timeline

All times Zagreb local (CEST, +0200). Source: cupertino's `docs/audits/issue-779-reindex-crash-20260518.log`, Claude session transcripts `58760905-…` and `20426929-…`, `~/.cupertino-dev/.reindex.pid`, GitHub issue #779.

| Time | Event |
|---|---|
| 2026-05-18 05:41 | Handoff doc `docs/handoff/2026-05-18.md` committed (`cbee6ea`); names the pending 11h reindex |
| 2026-05-18 05:47 | Claude session `58760905` wrote `~/bin/reindex-cupertino-dev.sh` (defensive launcher); explicitly advised "don't kick from inside any Claude" |
| 2026-05-18 06:20:44 | Same Claude session ran `~/bin/reindex-cupertino-dev.sh` via Bash; `cupertino save` started as PID 35243 |
| 2026-05-18 06:20:55 | `caffeinate -i -w 35243` started (PID 35288) to keep the Mac awake during the save |
| 2026-05-18 06:38 | Handoff doc updated (`a4e9633`) to reflect the in-flight save |
| 2026-05-18 17:35 | Apple-docs strategy finished (351,495 indexed, 14 skipped); SwiftEvolution strategy threw NSCocoa 256; process exited non-zero. Wall time: 11h15m |
| 2026-05-18 evening | Issue #779 filed; initial diagnosis attributed cause to NSCocoa 260 (`NSFileReadNoSuchFileError`) |
| 2026-05-19 01:54 | Second `cupertino save` launched manually as PID 17808. First action: `removeItem(at: searchDBURL)`, wiping the 11h-old apple-docs DB |
| 2026-05-19 02:00 | User killed PID 17808 before it wasted another 11h |
| 2026-05-19 02:13 | Reproduction in 1-FD fresh Swift process confirmed `NSUnderlyingError = NSPOSIXErrorDomain code 20 (ENOTDIR)`. EMFILE / fd-leak hypothesis retracted |
| 2026-05-19 02:18 | Three-variant reproduction confirmed `contentsOfDirectory(at: URL)` fails on symlinked leaf; `resolvingSymlinksInPath()` and the String-based API both work |
| 2026-05-19 02:30 | Provenance for the original launch traced to Claude transcript `58760905`; exact argv extracted |
| 2026-05-19 06:08 | One-line fix lands in `Indexer.DocsService.optionalDir` (PR #788, commit `face50f`); defense-in-depth `do/catch` lands in `Search.IndexBuilder.buildIndex` in the same commit |
| 2026-05-19 ~06:30 | Integration test `Issue779OptionalDirSymlinkTests` lands (PR for this commit), pinning both the positive case (post-fix symlink-following) and the negative ENOTDIR sentinel |

---

## 4. Detection

Process exit-non-zero, surfaced by `tail`ing the log file the next morning. No CI. No external monitoring. The save was a single-developer manual job kicked off detached with `nohup`; the only signals available were (a) `kill -0 $PID` and (b) the log contents.

Detection lagged the failure by hours (overnight: crash at 17:35, surfaced when the user checked the log the next day) because no exit-status notification was wired up. The `~/bin/reindex-cupertino-dev.sh` launcher gives a "Done when log contains '✅ Search index built successfully'" hint but does not actively notify on failure. That gap is its own follow-up.

The save-log diagnostic work landed in PRs [#780](https://github.com/mihaelamj/cupertino/pull/780), [#781](https://github.com/mihaelamj/cupertino/pull/781), [#782](https://github.com/mihaelamj/cupertino/pull/782) on 2026-05-19 (per-line ISO 8601 timestamps + startup invocation banner) and reduces the lag for the next incident of this class by making the failure context self-contained in the log.

---

## 5. Root Cause

**Trigger**: `cupertino save --docs --base-dir ~/.cupertino-dev` with the four optional source directories (`swift-evolution`, `swift-org`, `archive`, `hig`) left as symlinks under `~/.cupertino-dev/` pointing into `~/.cupertino/`. This is the standard dev layout established by `~/bin/reindex-cupertino-dev.sh` and the convention in `docs/handoff/2026-05-18.md`.

**Root cause**: `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)`, the URL-taking variant, does not follow a directory-symlink at the leaf URL. It runs enumeration against the symlink inode itself, which has type `NSFileTypeSymbolicLink`. The kernel returns `ENOTDIR` (POSIX 20). Foundation wraps it as `NSCocoaErrorDomain` code 256 (`NSFileReadUnknownError`) with localized description `The file "X" couldn't be opened.` (no "because…" suffix, because there is no specific Cocoa code mapping for `ENOTDIR` in the read-error family).

The throw originates at `Search.Strategies.SwiftEvolution.getProposalFiles(from:)` in `Packages/Sources/Search/Strategies/Search.Strategies.SwiftEvolution.swift`. Three other strategies share the same code shape and would have failed identically had they been first in the strategy order: `Search.SwiftOrgStrategy`, `Search.AppleArchiveStrategy`, `Search.HIGStrategy`.

**Contributing factors:**

1. `FileManager.fileExists(atPath:)` DOES follow symlinks (it `stat()`s, not `lstat()`s). It is used both at startup by `Indexer.DocsService.optionalDir` and inside each strategy as the "do I have a local corpus?" guard. Both guards passed at the relevant points in time, masking the divergence in symlink-handling semantics until the actual `contentsOfDirectory(at:)` call ran.

2. `Search.IndexBuilder.buildIndex` calls strategies in a `for`-loop with no per-strategy `do/catch`. The three enrichment passes (`registerFrameworkSynonyms`, `applyAppleStaticConstraints`, `propagateConstraintsFromParents`) live after the loop. One strategy throwing strands the rest.

3. The apple-docs strategy uses a different code path that was not affected, because the launcher script passes `--docs-dir /Users/mmj/.cupertino/docs` explicitly. That sidesteps the base-dir-relative symlink path entirely; the strategy receives a URL pointing at the real `~/.cupertino/docs` directly.

4. The bare error string (`"The file 'X' couldn't be opened."` with no "because…") is consistent with several different POSIX errnos (EMFILE, ENOTDIR, EIO, EACCES with the unusual mapping). Without an `NSUnderlyingError` inspection, the diagnosis is ambiguous.

**5-Whys:**

1. Why did save abort? Because SwiftEvolution strategy threw `NSCocoa 256`.
2. Why did SwiftEvolution throw? Because `FileManager.contentsOfDirectory(at:)` got `ENOTDIR` on the symlink URL.
3. Why did `contentsOfDirectory(at:)` get `ENOTDIR`? Because the URL-taking variant of that API operates on the inode at the literal URL (the symlink), not on the resolved-symlink path. The String-taking sibling does follow symlinks; the URL one doesn't.
4. Why was the failure latent until that point? Because `fileExists(atPath:)`, used at startup and as the strategy guard, follows symlinks. That masked the API divergence.
5. Why did losing one strategy abort 11h of apple-docs work? Because the strategies run sequentially with no per-strategy `do/catch`, and the enrichment passes live after the loop.

---

## 6. Resolution

### Mitigation (short-term)

- Killed the second save (PID 17808) before another 11h was lost to the same bug.
- Documented the symptom and the actual underlying error in #779 comments. Retracted the EMFILE diagnosis.

### Fix (long-term)

Two changes, neither merged at the time this postmortem was drafted:

1. **One-line fix** in `Indexer.DocsService.optionalDir` (`Packages/Sources/Indexer/Indexer.DocsService.swift`): when the optional directory exists, return `url.resolvingSymlinksInPath()` instead of `url` raw. This resolves the four optional-source symlinks at the composition root before they reach any strategy. Strategies stay untouched. `resolvingSymlinksInPath()` is a no-op for non-symlink URLs, so the change is safe for the typical brew-bundle layout.

2. **Defense in depth** in `Search.IndexBuilder.buildIndex` (`Packages/Sources/Search/Search.IndexBuilder.swift`): wrap each strategy call in `do/catch`, record the throw as a skipped `IndexStats` with a `skipReason`, continue the loop. One strategy throwing should not strand the enrichment passes. Independent of fix 1; protects against the next undiscovered strategy bug.

### Verification

- Pre-fix reproduction at `/tmp/repro.swift` (recorded in #779 comments): `contentsOfDirectory(at: URL(fileURLWithPath: "/Users/mmj/.cupertino-dev/swift-evolution"))` fails with `ENOTDIR`. After applying `.resolvingSymlinksInPath()`, the same call returns 483 entries.
- Same reproduction across all four optional source dirs confirms the bug is path-shape-invariant.
- Integration test (to be added under `Packages/Tests/`): fixture corpus with a symlinked optional dir, assert post-fix the strategy indexes the symlinked content. The test fixture MUST symlink the optional dir, not just create it: a naive "directory exists" test passes against the unfixed code.

---

## 7. Follow-ups

### 7.1 Fixed by this postmortem

- **PR [#788](https://github.com/mihaelamj/cupertino/pull/788)** (commit `face50f`, merged 2026-05-19): `Indexer.DocsService.optionalDir` returns `url.resolvingSymlinksInPath()` instead of `url`; `Search.IndexBuilder.buildIndex` wraps each strategy call in `do/catch` so a single strategy failure cannot strand the post-loop enrichment passes. End-to-end validation: ran `cupertino save --docs` against the 10% mini-corpus (41,569 doc symlinks + leaf symlinks for the four optional sources) on the fix-bearing binary; all four optional sources indexed (swift-evolution 483, swift-org 115, archive 368, hig 173), all three enrichment passes ran (`framework_aliases` has 22 synonym rows, `applyAppleStaticConstraints` logged, `propagateConstraintsFromParents` logged), `✅ Search index built successfully` in 11m 18s with zero errors.
- **PR (this commit)**: `Issue779OptionalDirSymlinkTests` integration test under `Packages/Tests/SearchTests/` covers both the positive case (post-fix path: `SwiftEvolutionStrategy` with a URL through `resolvingSymlinksInPath()` indexes content cleanly from a leaf directory-symlink fixture) and the negative ENOTDIR sentinel (pre-fix shape: same strategy with the raw symlink URL throws NSCocoa 256 with `NSPOSIXErrorDomain` code 20 underlying). Pins the bug as a regression sentinel: any future change that breaks `resolvingSymlinksInPath()` at the composition root surfaces in the negative test.

### 7.2 Filed for later

| Item | Issue | Reason |
|---|---|---|
| Save-log diagnostics (per-line ISO 8601, startup invocation banner) | [#780](https://github.com/mihaelamj/cupertino/issues/780), [#781](https://github.com/mihaelamj/cupertino/issues/781) | Already merged via [#782](https://github.com/mihaelamj/cupertino/pull/782) on 2026-05-19; next incident's log will be self-describing |
| Audit other URL-variant FileManager call sites in the codebase | Filed as [#786](https://github.com/mihaelamj/cupertino/issues/786); shipped via PR [#787](https://github.com/mihaelamj/cupertino/pull/787) + a follow-up commit catching a third call site (`PackageIndexer.walkDirectoryForFiles` enumerator) that c1 spotted during PR critic. Total: 7 sites migrated to `Shared.Utils.FileSystem.contentsOfDirectory` / `.enumerator` wrappers (Option C centralised approach). |
| Active failure notification from the launcher (`say` / desktop notification on exit-non-zero, not just on success) | Still open; not filed as an issue yet. Detection lagged the 17:35 failure by ~12h because the launcher only documents the success signal. |
| Integration test: symlinked optional source dir | Shipped: `Issue779OptionalDirSymlinkTests` (this commit). Positive + negative sentinel as described in §7.1. |
| Drop redundant `packages` + `package_dependencies` tables from `search.db` | Filed as [#789](https://github.com/mihaelamj/cupertino/issues/789); shipped via PR [#790](https://github.com/mihaelamj/cupertino/pull/790). Schema 17 → 18 with `DROP TABLE` migration. Surfaced during the #779 mini-corpus validation when the post-crash DB showed `packages` row count of 0 despite a successful strategy run. |
| `CREATE TABLE`-without-writer lint rule | Filed as [#791](https://github.com/mihaelamj/cupertino/issues/791); mechanical floor for the class-of-bug that #789 surfaced. Not yet routed. |
| Post-index search-results comparator (candidate `search.db` vs brew reference) | Filed as [#792](https://github.com/mihaelamj/cupertino/issues/792); broader regression catcher (the "would have caught #779, #786, #789 earlier" tool). Not yet routed. |

### 7.3 Where we got lucky

- The apple-docs SQLite writes had been WAL-checkpointed before the crash. The 351,495 rows survived in the DB file for the ~8h between crash and overwrite. Had the crash hit mid-checkpoint, the WAL would have been replayed but the corruption surface would have been larger.
- The brew DB at `~/.cupertino/search.db` was never touched. The launcher's pre-flight check explicitly verifies its mtime and size before and after. Without that guard, the dev binary's default base-dir behavior (pre-PR-#161) could have written to the brew location.
- The user killed PID 17808 (the second save) manually two minutes in. Had it run to completion under the EMFILE-hypothesis path, it would have failed identically 11h later, and the next diagnosis pass would have been distorted by yet another wrong root cause being "confirmed" by a repeat failure.
- The reproduction was possible in a 1-FD fresh Swift process. That ruled out EMFILE definitively in seconds. Had the failure been state-dependent on the apple-docs phase (e.g., a real fd leak), root cause would have taken much longer to nail down.

### 7.4 Lessons

1. `FileManager.contentsOfDirectory(at:)` and `contentsOfDirectory(atPath:)` have different symlink semantics. The URL variant does not follow leaf directory-symlinks; the String variant does. `fileExists(atPath:)` follows symlinks. Don't assume "if `fileExists` returns true, `contentsOfDirectory(at:)` will succeed." When passing user-controlled URLs to URL-variant Foundation APIs, resolve symlinks at the composition root.

2. Pipelines with post-loop enrichment passes should have per-stage `do/catch`. Five lines of code prevent disproportionate work loss when any single stage fails.

3. Reproducing in a fresh process should be the first investigative step for any "long-running job crashed at a specific point" bug. Initial-diagnosis confidence (EMFILE here, mtime-touch in earlier postmortems) felt high but was not supported by reproduction. The repro takes minutes; the wrong hypothesis costs hours.

4. When a Cocoa error has no "because…" suffix in its localized description, inspect `userInfo[NSUnderlyingErrorKey]` for the POSIX errno. NSCocoa code 256 is the catch-all wrapper; the underlying errno is what tells you what actually failed.

---

## 8. Background / Architecture

The cupertino save pipeline (`Search.IndexBuilder.buildIndex`) is a sequential strategy loop followed by enrichment passes:

```
AppleDocsStrategy
  → SwiftEvolutionStrategy (THREW HERE)
  → SwiftOrgStrategy        ┐
  → AppleArchiveStrategy    │  never ran
  → HIGStrategy             │
  → SampleCodeStrategy      │
  → SwiftPackagesStrategy   ┘
[loop end]
  → registerFrameworkSynonyms          ┐
  → applyAppleStaticConstraints        │  never ran
  → propagateConstraintsFromParents    ┘
```

The dev layout (`~/.cupertino-dev/`) is intentionally a symlink farm into the brew layout (`~/.cupertino/`):

```
~/.cupertino-dev/
├── search.db                 (real file, dev output)
├── apple-constraints.json    (real file, dev input)
├── archive          → ~/.cupertino/archive          (symlink)
├── hig              → ~/.cupertino/hig              (symlink)
├── swift-evolution  → ~/.cupertino/swift-evolution  (symlink)
└── swift-org        → ~/.cupertino/swift-org        (symlink)
```

This layout exists so dev work shares the 2.5 GB+ brew corpus without duplicating disk usage. The launcher script `~/bin/reindex-cupertino-dev.sh` enforces it by passing `--base-dir ~/.cupertino-dev` and relying on `Indexer.DocsService.run` to resolve the optional source dirs as `baseDir.appendingPathComponent(...)` (which lands on the symlinks). The apple-docs corpus is passed explicitly via `--docs-dir ~/.cupertino/docs`, sidestepping the base-dir-relative symlink path; that is why the apple-docs strategy worked.

---

## 9. References

### Internal

- [docs/audits/issue-779-reindex-crash-20260518.log](../audits/issue-779-reindex-crash-20260518.log): full 3,571-line crash log from PID 35243
- [docs/handoff/2026-05-18.md](../handoff/2026-05-18.md): contemporaneous handoff doc, names PID 35243 and the launcher
- [docs/PRINCIPLES.md](../PRINCIPLES.md): correctness-first principle that motivates the per-strategy `do/catch` fix

### External

- GitHub issue [#779](https://github.com/mihaelamj/cupertino/issues/779): tracking issue, full investigation thread
- GitHub PRs [#780](https://github.com/mihaelamj/cupertino/pull/780), [#781](https://github.com/mihaelamj/cupertino/pull/781), [#782](https://github.com/mihaelamj/cupertino/pull/782): save-log diagnostics that reduce detection lag for the next incident of this class
- Apple Foundation: `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` and `FileManager.contentsOfDirectory(atPath:)` have differing symlink-handling semantics. No canonical Apple documentation flags this; behavior empirically verified by reproduction.
- Postmortem template adapted from the consensus across Google SRE, Amazon COE, Meta SEV, Microsoft Azure PIR, GitLab handbook RCA, Stripe, and Cloudflare published postmortems. Template at [`docs/postmortems/_TEMPLATE.md`](_TEMPLATE.md), canonical source at `mihaela-agents/Rules/universal/templates/postmortem.md`.
