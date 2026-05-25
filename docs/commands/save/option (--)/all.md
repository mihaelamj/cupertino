# --all

Build every source's DB in one invocation. Replaces the pre-#1037 default behaviour of bare `cupertino save` (which built all three legacy DBs).

## Synopsis

```bash
cupertino save --all
```

## Description

Selects every valid `--source <id>` value at once. Mutually exclusive with `--source`; passing both is a usage error.

The full list of sources built today (registry-derived; expanding the production source registry adds entries automatically): `apple-docs`, `swift-evolution`, `hig`, `apple-archive`, `swift-org`, `swift-book`, `samples`, `packages`.

## Why explicit

Pre-#1037 `cupertino save` defaulted to building every DB when no scope flag was set. The post-#1037 surface makes scope explicit (per the "each source needs its own option" direction): no scope = usage error. `--all` is the opt-in for the old default behaviour.

## Examples

```bash
# Rebuild every DB from local source directories.
cupertino save --all

# CI / scripted; skip the preflight prompt.
cupertino save --all --yes
```

## Related

- `--source <id>` – build a specific source (repeatable)
- `--remote` – stream documentation from GitHub instead of building from a local corpus
- `--clear` – wipe existing rows before re-indexing each source
