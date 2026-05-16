# --docs-dir

**Optional.** Directory containing crawled documentation (maintainer workflow).

## Synopsis

```bash
cupertino save --docs-dir <path>
```

## Description

Specifies the directory containing crawled documentation files from a previous `cupertino fetch` run. Pointing at an absent or empty directory is fine — the apple-docs source is then skipped cleanly with `[apple-docs] skipped (no local corpus)`, and the rest of `save` runs against whichever other sources happen to be on disk ([#671](https://github.com/mihaelamj/cupertino/issues/671)).

Most users do not have a crawled docs directory — they download the pre-built bundle via `cupertino setup` and never use `cupertino save` at all.

## Default

`~/.cupertino/docs`

## Examples

### Index Default Documentation
```bash
cupertino save
```

### Index Custom Directory
```bash
cupertino save --docs-dir ./my-docs
```

### Index Swift.org Documentation
```bash
cupertino save --docs-dir ~/.cupertino/swift-org
```

### Absolute Path
```bash
cupertino save --docs-dir /Users/username/Documents/apple-docs
```

## Expected Structure

The directory should contain:
```
docs-dir/
├── metadata.json           # Optional but recommended
├── framework1/
│   ├── page1.md
│   └── page2.md
└── framework2/
    └── page3.md
```

## Notes

- Directory may be absent — `save` skips the apple-docs source cleanly when it is ([#671](https://github.com/mihaelamj/cupertino/issues/671))
- Should contain Markdown (`.md`) files or structured `.json` pages
- Works with output from `cupertino fetch`
- Tilde (`~`) expansion is supported
- Recursive: indexes all files in subdirectories
