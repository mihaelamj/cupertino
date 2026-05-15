# `cupertino save --dry-run`

Run the full `save` import pipeline against a throwaway temp database;
emit the same final report and per-document import log a real save
would, then delete the temp DB. Used to verify that a corpus imports
clean before committing it to the on-disk `search.db`.

## Usage

```sh
cupertino save --dry-run                     # uses default docs dir
cupertino save --dry-run --docs-dir /path    # arbitrary docs dir
cupertino save --dry-run --docs-dir /Volumes/Code/.../cupertino-docs/docs
```

All other `save` flags (`--docs-dir`, `--evolution-dir`, `--clear`,
`--yes`, etc.) are honored. Only `--remote` is incompatible (a remote
sync streams to its own destination already).

## What it does

1. Resolves the same source directories `save` would.
2. Opens a temp file in `$TMPDIR` named `cupertino-dryrun-<uuid>.db`.
3. Runs the full import pipeline (preflight, framework discovery,
   per-document indexing, FTS5 + structured tables, AST, symbols)
   against the temp DB.
4. Prints the final report exactly as a real save would, plus the
   per-document log file location.
5. Deletes the temp DB regardless of outcome.

## When to use it

- Before re-indexing the shipped bundle (12-hour run on a full
  corpus): verify a fresh corpus produces 0 collisions, 0 redundancy,
  no content lost.
- After landing a URI canonicalization change: confirm the existing
  corpus still imports clean.
- During development of new validation rules: iterate without
  burning real DB writes.

## Output

Same shape as a real save, plus a `🧪 Dry-run` banner before and
after. Exit code is identical to a real save with the same input:
zero if the import succeeds, non-zero otherwise.

## See also

- `cupertino save` — write the index for real
- `cupertino save --clear` — wipe the existing DB and rebuild
- `cupertino doctor --save` — preflight only, no DB at all
- `docs/PRINCIPLES.md` — the import-time invariants verified by this
  command
