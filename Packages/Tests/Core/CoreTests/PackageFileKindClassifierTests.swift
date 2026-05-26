@testable import Core
import CoreProtocols
import Foundation
import Testing

// MARK: - Top-level files

@Test("classify: top-level README.md → .readme")
func classifyTopLevelReadme() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "README.md")
    #expect(result?.kind == .readme)
    #expect(result?.module == nil)
}

@Test("classify: top-level readme (lowercase) → .readme")
func classifyTopLevelReadmeLowercase() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "readme.md")
    #expect(result?.kind == .readme)
}

@Test("classify: top-level CHANGELOG.md → .changelog")
func classifyChangelog() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "CHANGELOG.md")
    #expect(result?.kind == .changelog)
}

@Test("classify: LICENSE.txt → .license")
func classifyLicense() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "LICENSE.txt")
    #expect(result?.kind == .license)
}

@Test("classify: Package.swift → .packageManifest")
func classifyPackageManifest() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Package.swift")
    #expect(result?.kind == .packageManifest)
}

@Test("classify: Package.resolved → .packageResolved")
func classifyPackageResolved() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Package.resolved")
    #expect(result?.kind == .packageResolved)
}

@Test("classify: MIGRATING.md top-level → .projectDoc")
func classifyProjectDocTopLevel() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "MIGRATING.md")
    #expect(result?.kind == .projectDoc)
}

// MARK: - DocC catalogs

@Test("classify: Sources/Module/Module.docc/Article.md → .doccArticle + module")
func classifyDoccArticle() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(
        relpath: "Sources/Logging/Docs.docc/BestPractices/002-StructuredLogging.md"
    )
    #expect(result?.kind == .doccArticle)
    #expect(result?.module == "Logging")
}

@Test("classify: .docc/*.tutorial → .doccTutorial")
func classifyDoccTutorial() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(
        relpath: "Sources/MyModule/Docs.docc/Tutorials/Step1.tutorial"
    )
    #expect(result?.kind == .doccTutorial)
    #expect(result?.module == "MyModule")
}

// MARK: - Sources / Tests

@Test("classify: Sources/Module/File.swift → .source + module")
func classifySource() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Sources/NIOCore/EventLoop.swift")
    #expect(result?.kind == .source)
    #expect(result?.module == "NIOCore")
}

@Test("classify: Tests/ModuleTests/File.swift → .test + module")
func classifyTest() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Tests/NIOCoreTests/EventLoopTests.swift")
    #expect(result?.kind == .test)
    #expect(result?.module == "NIOCoreTests")
}

// MARK: - Examples

@Test("classify: Examples/foo.swift → .example")
func classifyExampleSwift() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Examples/TodoApp/main.swift")
    #expect(result?.kind == .example)
}

@Test("classify: Demo/foo.md → .example")
func classifyExampleMarkdown() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Demo/README.md")
    #expect(result?.kind == .example)
}

@Test("classify: Examples/ image file → nil (non-text)")
func classifyExampleBinary() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Examples/TodoApp/logo.png")
    #expect(result == nil)
}

// MARK: - Rejections

@Test("classify: random binary at any level → nil")
func classifyBinaryRejected() {
    #expect(Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Sources/Logging/logo.png") == nil)
}

@Test("classify: deep non-markdown, non-swift file → nil")
func classifyDeepNonText() {
    #expect(Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Sources/Logging/Resources/thing.json") == nil)
}

@Test("classify: empty path → nil")
func classifyEmptyPath() {
    #expect(Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "") == nil)
}

@Test("classify: Documentation/Article.md (non-docc, nested) → .projectDoc")
func classifyDocumentationArticle() {
    let result = Core.PackageIndexing.PackageFileKindClassifier.classify(relpath: "Documentation/Architecture.md")
    #expect(result?.kind == .projectDoc)
}
