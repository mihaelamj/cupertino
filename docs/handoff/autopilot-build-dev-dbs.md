# Autopilot: Build packages.db + samples.db into `~/.cupertino-dev/`

Step-by-step recipe for an AI agent to populate the two non-search DBs
from brew's read-only source corpora, then inspect them thoroughly,
without touching the brew-installed user-production environment.

This doc is the canonical instruction for the recurring "I need a v1.2.0+
samples.db / packages.db on this Mac for testing, but I cannot disturb
the brew binary's working copies" task. The trigger phrase is "build
dev DBs" or "autopilot dev DBs".

## Known gaps (read first)

The doc-recipe runs end-to-end and produces v1.2.0-schema DBs, but
three known gaps are open against the packages.db indexer + this
doc's probes. Read these before interpreting the inspection output:

- **#860 — `apple_imports_json` near-zero coverage on packages.db.**
  Indexer joins on the package's own Swift module name, not on
  parsed `import X` statements. Expect `apple_imports_json` populated
  for ~1/183 packages until that's fixed. The `--apple-imports` CLI +
  MCP filter therefore narrows to zero against real data even though
  the wiring is correct.
- **#861 — `swift_tools_version` never populated on packages.db.**
  v3 migration adds the column + an index; the indexer never writes
  to it. Expect 0/183 coverage.
- **#862 — packages-side HTTP-error poison probe false-positives.**
  Pre-#862 fix, the probe returns ~20-30 hits on a healthy corpus
  because real HTTP library source files mention "404 Not Found" in
  code comments. Use the **tightened HTML-shape probe** below, not
  the substring probe.

**Scope guardrail for all three issues**: packages.db's indexer +
this doc only. **Do not touch `Search.Index` / search.db creation
code as part of any fix**: search.db's enrichment passes work
correctly (24,827 `doc_symbols.generic_constraints` rows populated
on a fresh v1.2.0 search.db today; verified). search.db lives in a
different actor, different schema, different migration path, and is
not in scope for any packages.db-side fix.

## Goal

After this recipe finishes, on the operator's Mac:

1. `~/.cupertino-dev/packages.db` exists, schema = packages.db v4,
   populated with rows from `~/.cupertino/packages/` (read-only input).
2. `~/.cupertino-dev/samples.db` exists, schema = samples.db v4,
   populated with rows from `~/.cupertino/sample-code/` (read-only
   input).
3. Both DBs have their v1.2.0 enrichment columns populated where the
   AppleConstraints + AppleImports passes apply (`generic_constraints`
   on samples.db `file_symbols` + packages.db `package_symbols`,
   `apple_imports_json` on packages.db `package_metadata`).
4. The brew install at `~/.cupertino/` is byte-identical to its
   pre-run state.

## Hard constraints (NEVER violate)

1. **No writes to `~/.cupertino/*`.** Read-only `SELECT` / `PRAGMA` /
   filesystem reads against the brew tree are fine. Any `cupertino`
   subcommand that writes (`save`, `fetch`, `setup`, `migrate`) MUST
   target `~/.cupertino-dev/` exclusively. Mechanically: pass
   `--base-dir ~/.cupertino-dev` AND verify the binary you're invoking
   has `cupertino.config.json` with `baseDirectory=~/.cupertino-dev`
   next to it (the release build via `make build-release` ships this
   automatically; raw `swift build` does not).
2. **No `cupertino setup` / `cupertino fetch`.** Those re-download
   bundles from GitHub Releases. We want to use the local brew corpora
   as input, not redownload.
3. **No tag, no GH release, no Homebrew formula bump.** Build + inspect
   only. Anything ceremonial is the operator's.
4. **No `--clear` / `--force` on the brew tree.** Both flags are fine
   against the dev tree but never run them against `~/.cupertino/`.
5. **`feedback_never_touch_brew_db` is the hard floor.** When in doubt,
   stop and ask.

## Pre-flight (60 seconds)

Run each check; abort if any fails.

