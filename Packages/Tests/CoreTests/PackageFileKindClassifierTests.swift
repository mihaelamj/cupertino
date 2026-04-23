@testable import Core
import Foundation
import Testing

// MARK: - Top-level files

@Test("classify: top-level README.md → .readme")
func classifyTopLevelReadme() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "README.md")
    #expect(r?.kind == .readme)
    #expect(r?.module == nil)
}

@Test("classify: top-level readme (lowercase) → .readme")
func classifyTopLevelReadmeLowercase() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "readme.md")
    #expect(r?.kind == .readme)
}

@Test("classify: top-level CHANGELOG.md → .changelog")
func classifyChangelog() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "CHANGELOG.md")
    #expect(r?.kind == .changelog)
}

@Test("classify: LICENSE.txt → .license")
func classifyLicense() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "LICENSE.txt")
    #expect(r?.kind == .license)
}

@Test("classify: Package.swift → .packageManifest")
func classifyPackageManifest() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "Package.swift")
    #expect(r?.kind == .packageManifest)
}

@Test("classify: Package.resolved → .packageResolved")
func classifyPackageResolved() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "Package.resolved")
    #expect(r?.kind == .packageResolved)
}

@Test("classify: MIGRATING.md top-level → .projectDoc")
func classifyProjectDocTopLevel() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "MIGRATING.md")
    #expect(r?.kind == .projectDoc)
}

// MARK: - DocC catalogs

@Test("classify: Sources/Module/Module.docc/Article.md → .doccArticle + module")
func classifyDoccArticle() {
    let r = Core.PackageFileKindClassifier.classify(
        relpath: "Sources/Logging/Docs.docc/BestPractices/002-StructuredLogging.md"
    )
    #expect(r?.kind == .doccArticle)
    #expect(r?.module == "Logging")
}

@Test("classify: .docc/*.tutorial → .doccTutorial")
func classifyDoccTutorial() {
    let r = Core.PackageFileKindClassifier.classify(
        relpath: "Sources/MyModule/Docs.docc/Tutorials/Step1.tutorial"
    )
    #expect(r?.kind == .doccTutorial)
    #expect(r?.module == "MyModule")
}

// MARK: - Sources / Tests

@Test("classify: Sources/Module/File.swift → .source + module")
func classifySource() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "Sources/NIOCore/EventLoop.swift")
    #expect(r?.kind == .source)
    #expect(r?.module == "NIOCore")
}

@Test("classify: Tests/ModuleTests/File.swift → .test + module")
func classifyTest() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "Tests/NIOCoreTests/EventLoopTests.swift")
    #expect(r?.kind == .test)
    #expect(r?.module == "NIOCoreTests")
}

// MARK: - Examples

@Test("classify: Examples/foo.swift → .example")
func classifyExampleSwift() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "Examples/TodoApp/main.swift")
    #expect(r?.kind == .example)
}

@Test("classify: Demo/foo.md → .example")
func classifyExampleMarkdown() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "Demo/README.md")
    #expect(r?.kind == .example)
}

@Test("classify: Examples/ image file → nil (non-text)")
func classifyExampleBinary() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "Examples/TodoApp/logo.png")
    #expect(r == nil)
}

// MARK: - Rejections

@Test("classify: random binary at any level → nil")
func classifyBinaryRejected() {
    #expect(Core.PackageFileKindClassifier.classify(relpath: "Sources/Logging/logo.png") == nil)
}

@Test("classify: deep non-markdown, non-swift file → nil")
func classifyDeepNonText() {
    #expect(Core.PackageFileKindClassifier.classify(relpath: "Sources/Logging/Resources/thing.json") == nil)
}

@Test("classify: empty path → nil")
func classifyEmptyPath() {
    #expect(Core.PackageFileKindClassifier.classify(relpath: "") == nil)
}

@Test("classify: Documentation/Article.md (non-docc, nested) → .projectDoc")
func classifyDocumentationArticle() {
    let r = Core.PackageFileKindClassifier.classify(relpath: "Documentation/Architecture.md")
    #expect(r?.kind == .projectDoc)
}
