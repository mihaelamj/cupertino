# Rule Loading Guide

This file helps determine which rules to load based on the context and task at hand. Each rule file contains specific guidance for different aspects of Swift development.

## Rule Loading Triggers

Rules are under `ai-rules` folder. If the folder exist in local project directory, use that.

### 📝 general.md - Core Engineering Principles
**Load when:**
- Always
- Starting any new Swift project or feature
- Making architectural decisions
- Discussing code quality, performance, or best practices
- Planning implementation strategy
- Reviewing code for improvements

**Keywords:** architecture, design, performance, quality, best practices, error handling, planning, strategy

### 🔧 mcp-tools-usage.md - MCP Tools Integration
**Load when:**
- Always
- Using Context7 for library documentation
- Implementing sequential thinking for complex problems
- Setting up interactive feedback loops
- Optimizing tool usage and performance
- Working with external MCP tools

**Keywords:** MCP, Context7, sequential thinking, tool, integration, library docs, feedback

### 🧩 dependencies.md - Dependency Injection
**Load when:**
- Setting up dependency injection
- Working with Point-Free's Dependencies library
- Creating testable code with injected dependencies
- Mocking external services (URLSession, Date, UUID)
- Implementing actor-based stateful dependencies

**Keywords:** dependency, injection, @Dependency, @DependencyClient, withDependencies, mock, test dependencies

### 🧪 testing.md - Swift Testing Framework
**Load when:**
- Writing any tests
- Setting up test suites
- Testing async code
- Working with snapshot tests or ViewInspector
- Discussing test coverage or testing strategy

**Keywords:** test, @Test, @Suite, testing, unit test, integration test, snapshot, ViewInspector, test coverage

### 🎨 view.md - SwiftUI Views
**Load when:**
- Creating new SwiftUI views
- Building UI components
- Implementing view performance optimizations
- Adding accessibility features
- Working with view modifiers or animations

**Keywords:** SwiftUI, View, UI, interface, component, accessibility, animation, LazyVStack, ForEach

### 🎯 view-model.md - ViewModel Architecture
**Load when:**
- Creating ViewModels for SwiftUI views
- Implementing state management
- Coordinating between views and business logic
- Managing async operations in UI
- Handling user interactions

**Keywords:** ViewModel, @Observable, state management, coordinator, business logic, user action

### 📋 commits.md - Git Commit Conventions
**Load when:**
- Making git commits
- Creating commit messages
- Setting up branch naming
- Discussing version control practices
- Implementing conventional commits

**Keywords:** commit, git, version control, feat, fix, branch, conventional commits

### 📚 rules.md - Rule File Creation
**Load when:**
- Creating new rule files
- Documenting coding standards
- Establishing team conventions
- Reviewing or updating existing rules
- Meta-discussions about rule effectiveness

**Keywords:** rule file, documentation, standards, conventions, meta-rules, YAML frontmatter

## 🔒 `openapi-generated.md` — OpenAPI Spec & Generated Code Guardrails
**Load when:**
- Discussing OpenAPI specs
- Analyzing generated Swift code (DTOs, clients, servers)
- Mapping DTOs → domain models
- Reviewing server/client/database alignment
- Investigating API inconsistencies
- When asked to "analyze only"
**Keywords:** OpenAPI, openapi.yaml, YAML, spec, swift-openapi-generator, generated, DTO, Components.Schemas, QueryEntitlementBaseDataDTO, .build, DerivedData, Generated

**Critical behavior:**
✅ NEVER modify YAML
✅ NEVER modify generated Swift code
✅ ONLY analyze, propose, or map externally
✅ Suggest extension points and adapters instead

## 📦 `extreme-packaging.md` — ExtremePackaging Architecture
**Load when:**
- Always (foundation architecture principle)
- Creating new packages or modules
- Adding code to existing packages
- Discussing project structure or organization
- Refactoring or extracting code to packages
- Reviewing Package.swift changes
- Planning feature implementation
- Discussing build performance or dependencies

**Keywords:** package, Package.swift, SPM, Swift Package Manager, module, modular, structure, organization, dependencies, monorepo, ExtremePackaging, granular, build performance

**Critical behavior:**
✅ Maximum granular modularization into distinct packages
✅ Single responsibility per package
✅ Explicit dependency declaration
✅ Unidirectional dependency flow (Foundation → Infrastructure → Features → Apps)
✅ Create test target for every package

## 🧩 `components.md` — Component System Architecture
**Load when:**
- Creating component packages (Components, SharedComponents, AppComponents)
- Adding new components to the system
- Discussing component architecture
- Setting up component registry/factory
- Working with hot reload (Inject, KZFileWatchers)
- Configuring components.json
- Reviewing component layer structure

