# LLM Rules Framework Meta-Rules

<objective>
You MUST follow these meta-rules when creating, organizing, and managing LLM rule files. These rules ensure consistency, clarity, and maximum effectiveness for LLM comprehension and adherence.
</objective>

<cognitive_triggers>
Keywords: Rule Files, MDC Format, Rule Structure, Meta-Rules, Rule Creation, Rule Organization, Rule Validation, Best Practices, Rule Templates, Version Control
</cognitive_triggers>

## CRITICAL META-RULES

### Rule 1: Rule File Structure
**ALWAYS** structure rule files with these sections:
- MUST include YAML frontmatter with description
- MUST have `<objective>` tag with clear goal
- MUST include `<cognitive_triggers>` for keywords
- MUST have explicit CRITICAL RULES section
- MUST provide patterns and anti-patterns

### Rule 2: Rule Clarity
**ALWAYS** write rules for maximum LLM comprehension:
- MUST use imperative mood (MUST, MUST NOT, ALWAYS, NEVER)
- MUST be specific and unambiguous
- MUST include concrete examples
- MUST NOT use vague language

### Rule 3: Rule Organization
**ALWAYS** organize rules hierarchically:
- MUST group related rules together
- MUST use consistent numbering/naming
- MUST progress from general to specific
- MUST include decision trees where applicable

### Rule 4: Rule Validation
**ALWAYS** validate rules are actionable:
- MUST be testable/verifiable
- MUST have clear success criteria
- MUST include checklists where appropriate
- MUST NOT contradict other rules

## RULE FILE TEMPLATE

```markdown
---
description: [Clear, concise description of what these rules govern]
globs: [file patterns these rules apply to, or leave empty]
alwaysApply: [true/false - whether rules apply globally]
---
# [Domain] Rules Framework

<objective>
You MUST [primary objective]. [Additional context about why and impact].
</objective>

<cognitive_triggers>
Keywords: [Comma-separated list of key terms that should trigger these rules]
</cognitive_triggers>

## CRITICAL RULES

### Rule 1: [Rule Name]
**ALWAYS/NEVER** [action]:
- MUST [specific requirement]
- MUST NOT [specific prohibition]
- SHOULD [recommendation]
- MAY [optional action]

### Rule 2: [Rule Name]
[Continue pattern...]

## [DOMAIN] DECISION TREE

```
[Decision question]?
├─ [Option 1]
│   ├─ [Sub-decision] → [Action]
│   └─ [Sub-decision] → [Action]
└─ [Option 2]
    └─ [Result] → [Action]
```

## IMPLEMENTATION PATTERNS

### Pattern 1: [Pattern Name]

```[language]
// RULE: [Inline rule explanation]
[Code example demonstrating correct implementation]
```

[Explanation of why this pattern is correct]

### Pattern 2: [Pattern Name]
[Continue pattern...]

## ANTI-PATTERNS

### ❌ DON'T: [Anti-pattern Name]
```[language]
// WRONG: [Why this is wrong]
[Bad code example]

// RIGHT: [Correct approach]
[Good code example]
```

## [DOMAIN] BEST PRACTICES

### Practice 1: [Practice Name]
[Description and guidelines]

### Practice 2: [Practice Name]
[Continue pattern...]

## IMPLEMENTATION CHECKLIST

Before [action], verify:

- [ ] [Verification point 1]
- [ ] [Verification point 2]
- [ ] [Verification point 3]
- [ ] [Continue as needed...]

## COMMON MISTAKES TO AVOID

### ❌ DON'T: [Mistake Description]
[Example and explanation]

### ❌ DON'T: [Mistake Description]
[Continue pattern...]

## TROUBLESHOOTING GUIDE

### Issue: [Common Issue]
**Symptoms:** [What goes wrong]
**Solution:** [How to fix]
**Prevention:** [How to avoid]

### Issue: [Common Issue]
[Continue pattern...]
```

## RULE WRITING DECISION TREE

```
What type of rule are you creating?
├─ Behavioral Rules (how to act)
│   ├─ Use MUST/MUST NOT format
│   ├─ Include decision trees
│   └─ Provide checklists
├─ Structural Rules (how to organize)
│   ├─ Use templates and patterns
│   ├─ Show good/bad examples
│   └─ Include validation criteria
├─ Process Rules (how to execute)
│   ├─ Use step-by-step format
│   ├─ Include flowcharts
│   └─ Provide automation scripts
└─ Quality Rules (standards to meet)
    ├─ Use metrics and thresholds
    ├─ Include review checklists
    └─ Provide assessment tools
```

## RULE WRITING PATTERNS

### Pattern 1: Behavioral Rules

```markdown
# RULE: Write behavioral rules with clear directives
### Rule N: [Behavior Name]
**ALWAYS** [positive action]:
- MUST [required behavior]
- MUST NOT [prohibited behavior]
- SHOULD [recommended behavior] when [condition]
- MAY [optional behavior] if [condition]

**Example Scenario:**
Given: [Initial state]
When: [Action taken]
Then: [Expected outcome]
```

