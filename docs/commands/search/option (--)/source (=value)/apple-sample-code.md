# apple-sample-code

Apple sample code projects source

## Synopsis

```bash
cupertino search <query> --source apple-sample-code
```

## Description

Filters search results to only include Apple's official sample code projects. These are working code examples that demonstrate Apple technologies and APIs.

## Content

- **Project titles** and descriptions
- **Framework associations**
- **Download URLs**
- **Technology tags**

## Typical Size

- **~600 projects** indexed
- **Bundled** (no fetch required)
- Updated periodically by maintainers

## Examples

### Search for SwiftUI Samples
```bash
cupertino search "SwiftUI" --source apple-sample-code
```

### Search for ARKit Samples
```bash
cupertino search "ARKit" --source apple-sample-code
```

### Search for Machine Learning
```bash
cupertino search "Core ML" --source apple-sample-code
```

## URI Format

Results use the `apple-sample-code://` URI scheme:

```
apple-sample-code://{project_id}
```

## How to Populate

The sample code catalog is **bundled** with Cupertino and indexed automatically:

```bash
# Just build the index (sample code included automatically)
cupertino save
```

To fetch full sample code (optional):

```bash
# Fetch sample code projects
cupertino fetch --type code

# Rebuild index
cupertino save
```

## Use Cases

- **Learning** - Find working examples of APIs
- **Reference** - See Apple's recommended patterns
- **Starting points** - Base for new projects
- **Best practices** - Official implementation examples

## Notes

- Bundled catalog - no download required
- Metadata only (not full project code by default)
- Links to downloadable Xcode projects
- Great companion to API documentation
