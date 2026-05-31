# packages

Swift package metadata source

## Synopsis

```bash
cupertino search <query> --source packages
```

## Description

Filters search results to only include Swift package metadata. This is a bundled catalog of Swift packages from the Swift Package Index.

## Content

- **Package names** and descriptions
- **Repository URLs**
- **Stars and popularity metrics**
- **License information**
- **Keywords and categories**

## Typical Size

- **9,600+ packages** indexed
- **Bundled** (no fetch required)
- Updated periodically by maintainers

## Examples

### Search for Networking Packages
```bash
cupertino search "networking" --source packages
```

### Search for Database Packages
```bash
cupertino search "database" --source packages
```

### Search by Author
```bash
cupertino search "vapor" --source packages
```

## URI Format

Results use the `packages://` URI scheme:

```
packages://{package_name}
```

## How to Populate

The packages catalog is **bundled** with Cupertino and indexed automatically:

```bash
# Just build the index (packages included automatically)
cupertino save --source packages
```

To fetch package source archives (optional):

```bash
# Fetch source archives for priority packages (#217). Post-#1108 stage 2
# is the default, so no flag is needed.
cupertino fetch --source packages

# Rebuild index
cupertino save --source packages
```

## Priority Packages

36 curated high-priority packages are included:
- **31 Apple official packages** (swift-nio, swift-argument-parser, etc.)
- **5 essential ecosystem packages** (Alamofire, etc.)

## Notes

- Bundled catalog - no download required
- Metadata only (not full README content by default)
- Updated periodically in Cupertino releases
- Great for discovering Swift packages