```bash
# 1. Confirm brew corpora are present + readable.
test -d ~/.cupertino/packages   || { echo "FAIL: brew packages tree missing"; exit 1; }
test -d ~/.cupertino/sample-code || { echo "FAIL: brew sample-code tree missing"; exit 1; }

# 2. Count inputs (sanity, not equality).
find ~/.cupertino/packages -mindepth 2 -maxdepth 2 -type d | wc -l   # expect ~150-200 owner/repo
ls ~/.cupertino/sample-code/*.zip | wc -l                            # expect ~500-700 zips

# 3. Confirm dev sandbox exists.
test -d ~/.cupertino-dev || mkdir -p ~/.cupertino-dev

# 4. Confirm apple-constraints.json is on disk for the enrichment passes.
#    Without it, the passes silently no-op (generic_constraints + apple_imports_json stay NULL).
test -f ~/.cupertino-dev/apple-constraints.json || \
  { echo "WARN: apple-constraints.json missing; enrichment passes will no-op."; }

# 5. Build the release binary so its bundled config isolates writes.
cd /Volumes/Code/DeveloperExt/public/cupertino/Packages   # or the local repo path
make build-release

# 6. Verify the bundled config pins baseDirectory=~/.cupertino-dev.
cat Packages/.build/release/cupertino.config.json
# Expected: {"baseDirectory":"~/.cupertino-dev"} or absolute equivalent.
```

## Build commands

Both saves are long-running (packages ~2 min, samples ~5-15 min on a
~500-zip corpus). Run them as background processes with logs you can
tail, in this order (packages first, samples second — they don't
conflict but sequential keeps logs readable).

### Packages

```bash
BIN=/Volumes/Code/DeveloperExt/public/cupertino/Packages/.build/release/cupertino
TS=$(date '+%Y%m%d-%H%M%S')
LOG=~/.cupertino-dev/save-packages-${TS}.log

nohup "$BIN" save --packages \
  --packages-dir ~/.cupertino/packages \
  --base-dir ~/.cupertino-dev \
  --yes >"$LOG" 2>&1 &
echo $! > /tmp/cupertino-save-packages.pid

tail -f "$LOG"     # ALWAYS show this in the same response per feedback_tail_cmd_on_start
```

Expected log shape:

```
🚀 ... save --packages --packages-dir /Users/<user>/.cupertino/packages --base-dir /Users/<user>/.cupertino-dev --yes
📍 binary:  ...
🔨 Indexing packages from /Users/<user>/.cupertino/packages into /Users/<user>/.cupertino-dev/packages.db
📊 1/183 — <owner>/<repo>
📊 10/183 — <owner>/<repo>
...
📊 180/183 — <owner>/<repo>
[enrichment/PackagesAppleConstraints] affected=N skipped=M (Tms)
[enrichment/PackagesAppleImports] affected=N skipped=M (Tms)
✅ Packages index built: <N> packages
```

### Samples

```bash
BIN=/Volumes/Code/DeveloperExt/public/cupertino/Packages/.build/release/cupertino
TS=$(date '+%Y%m%d-%H%M%S')
LOG=~/.cupertino-dev/save-samples-${TS}.log

nohup "$BIN" save --samples \
  --samples-dir ~/.cupertino/sample-code \
  --base-dir ~/.cupertino-dev \
  --yes >"$LOG" 2>&1 &
echo $! > /tmp/cupertino-save-samples.pid

tail -f "$LOG"     # ALWAYS show this in the same response per feedback_tail_cmd_on_start
```

Expected log shape similar, plus an `[enrichment/SamplesAppleConstraints]`
line near the end.

### Wait pattern

Don't poll in a sleep loop. Use the harness's background-process
notification: kick off via `nohup ... &` with `run_in_background: true`
on the Bash call so the harness notifies you when the PID exits, then
re-enter the recipe at the inspection step. Alternatively for a busy
shell, `wait $PID` or a Monitor task watching the log for the trailing
`✅` line works.

## Deep inspection (the load-bearing step)

Both DBs must pass every probe below. A FAIL means the build is bad
and should be reported, not papered over.

### Shared structural probes

```bash
for db in ~/.cupertino-dev/packages.db ~/.cupertino-dev/samples.db; do
  echo "=== $db ==="
  sqlite3 -readonly "$db" "PRAGMA user_version; PRAGMA integrity_check; PRAGMA journal_mode; PRAGMA synchronous;"
done
```

Expected:
- `packages.db`: `user_version = 4`, `integrity_check = ok`,
  `journal_mode = wal`, `synchronous = 1` (NORMAL).
- `samples.db`: `user_version = 4`, `integrity_check = ok`,
  `journal_mode = wal`, `synchronous = 1` (NORMAL).

### packages.db row counts + new-column coverage

