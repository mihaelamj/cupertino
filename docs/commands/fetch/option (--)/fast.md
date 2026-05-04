# --fast

Use higher concurrency / shorter timeout for `--type availability`

## Synopsis

```bash
cupertino fetch --type availability --fast
```

## Description

Tunes the availability annotation pass for speed at the cost of robustness — higher concurrency, shorter per-request timeout. Use when the network is reliable and you want the run to finish quickly.

## Default

`false`

## Example

```bash
cupertino fetch --type availability --fast
```

## Notes

- Only meaningful for `--type availability`. No effect on other types.
- On flaky networks, the shorter timeouts can cause more retries; the default mode is safer for a slow link.
