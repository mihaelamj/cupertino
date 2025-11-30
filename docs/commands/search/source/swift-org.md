# swift-org

Swift.org documentation source

## Synopsis

```bash
cupertino search <query> --source swift-org
```

## Description

Filters search results to only include Swift.org documentation. This covers the official Swift language website content, including guides, blog posts, and community resources.

## Content

- **Getting started guides**
- **Swift blog posts**
- **Community resources**
- **Download and installation guides**
- **Contributing guidelines**

## Typical Size

- **~500 pages** indexed
- **~100 MB** on disk

## Examples

### Search Swift.org Content
```bash
cupertino search "getting started" --source swift-org
```

### Search for Installation
```bash
cupertino search "install" --source swift-org
```

### Search Community Content
```bash
cupertino search "contribute" --source swift-org
```

## URI Format

Results use the `swift-org://` URI scheme:

```
swift-org://{page_path}
```

## How to Populate

```bash
# Fetch Swift.org docs (5-10 minutes)
cupertino fetch --type swift

# Build index
cupertino save
```

## Notes

- Fetched from swift.org
- Clean HTML structure
- Good for Swift ecosystem information
- Includes blog posts and announcements
