# --constraint

Generic-parameter constraint type to match. Required.

## Synopsis

```bash
cupertino search-generics --constraint <type>
```

## Description

Finds symbols with a generic parameter constrained to the named type, e.g.
`View`, `Hashable`, `Sendable`, `Codable`.

## Default

None. This option is required.

## Example

```bash
cupertino search-generics --constraint Hashable
cupertino search-generics --constraint View --framework swiftui
```
