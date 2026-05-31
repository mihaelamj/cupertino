# --wrapper

Property wrapper name to match (with or without the leading `@`). Required.

## Synopsis

```bash
cupertino search-property-wrappers --wrapper <name>
```

## Description

Finds symbols whose declaration uses the named property wrapper. The leading `@`
is optional: `State` and `@State` are equivalent.

## Default

None. This option is required.

## Example

```bash
cupertino search-property-wrappers --wrapper State --framework swiftui
cupertino search-property-wrappers --wrapper @ObservedObject
```
