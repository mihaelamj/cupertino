import ArgumentParser
@testable import CLI
import Testing

@Suite("Output format alias parsing (#747)")
struct OutputFormatAliasTests {
    @Test("md parses as markdown on documented format-bearing commands")
    func mdParsesAsMarkdown() throws {
        let search = try CLIImpl.Command.Search.parse(["VStack", "--format", "md"])
        #expect(search.format == .markdown)

        let read = try CLIImpl.Command.Read.parse([
            "apple-docs://swiftui/documentation_swiftui_view",
            "--format", "md",
        ])
        #expect(read.format == .markdown)

        let readSample = try CLIImpl.Command.ReadSample.parse([
            "building-a-document-based-app-with-swiftui",
            "--format", "md",
        ])
        #expect(readSample.format == .markdown)

        let readSampleFile = try CLIImpl.Command.ReadSampleFile.parse([
            "building-a-document-based-app-with-swiftui",
            "ContentView.swift",
            "--format", "md",
        ])
        #expect(readSampleFile.format == .markdown)

        let listFrameworks = try CLIImpl.Command.ListFrameworks.parse(["--format", "md"])
        #expect(listFrameworks.format == .markdown)

        let listSamples = try CLIImpl.Command.ListSamples.parse(["--format", "md"])
        #expect(listSamples.format == .markdown)

        let inheritance = try CLIImpl.Command.Inheritance.parse(["UIButton", "--format", "md"])
        #expect(inheritance.format == .markdown)
    }

    @Test("md parses as markdown on AST search siblings")
    func mdParsesOnASTSearchSiblings() throws {
        let symbols = try CLIImpl.Command.SearchSymbols.parse(["--query", "View", "--format", "md"])
        #expect(symbols.format == .markdown)

        let wrappers = try CLIImpl.Command.SearchPropertyWrappers.parse(["--wrapper", "State", "--format", "md"])
        #expect(wrappers.format == .markdown)

        let concurrency = try CLIImpl.Command.SearchConcurrency.parse(["--pattern", "async", "--format", "md"])
        #expect(concurrency.format == .markdown)

        let conformances = try CLIImpl.Command.SearchConformances.parse(["--protocol", "View", "--format", "md"])
        #expect(conformances.format == .markdown)

        let generics = try CLIImpl.Command.SearchGenerics.parse(["--constraint", "View", "--format", "md"])
        #expect(generics.format == .markdown)
    }
}
