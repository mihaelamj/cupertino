# --protocol

Protocol name to find conformers of. Required.

## Synopsis

```bash
cupertino search-conformances --protocol <name>
```

## Description

Finds symbols that conform to the named protocol, e.g. `View`, `Codable`,
`Hashable`, `Sendable`.

## Default

None. This option is required.

## Example

```bash
cupertino search-conformances --protocol Codable
cupertino search-conformances --protocol View --framework swiftui
```
