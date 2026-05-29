# --swift-book-dir

**Optional.** Directory containing the Swift Book corpus (#1063, maintainer workflow).

## Synopsis

```bash
cupertino save --source swift-book --swift-book-dir <path>
```

## Description

Overrides the default Swift Book corpus location for `cupertino save --source swift-book`. Added in [#1063](https://github.com/mihaelamj/cupertino/issues/1063) alongside `--hig-dir` to complete the per-source `--<source>-dir` override surface. Most users never use this: they download the pre-built bundle via `cupertino setup`.

## Default

`~/.cupertino/swift-book`

## Example

```bash
cupertino save --source swift-book --swift-book-dir ~/corpora/swift-book
```
