import Foundation
@testable import Search
import Shared
import Testing

// MARK: - IntentClassifier

// MARK: - PackageQueryTests

@Suite("PackageQuery — intent classifier + tokens + chunk extraction")
struct PackageQueryTests {
    @Test("intent: how do I → .howTo")
    func intentHowDoI() {
        #expect(Search.IntentClassifier.classify("how do I use Vapor") == .howTo)
    }

    @Test("intent: how to → .howTo")
    func intentHowTo() {
        #expect(Search.IntentClassifier.classify("how to implement a log handler") == .howTo)
    }

    @Test("intent: show me an example → .example")
    func intentShowMeExample() {
        #expect(Search.IntentClassifier.classify("show me an example of DependencyKey") == .example)
    }

    @Test("intent: signature of → .symbolLookup")
    func intentSignature() {
        #expect(Search.IntentClassifier.classify("what is the signature of whenComplete") == .symbolLookup)
    }

    @Test("intent: declaration of → .symbolLookup")
    func intentDeclaration() {
        #expect(Search.IntentClassifier.classify("give me the declaration of EventLoopFuture") == .symbolLookup)
    }

    @Test("intent: where is X used → .crossReference")
    func intentWhereIsUsed() {
        #expect(Search.IntentClassifier.classify("where is NIOAsyncChannel used") == .crossReference)
    }

    @Test("intent: who uses → .crossReference")
    func intentWhoUses() {
        #expect(Search.IntentClassifier.classify("who uses the swift-log package") == .crossReference)
    }

    @Test("intent: fallback to .howTo")
    func intentFallback() {
        #expect(Search.IntentClassifier.classify("vapor middleware") == .howTo)
    }

    // MARK: - IntentConfig

    @Test("config: .howTo weights title heaviest")
    func configHowToWeights() {
        let cfg = Search.IntentConfig.for(.howTo)
        #expect(cfg.columnWeights.title > cfg.columnWeights.content)
        #expect(cfg.columnWeights.content > cfg.columnWeights.symbols)
        #expect(cfg.kindFilter.contains("doccArticle"))
        #expect(cfg.kindFilter.contains("readme"))
    }

    @Test("config: .symbolLookup weights symbols heaviest")
    func configSymbolLookupWeights() {
        let cfg = Search.IntentConfig.for(.symbolLookup)
        #expect(cfg.columnWeights.symbols > cfg.columnWeights.content)
        #expect(cfg.columnWeights.symbols > cfg.columnWeights.title)
        #expect(cfg.kindFilter.contains("source"))
    }

    @Test("config: .example prioritises example kind")
    func configExampleKindBonus() {
        let cfg = Search.IntentConfig.for(.example)
        #expect(cfg.kindBonus(for: "example") > cfg.kindBonus(for: "source"))
    }

    @Test("config: kind not in order list gets bonus 0")
    func configUnknownKindBonus() {
        let cfg = Search.IntentConfig.for(.howTo)
        #expect(cfg.kindBonus(for: "irrelevantKind") == 0)
    }

    // MARK: - Tokenizer / FTS builder

    @Test("tokens: stopwords removed")
    func tokensStopwordsRemoved() {
        let toks = Search.PackageQuery.tokens(from: "how do I use vapor")
        #expect(!toks.contains("how"))
        #expect(!toks.contains("do"))
        #expect(!toks.contains("i"))
        #expect(toks.contains("vapor"))
    }

    @Test("tokens: identifier with dots preserved")
    func tokensIdentifierWithDots() {
        let toks = Search.PackageQuery.tokens(from: "swift-nio.EventLoop")
        #expect(toks.contains("swift"))
        #expect(toks.contains("nio.EventLoop") || toks.contains("EventLoop"))
    }

    @Test("tokens: very short tokens dropped")
    func tokensShortDropped() {
        let toks = Search.PackageQuery.tokens(from: "a is foo")
        #expect(!toks.contains("a"))
        #expect(toks.contains("foo"))
    }

    @Test("buildFTSQuery: joins tokens with OR and quotes each")
    func buildFTSQueryJoinsOR() {
        let query = Search.PackageQuery.buildFTSQuery(question: "how do I use swift-log")
        #expect(query.contains("OR"))
        #expect(query.contains("\"swift\""))
    }