```bash
DB=~/.cupertino-dev/packages.db
sqlite3 -readonly "$DB" <<'SQL'
SELECT 'package_metadata: ' || COUNT(*) FROM package_metadata;
SELECT 'package_files:    ' || COUNT(*) FROM package_files;
SELECT 'package_symbols:  ' || COUNT(*) FROM package_symbols;
SELECT 'metadata with apple_imports_json: '
       || COUNT(*) FROM package_metadata
       WHERE apple_imports_json IS NOT NULL AND apple_imports_json != '[]';
SELECT 'symbols with generic_constraints: '
       || COUNT(*) FROM package_symbols
       WHERE generic_constraints IS NOT NULL AND generic_constraints != '';
SELECT 'metadata with swift_tools_version: '
       || COUNT(*) FROM package_metadata
       WHERE swift_tools_version IS NOT NULL AND swift_tools_version != '';
SELECT '-- sample apple_imports_json rows --';
SELECT owner || '/' || repo || ' = ' || apple_imports_json
       FROM package_metadata
       WHERE apple_imports_json LIKE '%swiftui%' LIMIT 5;
SELECT '-- sample generic_constraints rows --';
SELECT ps.name || ' (' || pm.owner || '/' || pm.repo || '): ' || ps.generic_constraints
       FROM package_symbols ps
       JOIN package_files pf ON ps.file_id = pf.id
       JOIN package_metadata pm ON pf.package_id = pm.id
       WHERE ps.generic_constraints IS NOT NULL AND ps.generic_constraints != ''
       LIMIT 5;
SQL
```

Expected:
- `package_metadata` ≈ count of owner/repo input dirs (typical: ~180).
- `package_files` typically 10x–100x metadata count (typical: ~20,000).
- `package_symbols` typically 10x–100x files (typical: ~1.4M on a 183-package corpus).
- **apple_imports_json coverage: see #860.** Until #860 is fixed,
  expect this to be near-zero (~1/183). Don't surface as a fresh
  finding; the gap is tracked. Once #860 is fixed, expected coverage
  jumps to 50+/183 (SwiftUI-importing packages alone clear that).
- **generic_constraints coverage: 100,000+ rows expected.** The
  AppleConstraintsPass works correctly; non-zero confirms enrichment
  ran. Zero means apple-constraints.json was missing — check the
  pre-flight step 4.
- **swift_tools_version coverage: see #861.** Expect 0/183 until
  #861 lands.
- Sample rows: human-readable owner/repo + module list. Look at
  shape (does it parse as JSON? are the values lowercased? are the
  generic_constraints comma-separated tokens?), not just count.

### samples.db row counts + new-column coverage

```bash
DB=~/.cupertino-dev/samples.db
sqlite3 -readonly "$DB" <<'SQL'
SELECT 'projects:    ' || COUNT(*) FROM projects;
SELECT 'files:       ' || COUNT(*) FROM files;
SELECT 'file_symbols: ' || COUNT(*) FROM file_symbols;
SELECT 'symbols with generic_constraints: '
       || COUNT(*) FROM file_symbols
       WHERE generic_constraints IS NOT NULL AND generic_constraints != '';
SELECT '-- sample generic_constraints rows --';
SELECT s.name || ' (' || s.kind || '): ' || s.generic_constraints
       FROM file_symbols s
       WHERE s.generic_constraints IS NOT NULL AND s.generic_constraints != ''
       LIMIT 5;
SQL
```

