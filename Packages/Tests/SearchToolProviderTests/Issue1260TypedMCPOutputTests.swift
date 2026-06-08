import MCPCore
@testable import SearchSQLite
@testable import SearchToolProvider
import SharedConstants
import Testing

@Suite("#1260 typed JSON MCP output")
struct Issue1260TypedMCPOutputTests {
    @Test("tools/list advertises format on every typed-output tool")
    func toolsListAdvertisesFormat() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeFullProvider(
            seedSearch: { try await Issue1260TypedMCPOutputFixtures.seedSymbols(on: $0) },
            seedSample: Issue1260TypedMCPOutputFixtures.seedProjectAndFile
        )
        defer { cleanup() }
        let listing = try await provider.listTools(cursor: String?.none)
        let toolNames = [
            Shared.Constants.Search.toolListSamples,
            Shared.Constants.Search.toolReadSample,
            Shared.Constants.Search.toolReadSampleFile,
            Shared.Constants.Search.toolSearchSymbols,
            Shared.Constants.Search.toolSearchPropertyWrappers,
            Shared.Constants.Search.toolSearchConcurrency,
            Shared.Constants.Search.toolSearchConformances,
            Shared.Constants.Search.toolSearchGenerics,
            Shared.Constants.Search.toolGetInheritance,
        ]
        for name in toolNames {
            let tool = try #require(listing.tools.first { $0.name == name })
            let keys = Set((tool.inputSchema.properties ?? [:]).keys)
            #expect(keys.contains(Shared.Constants.Search.schemaParamFormat), "\(name) must advertise format")
        }
    }

    @Test("invalid format is rejected before rendering")
    func invalidFormatRejected() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSampleProvider(seed: Issue1260TypedMCPOutputFixtures.seedProjectAndFile)
        defer { cleanup() }
        do {
            _ = try await provider.callTool(
                name: Shared.Constants.Search.toolListSamples,
                arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(("format", "xml"))
            )
            Issue.record("expected invalid format to throw")
        } catch let error as Shared.Core.ToolError {
            guard case let .invalidArgument(param, message) = error else {
                Issue.record("expected invalidArgument, got \(error)")
                return
            }
            #expect(param == Shared.Constants.Search.schemaParamFormat)
            #expect(message.contains("Valid values: json, markdown"))
        }
    }

    @Test("list_samples format=json returns typed project list")
    func listSamplesJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSampleProvider(seed: Issue1260TypedMCPOutputFixtures.seedProjectAndFile)
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolListSamples,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(("format", "json"))
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        #expect(json["totalProjects"] as? Int == 1)
        #expect(json["totalFiles"] as? Int == 1)
        let projects = try #require(json["projects"] as? [[String: Any]])
        let project = try #require(projects.first)
        let id = project["id"] as? String
        let title = project["title"] as? String
        let fileCount = project["fileCount"] as? Int
        #expect(id == "cupertino-demo")
        #expect(title == "Cupertino Demo")
        #expect(fileCount == 1)
    }

    @Test("read_sample format=json returns metadata and file list")
    func readSampleJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSampleProvider(seed: Issue1260TypedMCPOutputFixtures.seedProjectAndFile)
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolReadSample,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(
                ("project_id", "cupertino-demo"),
                ("format", "json")
            )
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        #expect(json["id"] as? String == "cupertino-demo")
        #expect(json["webURL"] as? String == "https://developer.apple.com/documentation/samplecode/cupertino-demo")
        let files = try #require(json["files"] as? [[String: Any]])
        let file = try #require(files.first)
        let path = file["path"] as? String
        let fileExtension = file["fileExtension"] as? String
        #expect(path == "Sources/ContentView.swift")
        #expect(fileExtension == "swift")
    }

    @Test("read_sample_file format=json returns typed file content")
    func readSampleFileJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSampleProvider(seed: Issue1260TypedMCPOutputFixtures.seedProjectAndFile)
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolReadSampleFile,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(
                ("project_id", "cupertino-demo"),
                ("file_path", "Sources/ContentView.swift"),
                ("format", "json")
            )
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        #expect(json["projectId"] as? String == "cupertino-demo")
        #expect(json["path"] as? String == "Sources/ContentView.swift")
        #expect(json["language"] as? String == "swift")
        #expect((json["content"] as? String)?.contains("ContentView") == true)
    }

    @Test("search_symbols format=json returns typed symbol rows")
    func searchSymbolsJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSearchProvider { try await Issue1260TypedMCPOutputFixtures.seedSymbols(on: $0) }
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchSymbols,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(
                ("query", "TypedBox"),
                ("format", "json")
            )
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        let filters = try #require(json["filters"] as? [String: Any])
        #expect(filters["query"] as? String == "TypedBox")
        let rows = try #require(json["results"] as? [[String: Any]])
        let row = try #require(rows.first)
        let docURI = row["doc_uri"] as? String
        let symbolName = row["symbol_name"] as? String
        #expect(docURI == "apple-docs://swiftui/typedbox")
        #expect(symbolName == "TypedBox")
    }

    @Test("search_property_wrappers format=json returns typed wrapper rows")
    func searchPropertyWrappersJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSearchProvider { try await Issue1260TypedMCPOutputFixtures.seedSymbols(on: $0) }
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchPropertyWrappers,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(
                ("wrapper", "MainActor"),
                ("format", "json")
            )
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        let filters = try #require(json["filters"] as? [String: Any])
        #expect(filters["wrapper"] as? String == "@MainActor")
        let rows = try #require(json["results"] as? [[String: Any]])
        let row = try #require(rows.first)
        let attributes = row["attributes"] as? String
        #expect(attributes == "@MainActor")
    }

    @Test("search_concurrency format=json returns typed concurrency rows")
    func searchConcurrencyJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSearchProvider { try await Issue1260TypedMCPOutputFixtures.seedSymbols(on: $0) }
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchConcurrency,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(
                ("pattern", "async"),
                ("format", "json")
            )
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        let filters = try #require(json["filters"] as? [String: Any])
        #expect(filters["pattern"] as? String == "async")
        let rows = try #require(json["results"] as? [[String: Any]])
        #expect(rows.contains { $0["symbol_name"] as? String == "loadTypedBox" })
    }

    @Test("search_conformances format=json returns typed conformance rows")
    func searchConformancesJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSearchProvider { try await Issue1260TypedMCPOutputFixtures.seedSymbols(on: $0) }
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchConformances,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(
                ("protocol", "View"),
                ("format", "json")
            )
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        let filters = try #require(json["filters"] as? [String: Any])
        #expect(filters["protocol"] as? String == "View")
        let rows = try #require(json["results"] as? [[String: Any]])
        let row = try #require(rows.first)
        let conformances = row["conformances"] as? String
        #expect(conformances == "View,Sendable")
    }

    @Test("search_generics format=json returns typed per-source arrays")
    func searchGenericsJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSearchProvider { try await Issue1260TypedMCPOutputFixtures.seedSymbols(on: $0) }
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolSearchGenerics,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(
                ("constraint", "Sendable"),
                ("format", "json")
            )
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        let filters = try #require(json["filters"] as? [String: Any])
        #expect(filters["constraint"] as? String == "Sendable")
        let appleDocs = try #require(json["apple_docs"] as? [[String: Any]])
        let row = try #require(appleDocs.first)
        let genericParams = row["generic_params"] as? String
        #expect(genericParams == "T: Sendable")
        _ = try #require(json["samples"] as? [[String: Any]])
        _ = try #require(json["packages"] as? [[String: Any]])
    }

    @Test("get_inheritance format=json returns title-bearing inheritance nodes")
    func inheritanceJSON() async throws {
        let (provider, cleanup) = try await Issue1260TypedMCPOutputFixtures.makeSearchProvider { index in
            try await Issue1260TypedMCPOutputFixtures.seedDocument(on: index, uri: "apple-docs://uikit/uibutton", framework: "uikit", title: "UIButton")
            try await Issue1260TypedMCPOutputFixtures.seedDocument(on: index, uri: "apple-docs://uikit/uicontrol", framework: "uikit", title: "UIControl")
            try await index.writeInheritanceEdges(
                pageURI: "apple-docs://uikit/uibutton",
                inheritsFromURIs: ["apple-docs://uikit/uicontrol"],
                inheritedByURIs: nil
            )
        }
        defer { cleanup() }
        let result = try await provider.callTool(
            name: Shared.Constants.Search.toolGetInheritance,
            arguments: Issue1260TypedMCPOutputFixtures.jsonArgs(
                ("symbol", "UIButton"),
                ("direction", "up"),
                ("format", "json")
            )
        )
        let json = try Issue1260TypedMCPOutputFixtures.jsonObject(from: result)
        #expect(json["status"] as? String == "ok")
        #expect(json["symbol"] as? String == "UIButton")
        let ancestors = try #require(json["ancestors"] as? [[String: Any]])
        let ancestor = try #require(ancestors.first)
        let uri = ancestor["uri"] as? String
        let title = ancestor["title"] as? String
        #expect(uri == "apple-docs://uikit/uicontrol")
        #expect(title == "UIControl")
    }
}
