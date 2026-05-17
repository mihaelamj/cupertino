# --force-replace

Authorise SIGTERM of any sibling `cupertino save` that targets the same database(s) as this invocation.

## Synopsis

```bash
cupertino save [--docs|--packages|--samples] --force-replace
cupertino save [--docs|--packages|--samples] --force-replace --yes
```

## Description

`cupertino save` writes one or more local databases (`search.db`, `samples.db`, `packages.db`). Two concurrent saves targeting the **same** database compete for the SQLite write lock, burn duplicate CPU + memory, and risk corrupting each other's WAL on shutdown. The concurrent-save gate (#253) detects this case and surfaces it via an interactive prompt before any write.

`--force-replace` is the explicit recovery path. When a sibling save is detected:

1. **With `--force-replace` and an interactive TTY** — the gate prints the conflicting PID(s) + their elapsed runtime, then prompts:
   ```
   This will lose any in-flight work the sibling has done.
   Type 'replace' to confirm:
   ```
   The literal word `replace` (case-insensitive, leading/trailing whitespace tolerated) is required. Single keystrokes, `y`, `yes`, etc. are rejected — this is deliberately the kind of action that should never happen by accident.

2. **With `--force-replace --yes`** — bypasses the typed-confirmation gate. The flag combination is the non-interactive (CI / scripted) authorisation pattern.

3. **With `--force-replace` and no TTY + no `--yes`** — aborts cleanly with a clear error. `--force-replace` alone is meaningless in an unattended context.

## Termination ladder

Once authorised, the gate:

1. Sends **SIGTERM** to each conflicting PID — gives the sibling a chance to flush its SQLite WAL + checkpoint cleanly.
2. Waits up to **30 seconds** for clean exit, polling every 1 second.
3. Falls back to **SIGKILL** for any PID still alive after grace expires.

The grace window matters: a SIGKILL mid-INSERT leaves the DB in a `database is locked` / `database disk image is malformed` state. SIGTERM-then-wait is the safe path; SIGKILL is the fallback for stuck processes.

## Pre-flight diagnostic ladder (run before `--force-replace`)

Skip none of these — they take 30 seconds total and save you from losing real work:

1. **Is the sibling progressing?**
   ```bash
   ps -p <pid> -o pid,etime,%cpu,rss
   ```
   Active CPU + recently-grown RSS = working. Frozen for minutes with 0% CPU = candidate for `--force-replace`.

2. **Who holds the DB lock?**
   ```bash
   lsof ~/.cupertino/search.db ~/.cupertino/search.db-wal 2>/dev/null
   ```
   Confirms the sibling PID is the one cupertino's gate flagged. If a different process holds the lock, `--force-replace` won't help — investigate that PID first.

3. **Is the WAL actively growing?**
   ```bash
   ls -lh ~/.cupertino/search.db-wal
   ```
   Run twice 10s apart. WAL still growing = checkpoint in progress = leave it alone.

4. **Only if 1-3 confirm the sibling is genuinely stuck** — run `cupertino save --force-replace` (or `--force-replace --yes` for CI).

## When to use

- **Recovery from runaway-save corruption** — exactly the scenario that motivated #253's gate. A runaway `cupertino save` process leaves a partial write + holds the lock; `cupertino save --force-replace --yes` clears it.
- **CI re-run after an interrupted previous run** — `--force-replace --yes` skips the prompt; the typed-confirmation gate is a TTY-only safeguard.

## When NOT to use

- **Routine workflow.** The plain `cupertino save` (no flag) is the right interactive default — the existing `[c]/[w]/[a]` prompt offers wait + abort options that don't risk losing the sibling's work.
- **Without confirming the sibling is actually stuck.** A sibling save that's progressing normally should be left alone; killing it loses real work. Run the diagnostic ladder above first.

## When SIGKILL doesn't take

`terminateSiblings` returns a `TerminationOutcome` after the SIGKILL fallback. If any PID is still alive (cross-user EPERM, D-state uninterruptible sleep), `cupertino save` aborts with a clear `❌ Refusing to proceed` error rather than cascading into `database is locked`. Surface the PID(s) the error names, investigate manually, then retry. The defensive abort exists because silently proceeding to a SQLite lock failure would be worse than the gate refusing to start.

## See also: `--force-replace-grace <seconds>`

The default 30-second SIGTERM→SIGKILL window is a practical floor for a moderately-sized WAL. Raise it (`--force-replace-grace 60`, `--force-replace-grace 120`) when the sibling is near-completing a multi-GB checkpoint — SIGKILL landing mid-checkpoint is exactly the corruption class this gate exists to prevent, so giving SQLite more time to flush is the safer default.

## See Also

- [`--yes`](yes.md) — bypass preflight prompts (the same flag bypasses `--force-replace`'s typed-confirmation gate)
- Issue [#722](https://github.com/mihaelamj/cupertino/issues/722) — the `--force-replace` design rationale
- Issue [#253](https://github.com/mihaelamj/cupertino/issues/253) — the base concurrent-save gate
