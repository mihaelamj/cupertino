# cupertino release

Package and upload databases to GitHub Releases.

## Synopsis

```bash
cupertino release [--base-dir <dir>] [--repo <owner/repo>] [--dry-run]
```

## Description

The `release` command packages the local search databases into a zip file and uploads them to GitHub Releases. This is used by maintainers to publish new database versions that users can download via `cupertino setup`.

**Note:** This command is for maintainers only. It requires a `GITHUB_TOKEN` with write access to the release repository.

## Options

- `--base-dir` - Directory containing databases (default: `~/.cupertino/`)
- `--repo` - GitHub repository for releases (default: `mihaelamj/cupertino-docs`)
- `--dry-run` - Create zip locally without uploading

## Examples

### Dry Run (Test Locally)

```bash
cupertino release --dry-run
```

### Publish Release

```bash
export GITHUB_TOKEN=your_token
cupertino release
```

### Custom Repository

```bash
cupertino release --repo myorg/my-docs
```

## Output

```
📦 Cupertino Release v0.3.0

📊 Database sizes:
   search.db:  1.2 GB
   samples.db: 192.2 MB

📁 Creating cupertino-databases-v0.3.0.zip...
   ✓ Created (228.3 MB)

🔐 Calculating SHA256...
   17dac4b84adaa04b5f976a7d1b9126630545f0101fe84ca5423163da886386a6

🚀 Creating release v0.3.0...
   ✓ Release created

⬆️  Uploading cupertino-databases-v0.3.0.zip...
   ✓ Upload complete

✅ Release v0.3.0 published!
   https://github.com/mihaelamj/cupertino-docs/releases/tag/v0.3.0
```

## Version Parity

The release tag matches the CLI version from `Constants.swift`:

| CLI Version | Release Tag | Zip Filename |
|-------------|-------------|--------------|
| 0.3.0 | v0.3.0 | cupertino-databases-v0.3.0.zip |
| 0.4.0 | v0.4.0 | cupertino-databases-v0.4.0.zip |

This ensures database schema compatibility between CLI and databases.

## Workflow

1. Refresh databases locally:
   ```bash
   cupertino fetch --type docs
   cupertino save
   ```

2. Bump version in `Sources/Shared/Constants.swift`

3. Publish release:
   ```bash
   cupertino release
   ```

4. Users can now run:
   ```bash
   cupertino setup
   ```

## Requirements

- `GITHUB_TOKEN` environment variable with `repo` scope
- Write access to the release repository
- Local databases in `~/.cupertino/` (or specified `--base-dir`)

## See Also

- [setup](../setup/) - Download pre-built databases (user command)
- [save](../save/) - Build databases locally
