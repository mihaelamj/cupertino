# --hig-dir

**Optional.** Directory containing the HIG corpus (#1063, maintainer workflow).

## Synopsis

```bash
cupertino save --source hig --hig-dir <path>
```

## Description

Overrides the default HIG corpus location for `cupertino save --source hig`. Added in [#1063](https://github.com/mihaelamj/cupertino/issues/1063) to bring HIG in line with the other sources' typed `--<source>-dir` overrides; before it, maintainers had to symlink `<base>/hig` to their corpus path. Most users never use this: they download the pre-built bundle via `cupertino setup`.

## Default

`~/.cupertino/hig`

## Example

```bash
cupertino save --source hig --hig-dir ~/corpora/hig
```