Expected:
- `projects` ≈ count of input zips.
- `files` typically 10x-100x projects.
- `file_symbols` typically 10x-100x files.
- generic_constraints coverage non-zero (else AppleConstraintsPass
  didn't run).

### FTS sanity

```bash
sqlite3 -readonly ~/.cupertino-dev/packages.db \
  "SELECT title, owner || '/' || repo FROM package_files_fts WHERE package_files_fts MATCH '\"Logger\"' ORDER BY bm25(package_files_fts) LIMIT 3;"
sqlite3 -readonly ~/.cupertino-dev/samples.db \
  "SELECT filename, project_id FROM files_fts WHERE files_fts MATCH '\"View\"' LIMIT 3;"
```

Expected: 3 sensible rows back from each query.

### No-poison probes

**What this protects against:** the package-fetcher accidentally
landing an HTML error page (404, Cloudflare challenge, GitHub rate
limit screen) into the source corpus instead of real .swift / .md
content. The shape we catch is "row content opens with HTML
markup", not "row content mentions an HTTP error string anywhere"
— the latter false-positives on legitimate HTTP library source
(swift-http-types, swift-nio, soto's S3 service all carry the
string in comments). See #862 for the rationale.

```bash
# packages: kind=source file whose content OPENS with HTML at byte 0.
# - kind=source filters out .md fixtures and benchmark inputs that
#   legitimately mention <html> in test data.
# - LTRIM + first-N-bytes match catches "the entire file is an HTML
#   error page", not "this Swift file embeds an HTML literal in a
#   string at line 7".
# This shape was tightened twice during the v1.2.0 spot-check (#862);
# do NOT loosen it.
sqlite3 -readonly ~/.cupertino-dev/packages.db <<'SQL'
SELECT 'pkg html-poison: ' || COUNT(*)
  FROM package_files pf
  JOIN package_files_fts fts ON pf.id = fts.rowid
  WHERE pf.kind = 'source'
    AND (SUBSTR(LTRIM(fts.content), 1, 15) LIKE '<!doctype html%' COLLATE NOCASE
      OR SUBSTR(LTRIM(fts.content), 1, 6)  LIKE '<html%' COLLATE NOCASE);
SQL

# samples: empty-content rows are the failure mode that matters here
sqlite3 -readonly ~/.cupertino-dev/samples.db \
  "SELECT 'sam empty-content: ' || COUNT(*) FROM files WHERE content IS NULL OR LENGTH(content) = 0;"
```

To prove the probe still trips on actual poison (one-off sanity, not
part of every run): inject a synthetic poison row into a temporary
copy of packages.db and re-run the probe; expect 1.

```bash
cp ~/.cupertino-dev/packages.db /tmp/poison-probe-test.db
sqlite3 /tmp/poison-probe-test.db <<'SQL'
INSERT INTO package_metadata (owner, repo, url, fetched_at, is_apple_official)
  VALUES ('synthetic', 'poison-test', 'https://test', 0, 0);
INSERT INTO package_files (package_id, relpath, kind, module, size_bytes, indexed_at)
  VALUES ((SELECT id FROM package_metadata WHERE owner='synthetic'),
          'poison.swift', 'source', 'Poison', 100, 0);
INSERT INTO package_files_fts
       (package_id, owner, repo, module, relpath, kind, title, content, symbols)
  VALUES ((SELECT id FROM package_metadata WHERE owner='synthetic'),
          'synthetic', 'poison-test', 'Poison', 'poison.swift', 'source',
          'poison.swift',
          '<!doctype html><html><head><title>404 Not Found</title></head></html>',
          '');
SQL
# Re-run the probe against /tmp/poison-probe-test.db → expect 1.
rm /tmp/poison-probe-test.db
```

Expected: each returns `0`. Any non-zero is a bug — surface it,
don't paper over.

**Do NOT use** the older substring-only probe (`content MATCH
'"404 Not Found"' OR content MATCH '"403 Forbidden"'`) — that one
returns ~20–30 false-positives on a healthy 183-package corpus
because real HTTP libraries (`apple/swift-http-types`,
`apple/swift-nio`, `soto-project/soto`) carry those strings in
legitimate source code. The HTML-shape probe above is the correct
shape for packages.db.

### End-to-end filter smoke (the load-bearing user-facing check)

```bash
BIN=/Volumes/Code/DeveloperExt/public/cupertino/Packages/.build/release/cupertino

# 1. CLI: --apple-imports SwiftUI restricts to packages that import SwiftUI.
#    Pre-#860 fix: expect EMPTY result list (the wiring is correct,
#    the data isn't populated). Post-#860 fix: non-empty list, every
#    row from a SwiftUI-importing package.
"$BIN" search --packages-db ~/.cupertino-dev/packages.db \
              --source packages \
              --apple-imports SwiftUI \
              "View" --limit 5

# 2. CLI: cross-DB fan-out includes packages + samples.
"$BIN" search --packages-db ~/.cupertino-dev/packages.db \
              --search-db ~/.cupertino-dev/search.db \
              --sample-db ~/.cupertino-dev/samples.db \
              "Logger" --limit 5
```

Expected:
- (1) pre-#860 fix: empty result list (known gap, surface separately,
  do NOT count as a smoke failure). Post-#860 fix: non-empty list,
  every row's framework or owner/repo references a SwiftUI-importing
  package.