    @Test("buildFTSQuery: empty question → empty string")
    func buildFTSQueryEmpty() {
        #expect(Search.PackageQuery.buildFTSQuery(question: "") == "")
    }

    @Test("buildFTSQuery: only stopwords → empty string")
    func buildFTSQueryOnlyStopwords() {
        #expect(Search.PackageQuery.buildFTSQuery(question: "how do I use the") == "")
    }

    // MARK: - ChunkExtractor

    @Test("chunk: markdown returns the section containing the match")
    func chunkMarkdownSection() {
        let md = """
        # Title

        Intro paragraph.

        ## First Section

        Line about setup.

        ## LogHandler

        Custom handler content here.
        More handler details.

        ## Another

        Unrelated.
        """
        let chunk = Search.ChunkExtractor.markdownChunk(
            content: md,
            queryTokens: ["loghandler"],
            maxLines: 100
        )
        #expect(chunk.contains("## LogHandler"))
        #expect(chunk.contains("Custom handler content"))
        #expect(!chunk.contains("## Another"))
    }

    @Test("chunk: markdown no match → returns lead section")
    func chunkMarkdownLead() {
        let md = """
        # Title

        Intro.

        ## First

        Body.
        """
        let chunk = Search.ChunkExtractor.markdownChunk(
            content: md,
            queryTokens: ["nothing"],
            maxLines: 100
        )
        #expect(chunk.contains("# Title"))
        #expect(chunk.contains("Intro"))
    }

    @Test("chunk: Swift returns enclosing declaration")
    func chunkSwiftDeclaration() {
        let code = """
        import Foundation

        public struct HTTPServer {
            public var port: Int = 8080

            public func start() {
                print("starting")
            }

            public func whenComplete(_ body: () -> Void) {
                body()
            }
        }
        """
        let chunk = Search.ChunkExtractor.swiftChunk(
            content: code,
            queryTokens: ["whencomplete"],
            maxLines: 40
        )
        #expect(chunk.contains("public func whenComplete"))
        #expect(chunk.contains("body()"))
    }

    @Test("chunk: Swift with no match returns first 40 lines")
    func chunkSwiftNoMatch() {
        let code = (0..<50).map { "line \($0)" }.joined(separator: "\n")
        let chunk = Search.ChunkExtractor.swiftChunk(
            content: code,
            queryTokens: ["doesNotExist"],
            maxLines: 20
        )
        #expect(chunk.contains("line 0"))
        #expect(!chunk.contains("line 30"))
    }

    @Test("chunk: firstLines truncates")
    func chunkFirstLines() {
        let content = (0..<100).map { "line \($0)" }.joined(separator: "\n")
        let chunk = Search.ChunkExtractor.firstLines(content: content, count: 5)
        #expect(chunk.split(separator: "\n").count == 5)
    }

    @Test("chunk: unknown extension falls back to firstLines")
    func chunkUnknownExtensionFallback() {
        let content = (0..<10).map { "row \($0)" }.joined(separator: "\n")
        let chunk = Search.ChunkExtractor.extract(
            relpath: "weird/file.xyz",
            content: content,
            queryTokens: ["row"],
            maxChunkLines: 3
        )
        #expect(chunk.split(separator: "\n").count == 3)
    }
}

@Suite("PackageQuery platform filter (#220)")
struct PackageQueryPlatformFilterTests {
    @Test("minColumn maps platform names case-insensitively")
    func minColumnLookup() {
        #expect(Search.PackageQuery.minColumn(for: "iOS") == "min_ios")
        #expect(Search.PackageQuery.minColumn(for: "ios") == "min_ios")
        #expect(Search.PackageQuery.minColumn(for: "macOS") == "min_macos")
        #expect(Search.PackageQuery.minColumn(for: "MAC") == "min_macos")
        #expect(Search.PackageQuery.minColumn(for: "tvOS") == "min_tvos")
        #expect(Search.PackageQuery.minColumn(for: "watchOS") == "min_watchos")
        #expect(Search.PackageQuery.minColumn(for: "visionOS") == "min_visionos")
    }

    @Test("minColumn returns nil for unknown platform — caller skips filter")
    func minColumnUnknownReturnsNil() {
        #expect(Search.PackageQuery.minColumn(for: "Linux") == nil)
        #expect(Search.PackageQuery.minColumn(for: "") == nil)
    }
}
