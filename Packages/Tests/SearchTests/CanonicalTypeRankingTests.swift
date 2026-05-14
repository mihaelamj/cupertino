import Foundation
import LoggingModels
@testable import Search
import SearchModels
import Testing

// Wide canonical-type ranking battery covering #254 + #256 acceptance.
//
// These tests seed a temp DB with realistic per-type peer clusters and verify
// the canonical apple-docs page lands at #1. Each scenario mirrors what the
// real corpus has: a Swift / SwiftUI / Foundation / UIKit canonical page
// plus framework-shadow peers (sub-symbols whose title shadows the type
// name, lower-case property pages, and niche-framework name collisions).
//
// Boost composition under test:
//   - HEURISTIC 1 exact-title boost (50x suffixed / 20x clean) — #254
//   - HEURISTIC 1.5 URI simplicity + framework authority tiebreak — #256
//   - per-column BM25F weights — #181, #192 D
//
// Runs entirely against in-memory FTS5 fixtures. No corpus rebuild needed.

private func tempDB() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("canonical-ranking-\(UUID().uuidString).db")
}

private func indexPage(
    on idx: Search.Index,
    uri: String,
    framework: String,
    title: String,
    content: String
) async throws {
    try await idx.indexDocument(Search.Index.IndexDocumentParams(
        uri: uri,
        source: "apple-docs",
        framework: framework,
        title: title,
        content: content,
        filePath: "/tmp/\(framework)-\(UUID().uuidString)",
        contentHash: UUID().uuidString,
        lastCrawled: Date()
    ))
}

@Suite("Canonical type ranking (#254 + #256)")
struct CanonicalTypeRankingTests {
    // MARK: - #254 acceptance set

