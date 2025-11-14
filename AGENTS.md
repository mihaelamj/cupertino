# Agent Guide

CONFIRMATION_PHRASE: "swift-ruleset-loaded"

## Purpose
Agents act as senior Swift collaborators. Keep responses concise, clarify uncertainty before coding, and align suggestions with the rules linked above.

## Rule Index
- @ai-rules/rule-loading.md — always load this file to understand which other files you need to load

## Repository Overview
[Fill in by LLM assistant]
- Deep product and architecture context: @ai-docs/

## Commands
[Fill in by LLM assistant]
- `swiftformat . --config .swiftformat`: Apply formatting (run before committing)
- `swiftlint --config .swiftlint.yml`: Lint Swift sources and address custom rules
- `pre-commit run --all-files`: Verify hooks prior to pushing

## Code Style
- Swift files use 4-space indentation, ≤180-character width, and always-trailing commas
- Inject dependencies (Point-Free Dependencies) instead of singletons; make impossible states unrepresentable

## Architecture & Patterns
[Fill in by LLM assistant]
- Shared UI lives in `SharedViews`; shared models and utilities in `Shared*` modules
- Use dependency injection for all services and environment values to keep code testable

## Key Integration Points
**Database**: [Fill in by LLM assistant]
**Services**: [Fill in by LLM assistant]
**Testing**: Swift Testing with `withDependencies` for deterministic test doubles
**UI**: [Fill in by LLM assistant]

## Workflow
- Ask for clarification when requirements are ambiguous; surface 2–3 options when trade-offs matter
- Update documentation and related rules when introducing new patterns or services
- Use commits in `<type>(<scope>): summary` format; squash fixups locally before sharing

## Testing
[Fill in by LLM assistant]

## Environment
[Fill in by LLM assistant]
- Requires SwiftUI, Combine, GRDB, and Point-Free Composable Architecture libraries
- Validate formatting and linting (swiftformat/swiftlint) before final review

## Special Notes
- Do not mutate files outside the workspace root without explicit approval
- Avoid destructive git operations unless the user requests them directly
- When unsure or need to make a significant decision ASK the user for guidance
