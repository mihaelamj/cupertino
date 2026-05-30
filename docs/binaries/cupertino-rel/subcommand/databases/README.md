# cupertino-rel databases

Package and upload databases to GitHub Releases.

## Synopsis

```bash
cupertino-rel databases [options]
```

## Description

Packages the documentation databases and uploads them to the cupertino-docs GitHub repository for distribution via `cupertino setup`.

## Options

| Option | Description |
|--------|-------------|
| [--base-dir](option (--)/base-dir.md) | Base directory containing databases |
| [--repo](option (--)/repo.md) | GitHub repository (owner/repo) |
| [--dry-run](option (--)/dry-run.md) | Create release without uploading |
| [--repo-root](option (--)/repo-root.md) | Path to repository root |
| [--allow-missing](option (--)/allow-missing.md) | Allow publishing when some derived databases are absent |

## Files Uploaded

The bundled database set is derived from the production source registry, not a
hardcoded list: one SQLite file per enabled source's declared `destinationDB`
(deduped by filename). Adding a new source automatically extends the bundle.
Today that set is the per-source databases:

- `apple-documentation.db`
- `hig.db`
- `apple-archive.db`
- `swift-evolution.db`
- `swift-org.db`
- `swift-book.db`
- `apple-sample-code.db`
- `packages.db`

A pre-split unified `search.db` sitting in the base directory is never bundled,
because no enabled source declares it as a destination.

## Examples

```bash
cupertino-rel databases
cupertino-rel databases --dry-run
cupertino-rel databases --repo mihaelamj/cupertino-docs
```