- (2) ranked result list spanning multiple sources (samples + search.db
  arms work today; packages arm contributes BM25-ranked rows).

### Samples-side import sanity (works today, no gap)

samples.db's indexer correctly captures `import X` statements into
the `file_imports` table. Verify the population shape on the
inspected DB:

```bash
sqlite3 -readonly ~/.cupertino-dev/samples.db <<'SQL'
SELECT 'file_imports rows: ' || COUNT(*) FROM file_imports;
SELECT '-- top-10 imported modules --';
SELECT module_name || ': ' || COUNT(*) FROM file_imports
       GROUP BY module_name ORDER BY COUNT(*) DESC LIMIT 10;
SELECT 'samples importing SwiftUI: '
       || COUNT(DISTINCT f.project_id)
       FROM file_imports i JOIN files f ON i.file_id = f.id
       WHERE i.module_name = 'SwiftUI';
SQL
```

Expected on the brew sample-code corpus: ~13,000 rows; top-10
dominated by `SwiftUI`, `Foundation`, `UIKit`, `RealityKit`,
`SwiftData`; SwiftUI-importing projects ≈ 300. This pattern is the
working reference for the #860 fix on the packages side (port the
`file_imports` capture path from `Sample.Index.Database` to
`Search.PackageIndex`).

### MCP tool smoke

```bash
BIN=/Volumes/Code/DeveloperExt/public/cupertino/Packages/.build/release/cupertino

# Drive the MCP server through stdio for one initialize + tools/call
(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"query":"View","source":"packages","apple_imports":"SwiftUI","limit":3}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search_generics","arguments":{"constraint":"View","limit":3}}}' \
) > /tmp/cupertino-mcp-in.json

timeout 15 "$BIN" serve < /tmp/cupertino-mcp-in.json > /tmp/cupertino-mcp-out.txt 2>&1
```

Then extract the two `result.content[0].text` bodies from
`/tmp/cupertino-mcp-out.txt` (each line is a JSON-RPC frame) and verify:
- id=3 response: markdown with 3 rows, every row references a
  SwiftUI-importing package.
- id=4 response: markdown with 3 source-tagged sections: Apple Docs
  (search.db), Sample Code (samples.db), Swift Packages (packages.db);
  at least one of the latter two non-empty.

## Stop conditions

You are done when ALL of these are true:

1. Both `~/.cupertino-dev/{packages,samples}.db` exist.
2. Both are at `user_version = 4`, `integrity_check = ok`.
3. **`generic_constraints` is populated** on both `samples.db.file_symbols`
   and `packages.db.package_symbols` (the AppleConstraintsPass works
   correctly on both DBs today).
4. **`apple_imports_json` is _expected_ to be near-zero until #860
   lands.** This is a known gap, NOT a stop-condition failure. Do
   not block on it. Once #860 ships, flip this to "populated for ≥50
   packages" and re-run.
5. **`swift_tools_version` is _expected_ to be zero until #861 lands.**
   Same treatment as #860 — known gap, not a stop failure.
