# Release Process

## Development Setup (Current)
- Using **symlinks** to `/usr/local/bin/`
- Auto-updates when running `make update`
- Good for rapid development

## Production Release Workflow

### 1. Save Current Stable Version
```bash
# Copy working binaries to versions folder
VERSION=0.1.1
mkdir -p /Volumes/Code/DeveloperExt/appledocsucker/versions/$VERSION
cp .build/release/cupertino /Volumes/Code/DeveloperExt/appledocsucker/versions/$VERSION/
cp .build/release/cupertino-mcp /Volumes/Code/DeveloperExt/appledocsucker/versions/$VERSION/
```

### 2. Bump Version for Development
- Update version in `Sources/CupertinoCLI/main.swift`
- Update version in `Sources/CupertinoMCP/main.swift`
- Update `VERSION` file
- Update `CHANGELOG.md`

### 3. Continue Development
```bash
make update  # Builds new version via symlinks
```

### 4. Production Install (when ready)
```bash
# Remove symlinks
sudo rm /usr/local/bin/cupertino
sudo rm /usr/local/bin/cupertino-mcp

# Install stable version (copies binaries)
sudo make install

# Verify
cupertino --version  # Should show new version
```

## Current Versions
- **v0.1.1**: Stable (saved in `versions/0.1.1/`)
  - Basic crawling, FTS5 search, MCP server
  
- **v0.1.2**: Development (symlinked)
  - Added state persistence & auto-resume
  - `--resume` flag
  - Enhanced progress logging

## Rollback to Stable
```bash
sudo rm /usr/local/bin/cupertino*
sudo cp /Volumes/Code/DeveloperExt/appledocsucker/versions/0.1.1/* /usr/local/bin/
```

