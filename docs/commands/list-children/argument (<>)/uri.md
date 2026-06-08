# uri

Apple documentation URI or topic-group fragment URI.

## Usage

```bash
cupertino list-children <uri>
```

## Accepted Forms

- `apple-docs://swiftui`
- `apple-docs://swiftui#Essentials`
- `https://developer.apple.com/documentation/swiftui`

Fragment URIs identify non-document topic headings returned by a previous `list-children` call. Pass the fragment URI back to the command to list documents inside that heading.
