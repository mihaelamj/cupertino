# --docs-dir

**Optional.** Directory containing crawled documentation (maintainer workflow).

## Synopsis

```bash
cupertino save --source apple-docs --docs-dir <path>
```

## Description

Specifies the directory containing crawled documentation files from a previous `cupertino fetch` run. Pointing at an absent or empty directory is fine, the apple-docs source is then skipped cleanly with `[apple-docs] skipped (no local corpus)`, and the rest of `save` runs against whichever other sources happen to be on disk ([#671](https://github.com/mihaelamj/cupertino/issues/671)).

Most users do not have a crawled docs directory, they download the pre-built bundle via `cupertino setup` and never use `cupertino save` at all.

## Default

`~/.cupertino/docs`

## Examples

### Index Default Documentation
```bash
cupertino save --all
```

### Index Custom Directory
```bash
cupertino save --source apple-docs --docs-dir ./my-docs
```

### Index Swift.org Documentation
```bash
cupertino save --source swift-org --swift-org-dir ~/.cupertino/swift-org
```

### Absolute Path
```bash
cupertino save --source apple-docs --docs-dir /Users/username/Documents/apple-docs
```

## Expected Structure

The directory should contain:
```
docs-dir/
├── metadata.json           # Optional but recommended
├── framework1/
│   ├── page1.json
│   └── page2.json
└── framework2/
    └── page3.json
```

## Notes

- Directory may be absent, `save` skips the apple-docs source cleanly when it is ([#671](https://github.com/mihaelamj/cupertino/issues/671))
- Should contain structured `.json` pages (older markdown fixtures are accepted where the source strategy supports them)
- Works with output from `cupertino fetch`
- Tilde (`~`) expansion is supported
- Recursive: indexes all files in subdirectories
