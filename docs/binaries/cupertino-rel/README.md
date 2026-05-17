# cupertino-rel

Release automation tool for Cupertino maintainers.

## Synopsis

```bash
cupertino-rel [options] [subcommand]
```

## Options

| Option | Description |
|--------|-------------|
| [--version](option (--)/version.md) | Show version information |
| -h, --help | Show help information |

## Description

Automates the complete Cupertino release workflow:

1. Update version in `Constants.swift`, `README.md`, `CHANGELOG.md`
2. Commit version bump
3. Create and push git tag
4. Wait for GitHub Actions to build
5. Upload databases via `cupertino release`
6. Update Homebrew formula

## Requirements

- `GITHUB_TOKEN` environment variable with `repo` scope

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `full` | Run the complete release workflow (default) |
| `bump` | Bump version in all required files |
| `tag` | Commit changes and create git tag |
| `databases` | Package and upload databases to GitHub Releases |
| `homebrew` | Update Homebrew formula with new version |
| `docs-update` | Update documentation databases and bump minor version |

## Usage

### Full Release

```bash
# Run complete release workflow (major/minor/patch)
cupertino-rel full --bump-type patch
cupertino-rel full --bump-type minor
cupertino-rel full --bump-type major
```

### Individual Steps

```bash
# Bump version only
cupertino-rel bump --type patch

# Create and push tag
cupertino-rel tag

# Upload databases
cupertino-rel databases

# Update Homebrew formula
cupertino-rel homebrew
```

### Documentation Update

```bash
# Update docs databases and bump minor version
cupertino-rel docs-update
```

## Version Bump Locations

The `bump` command updates version in:

- `Sources/Shared/Constants.swift` - App version constant
- `README.md` - Version badge and references
- `CHANGELOG.md` - New version section

## See Also

- [CONTRIBUTING.md](../../../CONTRIBUTING.md) - Development workflow
- [DEPLOYMENT.md](../../DEPLOYMENT.md) - Deployment and CI/CD
