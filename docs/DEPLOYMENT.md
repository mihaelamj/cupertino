# Cupertino Deployment Guide

**Version:** 0.8.0
**Last Updated:** 2025-12-12

This guide covers the complete release process for Cupertino.

---

## Table of Contents

1. [Environment Setup](#environment-setup)
2. [Automated Release (Recommended)](#automated-release-recommended)
3. [Manual Release Workflow](#manual-release-workflow)
4. [Installation Methods](#installation-methods)
5. [Troubleshooting](#troubleshooting)

---

## Environment Setup

**IMPORTANT:** Before building or releasing, set the `CUPERTINO_DOCS_TOKEN` environment variable.
This token is required for:
- Building `cupertino-rel` (Makefile only builds it when token is set)
- Uploading databases to cupertino-docs
- GitHub API operations

```bash
# Add to your ~/.zshrc or ~/.bashrc
export CUPERTINO_DOCS_TOKEN="your-github-token-here"

# Or set for current session
export CUPERTINO_DOCS_TOKEN="github_pat_..."
```

The token needs these scopes for `mihaelamj/cupertino-docs`:
- Contents (read/write)
- Metadata (read)

---

## Automated Release (Recommended)

Use `cupertino-rel` for automated releases:

```bash
# Ensure token is set (required for building cupertino-rel)
export CUPERTINO_DOCS_TOKEN="your-token"

# Build the release tool
cd Packages
swift build --product cupertino-rel

# Full release (bumps version, tags, waits for CI, uploads databases, updates Homebrew)
.build/debug/cupertino-rel 0.6.0

# Or use bump types
.build/debug/cupertino-rel patch  # 0.4.0 → 0.4.1
.build/debug/cupertino-rel minor  # 0.4.0 → 0.5.0
.build/debug/cupertino-rel major  # 0.4.0 → 1.0.0
```

### Subcommands

Run individual steps if needed:

```bash
# Preview version changes
cupertino-rel bump 0.5.0 --dry-run

# Bump version in all files
cupertino-rel bump 0.5.0

# Create and push git tag
cupertino-rel tag --push

# Upload databases to cupertino-docs (uses CUPERTINO_DOCS_TOKEN from env)
cupertino-rel databases

# Update Homebrew formula
cupertino-rel homebrew --version 0.5.0
```

### Full Release Output

```
🚀 Cupertino Release Workflow
   Current: 0.4.0 → New: 0.5.0

[1] Bump version in all files
    ✓ Updated Constants.swift
    ✓ Updated README.md
    ✓ Updated CHANGELOG.md
    ✓ Updated DEPLOYMENT.md

[2] Edit CHANGELOG.md
    Please edit CHANGELOG.md to add release notes.
    Press Enter when done...

[3] Create git tag and push
    ✓ Changes committed
    ✓ Tag v0.5.0 created
    ✓ Pushed to origin

[4] Wait for GitHub Actions build
    Waiting for GitHub Actions to build v0.5.0...
    ✓ Build complete!

[5] Upload databases to cupertino-docs
    ✓ Databases uploaded

[6] Update Homebrew formula
    ✓ Formula updated

✅ Release 0.5.0 complete!
```

---

## Manual Release Workflow

If you prefer manual control or need to debug:

> **⚠️ ORDER MATTERS:** You MUST commit the version bump BEFORE creating the tag.
> The tag must point to a commit that already has the correct version in Constants.swift.
> If you tag first, GitHub Actions will build a binary with the old version.

```bash
# 1. Update version and changelog
edit Packages/Sources/Shared/Constants.swift  # version = "X.Y.Z"
edit README.md                                 # Version: X.Y.Z
edit CHANGELOG.md                              # Add new section

# 2. Commit and push
git add -A && git commit -m "chore: bump version to X.Y.Z"
git push origin main

# 3. Create and push tag
git tag -a vX.Y.Z -m "vX.Y.Z - Release description"
git push origin vX.Y.Z

# 4. Wait for GitHub Actions to build the CLI release binary
# (creates cupertino-vX.Y.Z-macos-universal.tar.gz)

# 5. Build locally and install (ensure CUPERTINO_DOCS_TOKEN is set to build cupertino-rel)
export CUPERTINO_DOCS_TOKEN="your-token"
make build && sudo make install

# 6. Upload databases to cupertino-docs
cupertino-rel databases

# 7. Update Homebrew tap
cupertino-rel homebrew --version X.Y.Z
```

---

## Detailed Manual Steps

### Step 1: Update Version

Update version in these files:

| File | What to Change |
|------|----------------|
| `Packages/Sources/Shared/Constants.swift` | `public static let version = "X.Y.Z"` |
| `README.md` | `**Version:** X.Y.Z` |
| `CHANGELOG.md` | Add new `## X.Y.Z` section at top |

### Step 2: Commit Version Bump

```bash
git add Packages/Sources/Shared/Constants.swift README.md CHANGELOG.md
git commit -m "chore: bump version to X.Y.Z"
git push origin main
```

### Step 3: Verify Version Before Tagging

**IMPORTANT:** Always verify version is correct before creating tag:

```bash
# Check version in source
grep 'version = ' Packages/Sources/Shared/Constants.swift | head -1

# Build and verify binary reports correct version
make build && ./Packages/.build/release/cupertino --version
```

Both must show `X.Y.Z`. If not, fix before tagging.

### Step 4: Create GitHub Release Tag

```bash
git tag -a vX.Y.Z -m "vX.Y.Z - Brief description"
git push origin vX.Y.Z
```

This triggers GitHub Actions which:
- Builds universal binary (arm64 + x86_64)
- Signs and notarizes the binary
- Creates release with `cupertino-vX.Y.Z-macos-universal.tar.gz`

### Step 5: Upload Databases

```bash
# Uses CUPERTINO_DOCS_TOKEN from environment
cupertino-rel databases
```

### Step 6: Update Homebrew

```bash
cupertino-rel homebrew --version X.Y.Z
```

### Step 7: Verify

Test installation on a fresh machine:

```bash
brew tap mihaelamj/tap
brew install cupertino
cupertino --version    # Should show X.Y.Z
cupertino setup        # Downloads databases
cupertino doctor       # Health check
```

---

## Installation Methods

### 1. One-Command Install (Recommended)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/mihaelamj/cupertino/main/install.sh)
```

### 2. Homebrew

```bash
brew tap mihaelamj/tap
brew install cupertino
cupertino setup
```

### 3. Build from Source

```bash
git clone https://github.com/mihaelamj/cupertino.git
cd cupertino
make build
sudo make install
cupertino setup
```

---

## Repositories

| Repository | Purpose |
|------------|---------|
| [mihaelamj/cupertino](https://github.com/mihaelamj/cupertino) | Main CLI source code |
| [mihaelamj/cupertino-docs](https://github.com/mihaelamj/cupertino-docs) | Pre-built databases (search.db, samples.db) |
| [mihaelamj/homebrew-tap](https://github.com/mihaelamj/homebrew-tap) | Homebrew formula |

---

## Troubleshooting

### Don't Use Homebrew on Release Machine

On the machine where you run the release process, **do not install cupertino via Homebrew**. Use the locally built binary instead:

```bash
make build && sudo make install
```

The `cupertino-rel databases` command uses the version from `Constants.swift` to determine the release tag. If Homebrew has an old version installed, databases will be uploaded with the wrong version tag.

### GitHub Actions Build Failed

Check the [Actions tab](https://github.com/mihaelamj/cupertino/actions) for logs.

### databases: Not Found

Token not set or wrong token. Set `CUPERTINO_DOCS_TOKEN` with a token that has access to `cupertino-docs` repo:

```bash
export CUPERTINO_DOCS_TOKEN="your-token-here"
```

### cupertino-rel Shows Wrong Version

The Makefile only builds `cupertino-rel` when `CUPERTINO_DOCS_TOKEN` is set. If you ran `make build` without the token, an old version remains installed.

```bash
# Fix: rebuild with token set
export CUPERTINO_DOCS_TOKEN="your-token"
make build && sudo make install
cupertino-rel --version  # Should match Constants.swift
```

### Homebrew Shows Old Version

```bash
brew update
brew info cupertino  # Check available version
brew upgrade cupertino
```

### Version Mismatch

Ensure all three match:
- `cupertino --version`
- GitHub release tag
- cupertino-docs release tag

---

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) - Technical architecture
- [README.md](../README.md) - Project overview
