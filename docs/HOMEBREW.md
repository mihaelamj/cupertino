# Homebrew Formula Guide for Cupertino

Complete guide for creating and publishing Cupertino to Homebrew.

> **Note**: All `make` commands in this guide can be run from the **root directory** of the repository. A wrapper Makefile in the root delegates to `Packages/Makefile`, so you don't need to `cd Packages` first.

## Table of Contents

1. [What is Homebrew?](#what-is-homebrew)
2. [Quick Start](#quick-start)
3. [Creating the Formula](#creating-the-formula)
4. [Building Bottles](#building-bottles)
5. [Testing Locally](#testing-locally)
6. [Publishing Options](#publishing-options)
7. [Complete Workflow](#complete-workflow)

---

## What is Homebrew?

[Homebrew](https://brew.sh) is the most popular package manager for macOS. Creating a Homebrew formula allows users to install Cupertino with a single command:

```bash
brew install docsucker
```

Instead of manually building from source.

---

## Quick Start

### Option 1: Install from Local Build

```bash
# From root directory
make install

# Or from Packages subdirectory
cd Packages
make install

# Install to custom location
make install PREFIX=~/.local
```

### Option 2: Create Homebrew Tap (Recommended)

Create your own Homebrew tap for easy distribution:

```bash
# 1. Create tap repository
mkdir -p ~/homebrew-tap
cd ~/homebrew-tap
git init

# 2. Create formula (see template below)
mkdir -p Formula
# Create Formula/docsucker.rb

# 3. Push to GitHub
git remote add origin https://github.com/YOUR_USERNAME/homebrew-tap.git
git add .
git commit -m "Add docsucker formula"
git push -u origin main

# 4. Users can now install with:
brew tap YOUR_USERNAME/tap
brew install docsucker
```

---

## Creating the Formula

### Formula Template

Create `Formula/docsucker.rb`:

```ruby
class Cupertino < Formula
  desc "Apple Documentation Crawler & MCP Server"
  homepage "https://github.com/YOUR_USERNAME/cupertino"
  url "https://github.com/YOUR_USERNAME/cupertino/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "SHA256_HASH_OF_TARBALL"  # Get with: shasum -a 256 tarball.tar.gz
  license "MIT"  # Or your chosen license
  head "https://github.com/YOUR_USERNAME/cupertino.git", branch: "main"

  # Dependencies
  depends_on "swift" => :build
  depends_on xcode: ["16.0", :build]
  depends_on :macos => :sequoia  # macOS 15+

  def install
    # Build executables
    system "swift", "build",
           "--configuration", "release",
           "--disable-sandbox",
           "--build-path", ".build"

    # Install binaries
    bin.install ".build/release/docsucker"
    bin.install ".build/release/cupertino-mcp"

    # Install documentation
    doc.install "README.md"
    doc.install "DOCSUCKER_CLI_README.md"
    doc.install "MCP_SERVER_README.md"
    doc.install "TESTING_GUIDE.md"
  end

  def caveats
    <<~EOS
      Cupertino has been installed!

      📚 CLI Usage:
        Download Apple documentation:
          cupertino crawl --max-pages 15000 --output-dir ~/.docsucker/docs

        Download Swift Evolution proposals:
          cupertino crawl-evolution --output-dir ~/.docsucker/swift-evolution

      🤖 MCP Server Setup:
        1. Start server:
           cupertino-mcp serve

        2. Configure Claude Desktop:
           Edit ~/Library/Application Support/Claude/claude_desktop_config.json:
           {
             "mcpServers": {
               "cupertino": {
                 "command": "#{bin}/cupertino-mcp",
                 "args": ["serve"]
               }
             }
           }

        3. Restart Claude Desktop

      📖 Documentation:
        #{doc}/README.md
        #{doc}/DOCSUCKER_CLI_README.md
        #{doc}/MCP_SERVER_README.md

      ⚠️  Requirements:
        - macOS 15+ (Sequoia)
        - ~2-3 GB disk space for full Apple documentation
        - Internet connection for initial download
    EOS
  end

  test do
    # Test CLI help
    assert_match "Apple Documentation Crawler", shell_output("#{bin}/docsucker --help")
    assert_match "1.0.0", shell_output("#{bin}/docsucker --version")

    # Test MCP help
    assert_match "MCP Server", shell_output("#{bin}/cupertino-mcp --help")
    assert_match "1.0.0", shell_output("#{bin}/cupertino-mcp --version")

    # Test small crawl (integration test)
    testdir = testpath/"test-output"
    system bin/"cupertino", "crawl",
           "--start-url", "https://developer.apple.com/documentation/swift/array",
           "--max-pages", "1",
           "--max-depth", "0",
           "--output-dir", testdir,
           "--force"

    assert_predicate testdir, :exist?, "Output directory should exist"

    # Check that markdown file was created (in subdirectory)
    markdown_files = Dir.glob("#{testdir}/**/*.md")
    assert !markdown_files.empty?, "Should have created at least one markdown file"
  end
end
```

### Getting the SHA256 Hash

```bash
# Create release archive (from root directory)
make archive

# This creates: Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# Get SHA256
shasum -a 256 Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# Copy the hash into your formula
```

---

## Building Bottles

Homebrew bottles are pre-compiled binaries for faster installation.

### Using the Makefile

```bash
# Build bottle (from root directory)
make bottle

# This creates:
# Packages/docsucker-1.0.0.arm64_monterey.bottle.tar.gz

# Get SHA256 for bottle
shasum -a 256 Packages/docsucker-1.0.0.arm64_monterey.bottle.tar.gz
```

### Adding Bottles to Formula

```ruby
class Cupertino < Formula
  # ... (desc, homepage, etc.) ...

  bottle do
    root_url "https://github.com/YOUR_USERNAME/cupertino/releases/download/v1.0.0"
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "BOTTLE_SHA256_HERE"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "BOTTLE_SHA256_HERE"
    sha256 cellar: :any_skip_relocation, ventura:       "BOTTLE_SHA256_HERE"
  end

  # ... (rest of formula) ...
end
```

### Building Bottles for Multiple macOS Versions

```bash
# On macOS 15 (Sequoia)
make bottle
# → docsucker-1.0.0.arm64_sequoia.bottle.tar.gz

# On macOS 14 (Sonoma)
make bottle
# → docsucker-1.0.0.arm64_sonoma.bottle.tar.gz

# On macOS 13 (Ventura)
make bottle
# → docsucker-1.0.0.arm64_ventura.bottle.tar.gz
```

---

## Testing Locally

### Test Formula Before Publishing

```bash
# 1. Audit formula
brew audit --new-formula Formula/docsucker.rb

# 2. Style check
brew style Formula/docsucker.rb

# 3. Install from formula
brew install --build-from-source Formula/docsucker.rb

# 4. Run tests
brew test docsucker

# 5. Verify installation
cupertino --version
cupertino-mcp --version

# 6. Test functionality
cupertino crawl --max-pages 1 --output-dir /tmp/test-docs

# 7. Uninstall
brew uninstall docsucker
```

### Common Issues

**Issue: Swift version mismatch**

```bash
# Check Swift version
swift --version

# Update Xcode Command Line Tools
xcode-select --install
```

**Issue: Build fails with "cannot find module"**

```bash
# Clean and rebuild
cd Packages
swift package clean
brew install --build-from-source --verbose Formula/docsucker.rb
```

**Issue: Tests fail**

```bash
# Run tests manually
cd Packages
swift test

# Check specific test
swift test --filter testDownloadRealAppleDocPage
```

---

## Publishing Options

### Option 1: Personal Tap (Easiest)

Create your own Homebrew tap for easy maintenance and distribution.

#### Step 1: Create Tap Repository

```bash
# Create repository on GitHub: homebrew-tap
# Clone it locally
git clone https://github.com/YOUR_USERNAME/homebrew-tap.git
cd homebrew-tap

# Create Formula directory
mkdir -p Formula
```

#### Step 2: Add Formula

```bash
# Copy formula
cp /path/to/docsucker.rb Formula/

# Commit
git add Formula/docsucker.rb
git commit -m "Add docsucker formula"
git push
```

#### Step 3: Users Install

```bash
# Users tap your repository
brew tap YOUR_USERNAME/tap

# Install docsucker
brew install docsucker

# Update
brew update
brew upgrade docsucker
```

#### Step 4: Release Updates

```bash
# 1. Update version in formula
# 2. Update URL and SHA256
# 3. Commit and push
git add Formula/docsucker.rb
git commit -m "docsucker 1.1.0"
git push

# Users get updates with:
brew update
brew upgrade docsucker
```

### Option 2: Submit to Homebrew Core (Advanced)

Submit to official [homebrew-core](https://github.com/Homebrew/homebrew-core) for wider distribution.

#### Requirements

- Project must be stable and well-maintained
- Must have a tagged release on GitHub
- Formula must pass all audits
- Must build bottles for all supported macOS versions
- Must have comprehensive tests

#### Process

1. **Fork homebrew-core**:
   ```bash
   # Fork https://github.com/Homebrew/homebrew-core on GitHub
   git clone https://github.com/YOUR_USERNAME/homebrew-core.git
   cd homebrew-core
   ```

2. **Create formula**:
   ```bash
   # Use Homebrew's formula creator
   brew create https://github.com/YOUR_USERNAME/cupertino/archive/refs/tags/v1.0.0.tar.gz

   # Edit the generated formula
   brew edit docsucker
   ```

3. **Test thoroughly**:
   ```bash
   brew audit --new-formula --online docsucker
   brew style docsucker
   brew install --build-from-source docsucker
   brew test docsucker
   brew linkage docsucker
   ```

4. **Build bottles**:
   ```bash
   brew install --build-bottle docsucker
   brew bottle docsucker
   ```

5. **Submit PR**:
   ```bash
   git add Formula/docsucker.rb
   git commit -m "docsucker 1.0.0 (new formula)"
   git push origin main

   # Create PR on GitHub
   ```

6. **Wait for review** - Homebrew maintainers will review and merge if approved

### Option 3: Cask for Pre-built Binaries (Alternative)

If you want to distribute pre-built binaries instead of building from source:

```ruby
cask "cupertino" do
  version "1.0.0"
  sha256 "SHA256_OF_ZIP"

  url "https://github.com/YOUR_USERNAME/cupertino/releases/download/v#{version}/docsucker-#{version}-macos.zip"
  name "Cupertino"
  desc "Apple Documentation Crawler & MCP Server"
  homepage "https://github.com/YOUR_USERNAME/cupertino"

  binary "cupertino"
  binary "cupertino-mcp"
end
```

---

## Complete Workflow

### Initial Setup

```bash
# 1. Tag release in Git (from root directory)
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0

# 2. Create release archive
make archive
# Creates: Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# 3. Upload to GitHub Releases
# Go to: https://github.com/YOUR_USERNAME/cupertino/releases/new
# - Tag: v1.0.0
# - Title: Cupertino 1.0.0
# - Upload: Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# 4. Get SHA256
shasum -a 256 Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz
# Copy this hash

# 5. Create formula
# Create homebrew-tap repository on GitHub
git clone https://github.com/YOUR_USERNAME/homebrew-tap.git
cd homebrew-tap
mkdir -p Formula

# 6. Create Formula/docsucker.rb (use template above)
# - Set URL to GitHub release tarball
# - Set SHA256 from step 4

# 7. Commit formula
git add Formula/docsucker.rb
git commit -m "Add docsucker 1.0.0"
git push

# 8. Test installation
brew tap YOUR_USERNAME/tap
brew install docsucker --build-from-source
brew test docsucker

# 9. Build and upload bottle (optional)
brew install --build-bottle docsucker
brew bottle docsucker
# Upload bottle to GitHub Releases
# Update formula with bottle SHA256

# 10. Done! Users can now install with:
brew tap YOUR_USERNAME/tap
brew install docsucker
```

### Release Updates

```bash
# 1. Update version in code
# - Packages/Sources/CupertinoShared/Configuration.swift
# - Update version to 1.1.0

# 2. Commit and tag (from root directory)
git add .
git commit -m "Release 1.1.0"
git tag -a v1.1.0 -m "Release 1.1.0"
git push origin v1.1.0

# 3. Create archive
make archive
# Creates: Packages/docsucker-1.1.0-arm64-apple-darwin.tar.gz

# 4. Upload to GitHub Releases

# 5. Update formula
cd homebrew-tap
# Update Formula/docsucker.rb:
#   - url: v1.1.0
#   - sha256: new hash
git add Formula/docsucker.rb
git commit -m "docsucker 1.1.0"
git push

# 6. Users upgrade with:
brew update
brew upgrade docsucker
```

---

## Best Practices

### Versioning

- Use semantic versioning (1.0.0, 1.1.0, 2.0.0)
- Tag releases in Git
- Update version in code before tagging
- Create GitHub releases for each version

### Formula Maintenance

- Keep formula simple and readable
- Test on multiple macOS versions
- Provide helpful caveats for post-install setup
- Include comprehensive tests
- Document dependencies clearly

### Documentation

- Maintain clear README files
- Include installation instructions
- Provide usage examples
- Document MCP integration steps

### Testing

```bash
# Always test before publishing:
brew audit --new-formula Formula/docsucker.rb
brew style Formula/docsucker.rb
brew install --build-from-source Formula/docsucker.rb
brew test docsucker
brew linkage docsucker

# Test on clean system (VM or container)
```

---

## Example: Complete First Release

```bash
# In cupertino repository (root directory)
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0

make archive
# → Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz

# Upload to GitHub Releases
# https://github.com/YOUR_USERNAME/cupertino/releases/new

# Get SHA256
shasum -a 256 Packages/docsucker-1.0.0-arm64-apple-darwin.tar.gz
# → abc123def456... (copy this)

# Create tap repository
git clone https://github.com/YOUR_USERNAME/homebrew-tap.git
cd homebrew-tap
mkdir -p Formula

# Create Formula/docsucker.rb with template above
# Set:
#   url "https://github.com/YOUR_USERNAME/cupertino/archive/refs/tags/v1.0.0.tar.gz"
#   sha256 "abc123def456..."

git add Formula/docsucker.rb
git commit -m "Add docsucker 1.0.0"
git push

# Test installation
brew tap YOUR_USERNAME/tap
brew install docsucker
cupertino --version  # Should show 1.0.0
cupertino-mcp --version

# Success! Users can now install with:
# brew tap YOUR_USERNAME/tap
# brew install docsucker
```

---

## Resources

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Homebrew Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)
- [Creating Taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [Homebrew Bottles](https://docs.brew.sh/Bottles)
- [Swift in Homebrew](https://github.com/Homebrew/homebrew-core/search?q=language%3ARuby+swift&type=code)

---

## Summary

### Quick Reference

```bash
# Create tap (one-time)
git clone https://github.com/YOUR_USERNAME/homebrew-tap.git
cd homebrew-tap
mkdir -p Formula

# Each release:
1. Tag in Git: git tag v1.0.0 && git push --tags
2. Build: cd Packages && make archive
3. Upload: GitHub Releases
4. Get hash: shasum -a 256 *.tar.gz
5. Update: Formula/docsucker.rb (url, sha256)
6. Commit: git add . && git commit -m "1.0.0" && git push

# Users install:
brew tap YOUR_USERNAME/tap
brew install docsucker
```

### Files Needed

- `Formula/docsucker.rb` - Homebrew formula
- GitHub release with source tarball
- (Optional) Pre-built bottles

### Installation Methods

1. **Source**: `brew install --build-from-source docsucker`
2. **Bottle**: `brew install docsucker` (with bottles)
3. **Manual**: `make install` (from this Makefile)

Choose the method that works best for your distribution needs!