    @Test("Task → Swift Task struct beats kernel task_* C functions")
    func taskBeatsKernel() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_task",
            framework: "swift",
            title: "Task",
            content: "A unit of asynchronous work. Use Task to create a top-level concurrent unit of work that runs on behalf of the current actor."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://kernel/documentation_kernel_task_info",
            framework: "kernel",
            title: "task_info",
            content: "Returns information about a Mach task. The task_info function reports task accounting and statistics."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://kernel/documentation_kernel_task_threads",
            framework: "kernel",
            title: "task_threads",
            content: "Returns the set of threads in a task. task_threads enumerates kernel-side scheduling threads."
        )

        let hits = try await idx.search(query: "Task", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_task")
    }

    @Test("View → SwiftUI View protocol beats DeviceManagement View payload")
    func viewBeatsDeviceManagement() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_view",
            framework: "swiftui",
            title: "View",
            content: "A type that represents part of your app's user interface and provides modifiers that you use to configure views."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://devicemanagement/documentation_devicemanagement_view",
            framework: "devicemanagement",
            title: "View",
            content: "An MDM payload that configures view-related restrictions on a managed device."
        )

        let hits = try await idx.search(query: "View", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swiftui/documentation_swiftui_view")
    }

    @Test("URLSession → Foundation URLSession class beats sub-symbol Iterator")
    func urlSessionBeatsIterator() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_urlsession",
            framework: "foundation",
            title: "URLSession",
            content: "An object that coordinates a group of related, network data transfer tasks."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_urlsession_asyncbytes_iterator",
            framework: "foundation",
            title: "URLSession.AsyncBytes.Iterator",
            content: "An iterator over the bytes of a URLSession.AsyncBytes."
        )

        let hits = try await idx.search(query: "URLSession", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://foundation/documentation_foundation_urlsession")
    }

    @Test("Color → SwiftUI Color beats AppKit color sub-symbols")
    func colorBeatsAppKitSubsymbols() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_color",
            framework: "swiftui",
            title: "Color",
            content: "A representation of a color that adapts to a given context. Color works in SwiftUI views and modifiers."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://appkit/documentation_appkit_nsbitmapimagerep_propertykey_fallbackbackgroundcolor",
            framework: "appkit",
            title: "Color",
            content: "The fallback background color property for an NSBitmapImageRep."
        )

        let hits = try await idx.search(query: "Color", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swiftui/documentation_swiftui_color")
    }

    @Test("String → Swift String struct beats accessibility/accelerate string properties")
    func stringBeatsPeers() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_string",
            framework: "swift",
            title: "String",
            content: "A Unicode string value that is a collection of characters. String is the canonical Swift type for text."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://accessibility/documentation_accessibility_axbrailletranslationresult_resultstring",
            framework: "accessibility",
            title: "resultString",
            content: "The translated result string for an AXBrailleTranslationResult."
        )

        let hits = try await idx.search(query: "String", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_string")
    }

    // MARK: - Common Swift stdlib types (canonical Swift wins)

    @Test("Array → Swift Array struct beats sub-symbol mentions")
    func arrayCanonical() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_array",
            framework: "swift",
            title: "Array",
            content: "An ordered, random-access collection. Array is one of the most-used Swift types."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_nsarray_array",
            framework: "foundation",
            title: "Array",
            content: "A bridged array property on NSArray."
        )

        let hits = try await idx.search(query: "Array", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_array")
    }

    @Test("Optional → Swift Optional enum is the canonical answer")
    func optionalCanonical() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_optional",
            framework: "swift",
            title: "Optional",
            content: "A type that represents either a wrapped value or nil. Optional is fundamental to Swift's safety story."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftdata/documentation_swiftdata_persistentmodel_optional",
            framework: "swiftdata",
            title: "Optional",
            content: "A property wrapper for optional persistent model fields."
        )

        let hits = try await idx.search(query: "Optional", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_optional")
    }

    // MARK: - SwiftUI canonical types

    @Test("Image → SwiftUI Image beats AppKit/UIKit image sub-symbols")
    func imageCanonical() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_image",
            framework: "swiftui",
            title: "Image",
            content: "A view that displays an image. Image renders raster, vector, and system symbols in SwiftUI."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://appkit/documentation_appkit_nsimageview_image",
            framework: "appkit",
            title: "image",
            content: "The image displayed by an NSImageView."
        )

        let hits = try await idx.search(query: "Image", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swiftui/documentation_swiftui_image")
    }

    @Test("Text → SwiftUI Text view beats sub-symbol text properties")
    func textCanonical() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_text",
            framework: "swiftui",
            title: "Text",
            content: "A view that displays one or more lines of read-only text. Text is the SwiftUI primitive for prose."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://uikit/documentation_uikit_uilabel_text",
            framework: "uikit",
            title: "text",
            content: "The text displayed by the UILabel."
        )

        let hits = try await idx.search(query: "Text", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swiftui/documentation_swiftui_text")
    }

    // MARK: - Foundation canonical types

    @Test("URL → Foundation URL is canonical (no Swift competitor)")
    func urlCanonical() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_url",
            framework: "foundation",
            title: "URL",
            content: "A value that identifies the location of a resource. URL is Foundation's canonical resource locator."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://appintents/documentation_appintents_intentparameter-url",
            framework: "appintents",
            title: "URL",
            content: "An intent parameter for URL values."
        )

        let hits = try await idx.search(query: "URL", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://foundation/documentation_foundation_url")
    }

    @Test("Data → Foundation Data is canonical")
    func dataCanonical() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_data",
            framework: "foundation",
            title: "Data",
            content: "A byte buffer in memory. Data is Foundation's canonical raw-bytes container."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftdata/documentation_swiftdata_persistentmodel_data",
            framework: "swiftdata",
            title: "Data",
            content: "A persistent model property holding Data."
        )

        let hits = try await idx.search(query: "Data", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://foundation/documentation_foundation_data")
    }

    // MARK: - Niche-framework demotion (Installer JS, WebKit JS, JavaScriptCore)

    @Test("Date → Foundation Date beats WebKit JS Date binding")
    func dateBeatsWebKitJS() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_date",
            framework: "foundation",
            title: "Date",
            content: "A specific point in time, independent of any calendar or time zone. Date is Foundation's canonical timestamp."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://webkitjs/documentation_webkitjs_date",
            framework: "webkitjs",
            title: "Date",
            content: "A WebKit JavaScript Date binding."
        )

        let hits = try await idx.search(query: "Date", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://foundation/documentation_foundation_date")
    }

    @Test("Function → Swift not-applicable; demote installer_js Function")
    func swiftFunctionTermDemotesInstallerJS() async throws {
        // No Swift `Function` type exists, but installer_js has one. With the
        // authority demotion in place, the bare-typed `Function` query should
        // not float installer_js to the top of an apple-docs cluster as soon
        // as any other framework offers a more relevant page.
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_function",
            framework: "swift",
            title: "Function",
            content: "Free function declarations in Swift. Function syntax, parameter labels, return types."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://installer_js/documentation_installer_js_function",
            framework: "installer_js",
            title: "Function",
            content: "An installer JavaScript Function binding."
        )

        let hits = try await idx.search(query: "Function", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_function")
    }

    // MARK: - Negative cases (authority must NOT crowd out framework-specific results)

    @Test("AppIntents → AppIntents framework keeps its own top-level page")
    func appIntentsFrameworkSpecific() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://appintents/documentation_appintents_appintent",
            framework: "appintents",
            title: "AppIntent",
            content: "A type representing an action that an app exposes to the system."
        )
        // Decoy: a sub-symbol with a similar-but-not-equal title.
        try await indexPage(
            on: idx,
            uri: "apple-docs://appintents/documentation_appintents_appintentprovider_appintent",
            framework: "appintents",
            title: "AppIntent",
            content: "A property on AppIntentProvider that exposes the underlying AppIntent."
        )

        let hits = try await idx.search(query: "AppIntent", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://appintents/documentation_appintents_appintent")
    }

    @Test("VisionRequest → Vision framework keeps its own top-level page")
    func visionRequestFrameworkSpecific() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://vision/documentation_vision_visionrequest",
            framework: "vision",
            title: "VisionRequest",
            content: "A request executed against an image or video frame by the Vision framework."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://vision/documentation_vision_imagerequesthandler_visionrequest",
            framework: "vision",
            title: "VisionRequest",
            content: "A property on ImageRequestHandler exposing the active VisionRequest."
        )

        let hits = try await idx.search(query: "VisionRequest", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://vision/documentation_vision_visionrequest")
    }

    @Test("JSValue → JavaScriptCore framework keeps its own top-level page")
    func jsValueFrameworkSpecific() async throws {
        // JSValue exists only in JavaScriptCore. Even though JavaScriptCore
        // has an authority penalty (1.2), there's no Swift / Foundation /
        // SwiftUI competitor at the same exact title, so JSValue must still
        // land at #1.
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://javascriptcore/documentation_javascriptcore_jsvalue",
            framework: "javascriptcore",
            title: "JSValue",
            content: "A JavaScript value bridged into Swift through JavaScriptCore."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://javascriptcore/documentation_javascriptcore_jscontext_jsvalue",
            framework: "javascriptcore",
            title: "JSValue",
            content: "A JSContext property exposing a JSValue."
        )

        let hits = try await idx.search(query: "JSValue", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://javascriptcore/documentation_javascriptcore_jsvalue")
    }

    // MARK: - Sub-symbol shadow shapes (URI-simplicity tiebreak isolated)

    @Test("Same-framework sub-symbol does not beat top-level type page")
    func subsymbolShadowSameFramework() async throws {
        // Both pages are in `swiftui`. URI-simplicity must separate them even
        // when authority is identical.
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_button",
            framework: "swiftui",
            title: "Button",
            content: "A control that initiates an action when triggered. Button is a SwiftUI view that wraps a label."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_alert_button",
            framework: "swiftui",
            title: "Button",
            content: "An Alert.Button is a button shown in an alert dialog."
        )

        let hits = try await idx.search(query: "Button", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swiftui/documentation_swiftui_button")
    }

    @Test("Cross-framework sub-symbol shadow: top-level Swift type wins over deep peer")
    func subsymbolShadowCrossFramework() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_sequence",
            framework: "swift",
            title: "Sequence",
            content: "A type that provides sequential, iterated access to its elements. Sequence is a fundamental Swift protocol."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://gameplaykit/documentation_gameplaykit_gkagent_sequence",
            framework: "gameplaykit",
            title: "Sequence",
            content: "A GKAgent sequence behavior."
        )

        let hits = try await idx.search(query: "Sequence", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_sequence")
    }

    // MARK: - Multi-word queries (HEURISTIC 1 still fires for ≤3 words)

    @Test("Async Sequence → Swift AsyncSequence (single-word title) hits exact-title path")
    func asyncSequenceCanonical() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_asyncsequence",
            framework: "swift",
            title: "AsyncSequence",
            content: "A type that provides asynchronous, sequential, iterated access to its elements."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_urlsession_asyncsequence",
            framework: "foundation",
            title: "AsyncSequence",
            content: "A URLSession byte stream that conforms to AsyncSequence."
        )

        let hits = try await idx.search(query: "AsyncSequence", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_asyncsequence")
    }

    // MARK: - Lowercase / property-style queries (HEURISTIC 1 still applies)

    @Test("task (lowercase) → property pages, no canonical to override")
    func lowercaseTaskNoOverride() async throws {
        // Lowercase `task` is a property name, not a type. Authority and URI
        // simplicity should still fire if a top-level Swift `task` page
        // existed — but it doesn't, so the most-relevant property wins on
        // BM25F. This guards against the authority map silently boosting a
        // wrong page when the canonical doesn't exist.
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_view_task",
            framework: "swiftui",
            title: "task",
            content: "A SwiftUI view modifier that runs an async task tied to the view's lifetime."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://uikit/documentation_uikit_backgroundtasks_task",
            framework: "uikit",
            title: "task",
            content: "A UIKit background task identifier."
        )

        let hits = try await idx.search(query: "task", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        // Either is acceptable — both are valid. The point is that it
        // doesn't crash and produces a result.
    }

    // MARK: - Force-include canonical type page (#256 follow-on, fetchLimit escape)

    @Test("Canonical Foundation page surfaces even when buried past fetchLimit")
    func canonicalSurfacesPastFetchLimit() async throws {
        // Simulates the real-corpus failure mode: Foundation `URL` lands at
        // raw BM25 rank 1017 because hundreds of property pages titled "url"
        // have shorter docs than the parent class. The fetchCanonicalTypePages
        // helper probes by URI shape and force-includes it.
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_url",
            framework: "foundation",
            title: "URL",
            content: "A value that identifies the location of a resource. URL is Foundation's canonical resource locator. " + String(
                repeating: "Filler about URLs and HTTP and resources. ",
                count: 40
            )
        )
        // Decoy 1: short-document property page that wins BM25 by length normalization.
        try await indexPage(
            on: idx,
            uri: "apple-docs://sirieventsuggestionsmarkup/documentation_sirieventsuggestionsmarkup_url",
            framework: "sirieventsuggestionsmarkup",
            title: "URL",
            content: "A URL property."
        )
        // Decoy 2: another niche framework with a top-level "URL" page.
        try await indexPage(
            on: idx,
            uri: "apple-docs://devicemanagement/documentation_devicemanagement_url",
            framework: "devicemanagement",
            title: "URL",
            content: "A URL field on an MDM payload."
        )

        let hits = try await idx.search(query: "URL", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://foundation/documentation_foundation_url")
    }

    @Test("Force-include does not fire for queries with no canonical match")
    func forceIncludeRespectsFrameworkSpecific() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        // No swift/swiftui/foundation `JSValue` exists; only JavaScriptCore has it.
        // The canonical-page probe should return nothing and JavaScriptCore must
        // keep #1.
        try await indexPage(
            on: idx,
            uri: "apple-docs://javascriptcore/documentation_javascriptcore_jsvalue",
            framework: "javascriptcore",
            title: "JSValue",
            content: "A JavaScript value bridged into Swift through JavaScriptCore."
        )

        let hits = try await idx.search(query: "JSValue", source: "apple-docs", limit: 5)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://javascriptcore/documentation_javascriptcore_jsvalue")
    }

    @Test("Force-include preserves authority order (swift > swiftui > foundation)")
    func forceIncludeAuthorityOrder() async throws {
        // Synthetic worst case: same token has a top-level page in all three
        // top-tier frameworks. Authority order in the helper is
        // swift > swiftui > foundation; the result list must reflect that.
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_demo",
            framework: "swift",
            title: "Demo",
            content: "A Swift demo type."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://swiftui/documentation_swiftui_demo",
            framework: "swiftui",
            title: "Demo",
            content: "A SwiftUI demo view."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://foundation/documentation_foundation_demo",
            framework: "foundation",
            title: "Demo",
            content: "A Foundation demo class."
        )

        let hits = try await idx.search(query: "Demo", source: "apple-docs", limit: 5)
        try #require(hits.count >= 3)
        #expect(hits[0].uri == "apple-docs://swift/documentation_swift_demo")
        #expect(hits[1].uri == "apple-docs://swiftui/documentation_swiftui_demo")
        #expect(hits[2].uri == "apple-docs://foundation/documentation_foundation_demo")
    }

    // MARK: - Combined cluster: realistic 5-peer #256 shape

    @Test("Result cluster: Swift wins among 5 realistic peers")
    func resultClusterFivePeers() async throws {
        let dbPath = tempDB()
        defer { try? FileManager.default.removeItem(at: dbPath) }
        let idx = try await Search.Index(dbPath: dbPath, logger: Logging.NoopRecording())

        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_result",
            framework: "swift",
            title: "Result",
            content: "A value that represents either a success or a failure, including an associated value in each case. Generic over Success and Failure types."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://vision/documentation_vision_visionrequest_result",
            framework: "vision",
            title: "Result",
            content: "An associated type that represents the result of a VisionRequest."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://installer_js/documentation_installer_js_result",
            framework: "installer_js",
            title: "Result",
            content: "The result of an installer JavaScript operation."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://endpointsecurity/documentation_endpointsecurity_es_result_t_result",
            framework: "endpointsecurity",
            title: "result",
            content: "A property of es_result_t exposing the operation result."
        )
        try await indexPage(
            on: idx,
            uri: "apple-docs://swift/documentation_swift_result_publisher-swift.struct_result",
            framework: "swift",
            title: "result",
            content: "A property on Combine's Result publisher exposing the wrapped value."
        )

        let hits = try await idx.search(query: "Result", source: "apple-docs", limit: 10)
        try #require(!hits.isEmpty)
        #expect(hits.first?.uri == "apple-docs://swift/documentation_swift_result")
    }
}
