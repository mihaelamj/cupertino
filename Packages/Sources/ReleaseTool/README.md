# ReleaseTool

Maintainer-only CLI for automating Cupertino releases.

## Overview

`cupertino-rel` automates the multi-step release process:

1. **bump** - Update version in Constants.swift, README.md, CHANGELOG.md, DEPLOYMENT.md
2. **tag** - Commit changes and create git tag
3. **databases** - Package and upload databases to cupertino-docs
4. **homebrew** - Update Homebrew formula with new SHA256
5. **full** - Run all steps in sequence (default)

## Building

```bash
cd Packages
swift build --product cupertino-rel
```

## Usage

### Full Release

```bash
# By version number
cupertino-rel 0.5.0

# By bump type
cupertino-rel patch   # 0.4.0 → 0.4.1
cupertino-rel minor   # 0.4.0 → 0.5.0
cupertino-rel major   # 0.4.0 → 1.0.0

# Preview without changes
cupertino-rel 0.5.0 --dry-run
```

### Individual Commands

```bash
# Bump version only
cupertino-rel bump 0.5.0
cupertino-rel bump patch --dry-run

# Tag and push
cupertino-rel tag --push
cupertino-rel tag --version 0.5.0 --dry-run

# Upload databases (requires GITHUB_TOKEN)
export GITHUB_TOKEN="your-cupertino-docs-token"
cupertino-rel databases
cupertino-rel databases --dry-run

# Update Homebrew formula
cupertino-rel homebrew --version 0.5.0
cupertino-rel homebrew --dry-run
```

### Skip Options

```bash
# Skip waiting for GitHub Actions
cupertino-rel 0.5.0 --skip-wait

# Skip database upload
cupertino-rel 0.5.0 --skip-databases

# Skip Homebrew update
cupertino-rel 0.5.0 --skip-homebrew
```

## Environment Variables

| Variable | Required For | Description |
|----------|--------------|-------------|
| `GITHUB_TOKEN` | `databases`, `full` | Token with write access to cupertino-docs repo |

## Files Modified

The `bump` command updates:

| File | Field |
|------|-------|
| `Packages/Sources/Shared/Constants/Shared.Constants.swift` | `version = "X.Y.Z"` |
| `README.md` | `**Version:** X.Y.Z` |
| `CHANGELOG.md` | Adds `## X.Y.Z` section |
| `docs/DEPLOYMENT.md` | `**Version:** X.Y.Z` |

## Why Separate from CLI?

- **Security** - Release credentials not exposed to users
- **Clean UX** - Users only see commands they need
- **Maintainability** - Release logic can evolve independently

## Architecture

```
ReleaseTool/
├── ReleaseCLI.swift           # @main entry point, shared helpers
├── BumpCommand.swift          # Version bumping with regex
├── TagCommand.swift           # Git operations
├── DatabaseReleaseCommand.swift  # GitHub Releases API
├── HomebrewCommand.swift      # Formula updates
├── FullCommand.swift          # Orchestrates all steps
└── README.md                  # This file
```

## See Also

- [docs/DEPLOYMENT.md](../../../docs/DEPLOYMENT.md) - Full release documentation
- [Issue #98](https://github.com/mihaelamj/cupertino/issues/98) - Original feature request
