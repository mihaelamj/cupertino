# Cupertino Code Style Guide

This document outlines the code style and formatting rules for the Cupertino project, derived from `.swiftlint.yml` and `.swiftformat` configurations.

## Zero Tolerance Policy

**CRITICAL RULE**: Never accept SwiftLint warnings or errors.

- **Zero errors**: Mandatory - build must have zero errors
- **Zero warnings**: Mandatory - all warnings must be fixed
- **If a warning is genuinely impossible to fix**: Disable it in the source file with `swiftlint:disable` and provide a clear comment explaining why
- **Never tolerate**: "It's just a warning" - fix it or disable it with justification

Example of acceptable disable:
```swift
// swiftlint:disable file_length
// Justification: This file handles complex HTML parsing with many edge cases.
// Splitting would reduce cohesion. File length is acceptable given functionality.
```

## SwiftFormat Rules

### Indentation & Spacing
- **Indent**: 4 spaces (not tabs)
- **Max line width**: 180 characters
- **Else position**: Same line as closing brace
- **Indent case**: false (case statements not indented)

### Formatting
- **Allman braces**: false (opening brace on same line)
- **Closing paren**: balanced
- **Fragment**: false (format whole files only)
- **Operator func**: no-space (e.g., `func +(_ lhs:...`)
- **No space operators**: `..<` and `...` (e.g., `0..<10`)

### Collections & Arguments
- **Commas**: Always include trailing commas in multi-line collections
- **Wrap arguments**: before-first
- **Wrap collections**: before-first
- **Wrap parameters**: before-first
- **Strip unused args**: closure-only

### Literals
- **Binary grouping**: none
- **Decimal grouping**: none
- **Hex grouping**: none
- **Octal grouping**: none
- **Hex literal case**: lowercase
- **Exponent case**: lowercase
- **Exponent grouping**: disabled
- **Fraction grouping**: disabled

### Imports & Headers
- **Import grouping**: alphabetized
- **Header**: ignore (don't modify file headers)

### Other
- **Trailing closures**: enabled
- **Self required**: (empty - minimal use of explicit self)
- **Conflict markers**: reject
- **ifdef**: no-indent

### Disabled Rules
- `hoistPatternLet`: Keep let/var in pattern position
- `wrapMultilineStatementBraces`: Don't wrap multiline statement braces
- `extensionAccessControl`: Don't move access control to extensions

## SwiftLint Rules

### Disabled Rules
- `opening_brace`: (custom brace style allowed)
- `operator_whitespace`: (handled by SwiftFormat)
- `orphaned_doc_comment`: (allowed)

### Opt-in Rules
- `empty_count`: Prefer `.isEmpty` over `.count == 0`
- `shorthand_optional_binding`: Use `if let foo` instead of `if let foo = foo`
- `weak_delegate`: Delegates should be weak

### Length Limits
- **Line length**: 180 characters (warning and error)
- **File length**: 1000 lines (warning and error)
- **Function body length**: 40 lines (warning), 100 lines (error) - SwiftLint defaults
- **Type body length**: 300 lines (warning and error)
- **Function parameter count**: 5 parameters (warning)
- **Large tuple**: 3 elements (warning), 10 elements (error)

**Important**: Never modify `.swiftlint.yml` or `.swiftformat` configuration files. If a rule must be bypassed for exceptional cases:
- Use `// swiftlint:disable:next rule_name` or `// swiftformat:disable:next rule_name`
- Include a clear explanation of why the rule is disabled
- Explain why the code cannot be refactored to comply with the rule

### Complexity
- **Cyclomatic complexity**: 20 (warning), ignores case statements

### Naming
- **Identifier name**:
  - Min length: 2 characters
  - Max length: 90 characters (warning and error)
  - Allowed symbols: `_`
  - Excluded: `iO, id, vc, x, y, i, pi, d`

- **Type name**:
  - Min length: 2 characters
  - Max length: 90 characters
  - Allowed symbols: `_`
  - Excluded: `iosAppApp, macAppApp`

### Nesting
- **Type level**: 3 levels (warning and error)
- **Function level**: 5 levels (warning and error)

### Other Rules
- **Trailing comma**: mandatory in multi-line collections
- **Force cast**: warning (avoid when possible)
- **Legacy constant**: error (use #colorLiteral, #imageLiteral)
- **Legacy constructor**: error (use modern initializers)

### Custom Rules

#### `combine_assign_to_self`
- **Error**: Using `.assign(to:on:self)` creates retain cycle
- **Fix**: Use `assignNoRetain(to:on:self)` instead

#### `duplicate_remove_duplicates`
- **Error**: ViewStore's publisher already does `removeDuplicates()`
- **Fix**: Don't call `.removeDuplicates()` on ViewStore publishers

#### `dont_scale_to_zero`
- **Error**: Don't scale down to 0 (causes singular matrix warnings)
- **Fix**: Use non-zero scale values

#### `use_data_constructor_over_string_member`
- **Error**: Don't use `String.data(using:.utf8)`
- **Fix**: Use `Data(string.utf8)` (non-optional, guaranteed encodable)

#### `tca_explicit_generics_reducer`
- **Error**: Missing explicit generics in Reducer
- **Fix**: Use `Reduce<State, Action>` instead of `Reduce {`

#### `tca_scope_unused_closure_parameter`
- **Error**: Unused closure parameter in `.scope(state:)`
- **Fix**: Explicitly use parameter name (ensures correct state mutation)

#### `tca_use_observe_viewstore_api`
- **Error**: Using old `ViewStore(store.scope(...))`
- **Fix**: Use modern `observe:` API

## Excluded Paths

The following paths are excluded from formatting/linting:
- `Stage/`
- `Tasks/.build/`
- `ThirdParty/`
- `**/SwiftGen/*`
- `**/Sourcery/*`
- `Frameworks/swift-composable-architecture/`
- `**.generated.swift`
- `*.generated` files
- `Packages/Tests/**` (for SwiftLint - tests use force unwrapping)

## Example Code

```swift
// ✅ Good: Trailing commas, proper indentation, alphabetized imports
import DocsuckerCore
import DocsuckerLogging
import Foundation

actor MyActor {
    private let config: Config

    init(config: Config) {
        self.config = config
    }

    func processItems(_ items: [String]) async throws {
        let filteredItems = items.filter { item in
            item.count > 0
        }

        let results = [
            "first",
            "second",
            "third",
        ]

        // Use isEmpty instead of count == 0
        guard !results.isEmpty else { return }

        // Shorthand optional binding
        if let config {
            print(config)
        }

        // Data constructor
        let data = Data("hello".utf8)

        // Range operators without spaces
        for i in 0..<10 {
            print(i)
        }
    }
}
```

## Notes

- Always run SwiftFormat before committing code
- SwiftLint runs in pre-commit hooks
- Keep functions under 100 lines when practical
- Keep type bodies under 300 lines
- Use explicit type annotations for public APIs
- Prefer value types (struct/enum) over reference types (class)
- Use actors for thread-safe state management
