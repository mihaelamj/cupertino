# list_samples

List all indexed Apple sample code projects.

## Synopsis

```json
{
  "name": "list_samples",
  "arguments": {}
}
```

## Description

Returns a list of all indexed sample code projects with their titles, descriptions, and frameworks.

## Parameters

None required.

## Response

Returns a list of sample projects with metadata:

```markdown
# Sample Code Projects

Found **606** projects:

## 1. Building a Document-Based App with SwiftUI
- **Project ID:** building-a-document-based-app-with-swiftui
- **Frameworks:** SwiftUI, UIKit
- **Files:** 12

## 2. Fruta: Building a Feature-Rich App with SwiftUI
- **Project ID:** fruta-building-a-feature-rich-app-with-swiftui
- **Frameworks:** SwiftUI, WidgetKit
- **Files:** 45
...
```

## Examples

### List All Projects

```json
{}
```

## See Also

- [search_samples](../search_samples/) - Search sample code
- [read_sample](../read_sample/) - Read sample README
- [read_sample_file](../read_sample_file/) - Read specific source file
