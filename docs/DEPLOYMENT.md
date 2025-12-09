# Cupertino Deployment Guide

**Version:** 0.4.0
**Last Updated:** 2025-12-09

This guide covers the complete release process for Cupertino.

---

## Table of Contents

1. [Quick Release Workflow](#quick-release-workflow)
2. [Detailed Steps](#detailed-steps)
3. [Installation Methods](#installation-methods)
4. [Troubleshooting](#troubleshooting)

---

## Quick Release Workflow

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

# 5. Build locally and install
make build && sudo make install

# 6. Upload databases to cupertino-docs
export GITHUB_TOKEN="your-cupertino-docs-token"
cupertino release

# 7. Update Homebrew tap
cd /tmp && rm -rf homebrew-tap
git clone https://github.com/mihaelamj/homebrew-tap.git
cd homebrew-tap
# Edit Formula/cupertino.rb with new version, URL, and SHA256
git add -A && git commit -m "chore: bump cupertino to X.Y.Z"
git push
```

---

## Detailed Steps

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

### Step 5: Create GitHub Release

Go to [GitHub Releases](https://github.com/mihaelamj/cupertino/releases) and create a release:

**Title:**
```
vX.Y.Z - Brief Feature Summary
```

**Description:**
```markdown
## What's New

### Feature Name
- Description of feature
- Another point

### Fixes
- Fix description

## Issues Closed
#issue1, #issue2
```

### Step 6: Build and Install Locally

```bash
make build
sudo make install
cupertino --version  # Verify
```

### Step 7: Upload Databases

Upload pre-built databases to `mihaelamj/cupertino-docs`:

```bash
export GITHUB_TOKEN="your-cupertino-docs-token"
cupertino release
```

This:
- Packages `~/.cupertino/search.db` and `samples.db`
- Creates release tag `vX.Y.Z` in cupertino-docs
- Uploads zip with SHA256 checksum

### Step 8: Update Homebrew Tap

Get the SHA256 of the CLI binary:

```bash
curl -sL https://github.com/mihaelamj/cupertino/releases/download/vX.Y.Z/cupertino-vX.Y.Z-macos-universal.tar.gz.sha256
```

Clone and update the tap:

```bash
cd /tmp && rm -rf homebrew-tap
git clone https://github.com/mihaelamj/homebrew-tap.git
cd homebrew-tap
```

Edit `Formula/cupertino.rb`:

```ruby
class Cupertino < Formula
  desc "Apple Documentation MCP Server - Search Apple docs, Swift Evolution, and sample code"
  homepage "https://github.com/mihaelamj/cupertino"
  url "https://github.com/mihaelamj/cupertino/releases/download/vX.Y.Z/cupertino-vX.Y.Z-macos-universal.tar.gz"
  sha256 "NEW_SHA256_HERE"
  version "X.Y.Z"
  license "MIT"

  depends_on :macos
  depends_on macos: :sequoia

  def install
    bin.install "cupertino"
    (bin/"Cupertino_Resources.bundle").install Dir["Cupertino_Resources.bundle/*"]
  end

  def post_install
    ohai "Run 'cupertino setup' to download documentation databases"
  end

  test do
    assert_match "X.Y.Z", shell_output("#{bin}/cupertino --version")
  end
end
```

Commit and push:

```bash
git add Formula/cupertino.rb
git commit -m "chore: bump cupertino to X.Y.Z"
git push
```

### Step 9: Verify

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

### GitHub Actions Build Failed

Check the [Actions tab](https://github.com/mihaelamj/cupertino/actions) for logs.

### cupertino release: Not Found

Wrong token. Use the token for `cupertino-docs` repo, not `cupertino`:

```bash
export GITHUB_TOKEN="cupertino-docs-token-here"
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

- [DEVELOPMENT.md](../DEVELOPMENT.md) - Development workflow
- [ARCHITECTURE.md](ARCHITECTURE.md) - Technical architecture
- [README.md](../README.md) - Project overview