**Keywords:** component, Components, SharedComponents, AppComponents, AllComponents, AnyComponent, ComponentRegistry, ComponentFactory, ComponentsBundle, hot reload, Inject, components.json

**Critical behavior:**
✅ Three-package hierarchy: Components → SharedComponents → AppComponents
✅ Components package comes FIRST with zero dependencies
✅ Contains AnyComponent, ComponentRegistry, ComponentFactory, etc.
✅ SharedComponents depends ONLY on Inject + KZFileWatchers
✅ AppComponents depends on Components + AppTheme + AppFont
✅ AllComponents aggregator ONLY for previews, NOT production

## 🔤 `app-fonts.md` — Font Registration with CoreText
**Load when:**
- Adding custom fonts to the project
- Creating AppFont package
- Implementing font registration
- Discussing font loading or Bundle.module
- Troubleshooting font issues
- Setting up typography system

**Keywords:** fonts, custom fonts, typography, CoreText, CTFontManager, Bundle.module, .process, font registration, .otf, .ttf, AppFont, FontRegistration

**Critical behavior:**
✅ ALWAYS use CoreText registration (CTFontManagerRegisterFontsForURL)
✅ NEVER use Info.plist (UIAppFonts) in SPM packages
✅ Use .process() for resources, NEVER .copy()
✅ Use Bundle.module, NEVER Bundle.main
✅ Register in app init BEFORE UI renders
✅ Platform-specific imports (#if canImport(UIKit/AppKit))

## 🎨 `app-colors.md` — Color System with HSV & Apple HIG Naming
**Load when:**
- Creating AppColors package
- Setting up color system
- Implementing dynamic light/dark colors
- Discussing semantic color naming
- Working with HSV color manipulation
- Creating AppTheme package
- Defining brand colors

**Keywords:** colors, AppColors, HSV, HSB, dynamic colors, light mode, dark mode, semantic colors, primary, destructive, label, background, Apple HIG, UIColor, NSColor

**Critical behavior:**
✅ Use HSV internally for color manipulation
✅ Follow Apple HIG naming: `primary`, `destructive` (NOT "danger"), `label` (NOT "textPrimary")
✅ AppColors standalone package (zero dependencies)
✅ AppTheme combines AppColors + AppFonts
✅ Dynamic colors with init(light:dark:)
✅ Automatic dark variant calculation from HSV
✅ NEVER use Google Material Design naming ("error", "onSurface")

## Quick Reference

```swift
// When working on a new feature:
// Load: general.md, mcp-tools-usage.md, extreme-packaging.md, view.md, view-model.md, dependencies.md

// When creating components:
// Load: general.md, mcp-tools-usage.md, extreme-packaging.md, components.md, dependencies.md

// When setting up design system (colors + fonts):
// Load: general.md, extreme-packaging.md, app-colors.md, app-fonts.md

// When adding custom fonts:
// Load: general.md, extreme-packaging.md, app-fonts.md

// When adding custom colors:
// Load: general.md, extreme-packaging.md, app-colors.md

// When writing tests:
// Load: general.md, mcp-tools-usage.md, extreme-packaging.md, testing.md, dependencies.md

// When reviewing code:
// Load: general.md, mcp-tools-usage.md, extreme-packaging.md, commits.md

// When integrating external libraries:
// Load: general.md, mcp-tools-usage.md, extreme-packaging.md, dependencies.md

// When creating documentation:
// Load: general.md, extreme-packaging.md

// When creating new packages or refactoring:
// Load: general.md, extreme-packaging.md, dependencies.md
```

## Rule Combinations

### Feature Development
1. Start with `general.md` for architecture decisions
2. Load `mcp-tools-usage.md` for available mcp tools, ignore TaskMaster rules and use internal tasks system
3. Apply `extreme-packaging.md` for package structure decisions
4. Use `view-model.md` for state coordination
5. Apply `view.md` for UI implementation
6. Include `dependencies.md` for service integration
7. Follow with `testing.md` for test coverage

### Code Review & Maintenance
1. Apply `general.md` for quality standards
2. Use `commits.md` for version control
3. Reference specific domain rules as needed

### Complex Problem Solving
1. Load `mcp-tools-usage.md` 
2. Apply `general.md` for chain-of-thought reasoning
3. Follow domain-specific rules for implementation

## Loading Strategy

1. **Always load `general.md`, `mcp-tools-usage.md`, and `extreme-packaging.md` first** - They provide the foundation
2. **Load domain-specific rules** based on the task
3. **Load supporting rules** as needed (e.g., testing when implementing)
4. **Keep loaded rules minimal** - Only what's directly relevant
5. **Refresh rules** when switching contexts or tasks
