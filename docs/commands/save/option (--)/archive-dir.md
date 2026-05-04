# --archive-dir

Directory containing Apple Archive documentation

## Synopsis

```bash
cupertino save --archive-dir <path>
```

## Description

Override the default `~/.cupertino/archive/` location for legacy Apple Archive guides (Core Animation Programming Guide, Quartz 2D, KVO/KVC, etc.).

## Default

`~/.cupertino/archive/` (or under `--base-dir/archive/` when `--base-dir` is set)

## Example

```bash
cupertino save --archive-dir ~/old-docs/archive
```

## Notes

- Tilde (`~`) expansion supported.
- Missing directory → archive content is skipped with an info log; the docs build still succeeds.
- Indexed into `search.db` under the `apple-archive` source prefix.