6. **No-poison probes use the tightened HTML-shape SQL above (#862).**
   Both return 0 on a healthy corpus. Substring probes that return
   20-30 hits are the loose-probe false-positives; ignore those and
   use the tightened SQL.
7. CLI + MCP smoke return results. The `--apple-imports SwiftUI`
   smoke returns empty until #860 lands (known); the un-filtered
   `--source packages` smoke returns rich results today.
8. Brew `~/.cupertino/*.db` mtime + size are unchanged from pre-run.
   Verify:
   ```bash
   stat -f '%Sm %z %N' ~/.cupertino/*.db
   ```

## Surface conditions (come back early)

Stop and ask the operator if any of these:

- A pre-flight check fails (corpora missing, build fails).
- The save crashes mid-run or exits non-zero.
- The **tightened HTML-shape** poison probe returns non-zero (real
  poison present). Substring-probe noise on legitimate HTTP-related
  source is NOT a surface condition (covered by #862; use the
  tightened probe).
- **`generic_constraints` coverage is exactly 0** on either DB (the
  AppleConstraintsPass silently failed; check
  apple-constraints.json presence and the `[enrichment/...]` log line).
  Near-zero `apple_imports_json` / `swift_tools_version` is the
  expected pre-#860 / pre-#861 state — NOT a surface condition.
- Brew DB mtime changed (you violated the no-touch contract).
- The corpus you read is suspiciously different in shape from what
  the operator described (e.g. zero packages, zero samples).
- **A new gap not tracked by #860 / #861 / #862.** Surface it as a
  fresh finding, file a GH issue per `feedback_file_issue_first_for_every_bug`,
  cross-link from the report.

## Handback report format

One message containing:

1. Build wall-clock + exit code for each save run.
2. Final DB paths + `stat` output (mtime + size).
3. Row counts: projects/packages, files, symbols.
4. New-column coverage counts (apple_imports_json, generic_constraints).
5. Output of the CLI `--apple-imports SwiftUI` smoke.
6. Output of the MCP `search_generics` smoke (first 30 lines of each
   source section).
7. Brew DB stat output proving no-touch contract held.
8. Log paths for the two save runs.

Then stop. No tag, no release, no homebrew. Hand back.

## Common gotchas

- **`cupertino save` exits in 1s with no output → corpus missing.**
  The save skips cleanly when its input dir is absent. Verify
  `--packages-dir` / `--samples-dir` path before re-running.
- **`raw swift build` binary writes to `~/.cupertino` (brew).** The
  composition root reads `cupertino.config.json` next to the binary;
  `make build-release` puts the right config there. Use the release
  binary or drop the config yourself:
  `printf '{"baseDirectory":"~/.cupertino-dev"}\n' > Packages/.build/release/cupertino.config.json`
- **AppleConstraintsPass + AppleImportsPass silently no-op when
  `<base-dir>/apple-constraints.json` is missing.** Both passes log
  zero affected rows in that case. Without enrichment, the new
  columns stay NULL even though the build completes "successfully".
  Always verify `~/.cupertino-dev/apple-constraints.json` is on disk
  before kicking off save.
- **GNU vs BSD tail.** `tail -f --pid=$PID` is GNU-only and exits
  immediately on BSD/macOS. Use `while ps -p $PID >/dev/null; do …;
  done` or `tail -f <log> &; wait $PID; kill $tail_pid` instead.
- **Don't use sleep loops to poll the save.** Either fire-and-forget
  with `run_in_background: true` and wait for the harness's
  completion notification, or use a Monitor task watching the log
  for the `✅ ... built` line.
- **The release binary's config pins `~/.cupertino-dev` by design
  (#218).** That's the safety net that prevents accidental brew
  writes. Verify it's still there before every save invocation.

## References

### Open issues tracking gaps surfaced by this recipe

- **#860** — packages.db: AppleImportsPass joins on wrong column;
  `apple_imports_json` populated for 1/183 packages. Fix needs
  packages-side import capture (`package_imports` table mirroring
  samples.db's `file_imports`) + the join change. **Scope: packages.db
  indexer only; do not touch search.db creation.**
- **#861** — packages.db: `swift_tools_version` column never populated
  by indexer (0/183 packages). Fix is a Package.swift-line-1 read +
  bind at metadata insert time. **Scope: packages.db indexer only.**
- **#862** — docs(handoff): this doc's poison probe was too loose
  (substring on content); tightened to HTML-shape probe in the same
  PR that filed #862. **Scope: doc only.**

### Source code

- `Packages/Sources/CLI/Commands/CLIImpl.Command.Save.swift`: the save
  command surface.
- `Packages/Sources/CLI/Commands/CLIImpl.Command.Save.Indexers.swift`:
  composition-root activation of the enrichment passes.
- `Packages/Sources/Search/PackageIndex.swift`: packages.db schema
  v3→v4 migration + indexer.
- `Packages/Sources/Search/PackageIndexer.swift`: packages.db AST
  extraction + insertion path (touchpoint for #860 import capture +
  #861 swift-tools-version capture).
- `Packages/Sources/SampleIndex/Sample.Index.Database.swift`:
  samples.db schema v3→v4 migration + indexer; canonical working
  reference for the `file_imports` capture that #860 needs to port.

### Companion docs + memory

- `docs/design/per-db-schema-spec.md` §11: cross-DB column mapping
  (which surface touches which column on which DB).
- `feedback_never_touch_brew_db` memory: the no-write contract.
- `feedback_tail_cmd_on_start` memory: always show the tail command
  in the kickoff response.
- `feedback_file_issue_first_for_every_bug` memory: any new gap
  discovered during a run gets a GH issue filed BEFORE the handback
  report; this doc references existing issues but doesn't ship fixes
  inline.