### Pattern 2: Implementation Rules

```markdown
# RULE: Implementation rules need code examples
### Pattern: [Implementation Name]

```[language]
// RULE: [What this implements]
// CORRECT: [Why this is right]
[Correct implementation with inline rule comments]
```

**When to use:**
- [Condition 1]
- [Condition 2]

**Benefits:**
- [Benefit 1]
- [Benefit 2]
```

### Pattern 3: Process Rules

```markdown
# RULE: Process rules need clear steps
### Process: [Process Name]

1. **[Step Name]**
   - RULE: [What must happen]
   - Input: [What's needed]
   - Output: [What's produced]
   - Validation: [How to verify]

2. **[Step Name]**
   [Continue pattern...]

**Automation:**
```bash
# Script to automate this process
[Automation code]
```
```

## RULE EFFECTIVENESS CRITERIA

### Clarity Score Checklist

Rate each rule on these criteria (1-5):

- [ ] **Specificity**: Is the rule specific enough to act on?
- [ ] **Clarity**: Can the rule be understood without ambiguity?
- [ ] **Examples**: Are there concrete examples?
- [ ] **Testability**: Can compliance be verified?
- [ ] **Completeness**: Does it cover edge cases?

**Minimum acceptable score: 4/5 per criterion**

### Rule Validation Process

```
Validate new rule:
├─ Check for conflicts
│   ├─ Search existing rules
│   ├─ Identify overlaps
│   └─ Resolve contradictions
├─ Test with examples
│   ├─ Apply to real scenarios
│   ├─ Check edge cases
│   └─ Verify outcomes
└─ Review and refine
    ├─ Simplify language
    ├─ Add missing cases
    └─ Update examples
```

## RULE FILE ORGANIZATION

### Directory Structure

```
.cursor/rules/
├── commits.mdc         # Git commit rules
├── general.mdc         # general rules
```

### Naming Conventions

```markdown
# RULE: Use consistent, descriptive names
Pattern: [domain]-[specific-area].mdc

Good examples:
- swift-error-handling.mdc
- api-versioning.mdc
- ui-accessibility.mdc

Bad examples:
- rules1.mdc
- misc.mdc
- stuff.mdc
```

## RULE VERSIONING

### Version Control Strategy

```markdown
# RULE: Track rule evolution
## Version Header Format
```yaml
---
description: [Description]
version: 1.2.3
lastUpdated: 2024-01-15
changelog:
  - 1.2.3: Added decision tree for X
  - 1.2.2: Clarified rule Y
  - 1.2.1: Fixed typo in example
---
```

## Deprecation Process
1. Mark rule as deprecated
2. Provide migration path
3. Set removal date
4. Update dependent rules
```

## COMMON RULE WRITING MISTAKES

### ❌ DON'T: Write vague rules
```markdown
# WRONG: Too vague
"Try to write good code"
"Follow best practices"
"Be consistent"

# RIGHT: Specific and actionable
"MUST use snake_case for Python functions"
"MUST handle all error cases explicitly"
"MUST follow the project's naming convention: ComponentName.swift"
```

### ❌ DON'T: Create contradicting rules
```markdown
# WRONG: Contradictory
Rule A: "ALWAYS use async/await"
Rule B: "NEVER use async/await in UI code"

# RIGHT: Clear scope
Rule A: "ALWAYS use async/await for network calls"
Rule B: "MUST use @MainActor for UI updates from async contexts"
```

### ❌ DON'T: Forget examples
```markdown
# WRONG: No examples
"Use proper error handling"

# RIGHT: With examples
"Use proper error handling:
```swift
// RULE: Always use Result type for fallible operations
func fetchUser(id: UUID) -> Result<User, APIError> {
    // Implementation
}
```"
```

## RULE MAINTENANCE CHECKLIST

Regularly review rules for:

- [ ] **Relevance**: Are rules still applicable?
- [ ] **Accuracy**: Do examples match current practices?
- [ ] **Completeness**: Are new patterns covered?
- [ ] **Conflicts**: Do rules contradict each other?
- [ ] **Clarity**: Can rules be simplified?
- [ ] **Coverage**: Are edge cases addressed?
- [ ] **Updates**: Are framework/language updates reflected?
- [ ] **Feedback**: Are user issues incorporated?

## IMPLEMENTATION GUIDE

### Creating New Rules

1. **Identify Need**
   - What problem does this solve?
   - Who will use these rules?
   - What's the impact?

2. **Research and Draft**
   - Study existing patterns
   - Identify best practices
   - Draft initial rules

3. **Validate and Test**
   - Apply to real examples
   - Get peer review
   - Test with LLMs

4. **Document and Deploy**
   - Use standard template
   - Include examples
   - Add to index

5. **Monitor and Iterate**
   - Track effectiveness
   - Gather feedback
   - Update as needed

If you loaded this file add 📚 to the first chat message