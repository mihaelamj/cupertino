# --kind

Restrict results to a single symbol kind.

## Synopsis

```bash
cupertino search-symbols --kind <kind>
```

## Description

Limits matches to one declaration kind.

## Values

`class`, `struct`, `enum`, `protocol`, `actor`, `typealias`, `macro`, `method`,
`function`, `property`, `initializer`, `subscript`, `case`, `operator`.

## Default

None (match every kind).

## Example

```bash
cupertino search-symbols --kind protocol --framework swiftui
cupertino search-symbols --query Task --kind struct
```
