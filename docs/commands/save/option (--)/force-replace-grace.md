# --force-replace-grace

Seconds to wait between `SIGTERM` and `SIGKILL` when [`--force-replace`](force-replace.md) terminates a sibling `cupertino save`.

## Synopsis

```bash
cupertino save --force-replace --force-replace-grace <seconds>
```

## Description

The `--force-replace` termination ladder is:

1. `SIGTERM` to each (re-verified) sibling PID
2. Poll every 1 second for up to `--force-replace-grace` seconds
3. `SIGKILL` any PID still alive after grace expires
4. One final `kill(pid, 0)` poll — if anything still answers, abort the calling `save` cleanly with `❌ Refusing to proceed`

The grace window matters because SIGKILL mid-INSERT leaves the DB in a `database is locked` / `database disk image is malformed` state — exactly the corruption class this gate exists to prevent. SIGTERM-then-wait gives SQLite time to flush its WAL + checkpoint cleanly.

**Default: 30 seconds.** That's a practical floor for a moderately-sized WAL (the `samples.db` checkpoint case observed during #513 took ~5s; `search.db` near-end-of-day-builds with multi-GB WAL can need 60+).

## Values

A positive integer (seconds).

## Examples

### Default — fine for most cases

```bash
cupertino save --force-replace --yes
# grace defaults to 30 seconds
```

### Generous grace for a near-completed search.db build

```bash
cupertino save --force-replace --yes --force-replace-grace 120
```

If the sibling save is mid-checkpoint with a multi-GB WAL, give it 2 minutes to flush. The cost of waiting is wallclock; the cost of SIGKILL-mid-checkpoint is a corrupted DB.

### Aggressive (CI cleanup, sibling known-frozen)

```bash
cupertino save --force-replace --yes --force-replace-grace 5
```

Only when you've already confirmed the sibling is stuck (e.g. via `ps -p <pid>` showing 0% CPU for minutes + no WAL growth).

## See Also

- [`--force-replace`](force-replace.md) — the flag this option configures
- [`--yes`](yes.md) — bypass the typed-confirmation gate (orthogonal to grace)
- Issue [#722](https://github.com/mihaelamj/cupertino/issues/722) — why the grace window is configurable
