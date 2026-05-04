# --per-source

Per-source candidate cap before reciprocal-rank fusion

## Synopsis

```bash
cupertino search <query> --per-source <n>
```

## Description

In fan-out mode (no `--source`), each contributing fetcher (apple-docs, samples, packages, etc.) returns up to `--per-source` candidates before they're cross-ranked via RRF. Caps a noisy source from drowning out a strong single hit from another. ([#239](https://github.com/mihaelamj/cupertino/issues/239))

## Default

`10`

## Example

```bash
cupertino search "actor reentrancy" --per-source 5 --limit 3
```

## Notes

- Only applies in fan-out mode. Ignored in `--source <name>` mode.
- After per-source caps, RRF (k=60) ranks the combined pool, then `--limit` truncates to the final list.
