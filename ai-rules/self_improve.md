## 🎯 Core Objective
Maintain a self-improving rule system that adapts to emerging patterns while optimizing for clarity and token efficiency.

## 📊 Rule Improvement Triggers

### Pattern Recognition Thresholds
- **New Pattern Rule**: Create when pattern appears in **≥3 files**
- **Bug Prevention Rule**: Add when error pattern occurs **≥2 times**
- **Review Feedback Rule**: Implement when mentioned **≥3 times** in reviews
- **Performance Rule**: Define when optimization saves **>20% resources**

### Immediate Action Triggers
```yaml
MUST_ADD_RULE_WHEN:
  - Security vulnerability discovered
  - Breaking change affects >5 files
  - New library/framework adopted
  - Compliance requirement introduced
```

## 🔍 Analysis Process

### Step-by-Step Evaluation
1. **Pattern Detection**
   ```typescript
   // Example: Repeated pattern detected
   const userQuery = await prisma.user.findMany({
     select: { id: true, email: true, name: true },
     where: { status: 'ACTIVE', deletedAt: null }
   });
   ```
   → Action: Extract to `prisma.mdc` standard query pattern

2. **Impact Assessment**
   - Frequency: How often does this pattern occur?
   - Scope: How many files/developers affected?
   - Risk: What errors could this prevent?

3. **Rule Formulation**
   - Write specific, actionable instruction
   - Include concrete example from codebase
   - Add rationale and expected outcome

## 📝 Rule Creation Guidelines

### Rule Template
```markdown
## Rule: [Descriptive Name]
**Priority**: Critical | High | Medium | Low
**Applies to**: [file patterns or conditions]

### What to do:
[Clear, imperative instruction]

### Example:
\`\`\`[language]
// ✅ Good
[code example from actual codebase]

// ❌ Avoid
[anti-pattern example]
\`\`\`

### Why:
[Brief rationale - max 2 sentences]

### References:
- [Link to relevant documentation]
- Related: [cross-reference other rules]
```

## 🔄 Rule Lifecycle Management

### Update Triggers
| Condition | Action | Priority |
|-----------|--------|----------|
| Better implementation found | Update example | Medium |
| Edge case discovered | Add handling note | High |
| Dependency updated | Review compatibility | Critical |
| Performance improvement | Replace approach | High |

### Deprecation Process
1. **Mark as deprecated** with migration path
2. **Set sunset date** (typically 30 days)
3. **Log usage** to track adoption
4. **Remove** after migration complete

## 📊 Quality Metrics

### Rule Effectiveness Score
Calculate monthly for each rule:
```
Score = (Violations Prevented × Impact) / (False Positives + Complexity)
```

### Evaluation Criteria
- **Clarity**: Can junior dev understand in <30 seconds?
- **Actionability**: Does it specify exact steps?
- **Measurability**: Can compliance be automatically checked?
- **Relevance**: Used in last 30 days?

## 🚀 Continuous Improvement Workflow

### Weekly Review Checklist
- [ ] Analyze code review comments for patterns
- [ ] Check error logs for repeated issues
- [ ] Review new dependencies for rule needs
- [ ] Update examples with latest code
- [ ] Remove/deprecate unused rules

### Monthly Optimization
1. **Token Usage Analysis**
   - Identify verbose rules
   - Apply conciseness techniques
   - Maintain clarity threshold

2. **Rule Consolidation**
   - Merge similar rules
   - Create meta-rules for patterns
   - Reduce total rule count

## 🔗 Integration Points

### Cross-Reference Structure
```yaml
rules:
  - file: prisma.mdc
    depends_on: [database.mdc, security.mdc]
    
  - file: api.mdc
    imports: [validation.mdc, error-handling.mdc]
    
  - file: testing.mdc
    complements: [performance.mdc]
```

### Documentation Sync
- **Auto-update** examples when code changes
- **Version** rules with codebase releases
- **Link** to external docs with expiry checks

---

**Meta**: This rule file itself follows optimization principles:
- Structured with clear sections and delimiters
- Uses tables and lists for scannability  
- Includes concrete examples
- Prioritizes actionable instructions
- Minimizes token usage while maintaining clarity