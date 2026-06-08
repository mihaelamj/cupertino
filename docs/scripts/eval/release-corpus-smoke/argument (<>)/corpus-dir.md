# <corpus-dir>

Prepared release corpus directory to test against.

```bash
scripts/eval/release-corpus-smoke.sh ~/.cupertino
```

If omitted, the script uses `$CUPERTINO_RELEASE_CORPUS`; if that is unset, it
uses `~/.cupertino`.

The directory must contain the eight release database files directly:

- `apple-documentation.db`
- `hig.db`
- `apple-archive.db`
- `swift-evolution.db`
- `swift-org.db`
- `swift-book.db`
- `apple-sample-code.db`
- `packages.db`
