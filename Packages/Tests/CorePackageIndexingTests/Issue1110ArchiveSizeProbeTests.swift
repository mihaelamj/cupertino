@testable import CorePackageIndexing
import CoreProtocols
import Foundation
import Testing

/// #1110 regression: `PackageArchiveExtractor` HEAD-probes the tarball
/// URL before issuing the GET. If the server advertises a
/// `Content-Length` over `maxTarballBytes`, the GET is skipped (saves
/// the wasted bytes-on-wire seen on `tuist/tuist` at 270 MB pre-fix).
/// HEAD returning no Content-Length, a non-200, or a transient error
/// falls through to the GET which keeps the post-download size check.
///
/// The tests run against a stubbed `URLProtocol` registered on a
/// throwaway `URLSession`; no real network reached.
@Suite("#1110 PackageArchiveExtractor archive-size HEAD probe", .serialized)
struct Issue1110ArchiveSizeProbeTests {
    @Test("HEAD reports Content-Length > ceiling: GET is skipped, tarballTooLarge thrown")
    func headOversizeBailsBeforeGet() async {
        Issue1110Stub.reset()
        Issue1110Stub.handler = { request in
            #expect(request.httpMethod == "HEAD")
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(100 * 1024 * 1024)"]
            )!
            return (resp, Data())
        }
        let extractor = makeExtractor(maxBytes: 50 * 1024 * 1024)

        do {
            _ = try await extractor.fetchAndExtract(
                owner: "test",
                repo: "oversize",
                destination: URL(fileURLWithPath: "/dev/null")
            )
            Issue.record("Expected ExtractError.tarballTooLarge")
        } catch let error as Core.PackageIndexing.PackageArchiveExtractor.ExtractError {
            switch error {
            case .tarballTooLarge(let bytes):
                #expect(bytes == 100 * 1024 * 1024)
            default:
                Issue.record("Wrong ExtractError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        // The probe throws on the first oversize verdict, exiting the
        // candidateRefs loop. Exactly 1 HEAD and 0 GETs (not one HEAD
        // per ref as a prior comment incorrectly claimed).
        #expect(Issue1110Stub.requestCount == 1, "observed: \(Issue1110Stub.observedMethods)")
        #expect(Issue1110Stub.getRequestCount == 0, "observed: \(Issue1110Stub.observedMethods)")
    }

    // swiftlint:disable:next function_body_length
    @Test("Multi-ref: HEAD probe runs per ref until one returns oversize")
    func multiRefHeadProbePerRef() async {
        // First ref (HEAD) HEAD-probes 404; loop tries `main`, whose
        // HEAD-probe reports oversize. Total: 2 HEADs, 0 GETs.
        Issue1110Stub.reset()
        Issue1110Stub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/tar.gz/HEAD") {
                let resp = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (resp, Data())
            }
            if path.hasSuffix("/tar.gz/main") {
                let resp = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Length": "\(100 * 1024 * 1024)"]
                )!
                return (resp, Data())
            }
            // master: never reached in this test
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (resp, Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Issue1110Stub.self]
        let session = URLSession(configuration: config)
        let extractor = Core.PackageIndexing.PackageArchiveExtractor(
            session: session,
            candidateRefs: ["HEAD", "main", "master"],
            maxTarballBytes: 50 * 1024 * 1024
        )

        do {
            _ = try await extractor.fetchAndExtract(
                owner: "test",
                repo: "multi-ref",
                destination: URL(fileURLWithPath: "/dev/null")
            )
            Issue.record("Expected tarballTooLarge from the main-ref HEAD probe")
        } catch let error as Core.PackageIndexing.PackageArchiveExtractor.ExtractError {
            switch error {
            case .tarballTooLarge(let bytes):
                #expect(bytes == 100 * 1024 * 1024)
            default:
                Issue.record("Wrong ExtractError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        // HEAD/HEAD-ref + HEAD/main-ref = 2 HEADs. `master` is never
        // probed because `main` already threw. 0 GETs.
        #expect(Issue1110Stub.getRequestCount == 0, "observed: \(Issue1110Stub.observedMethods)")
        // Stub records "HEAD" via .uppercased() so the count check is
        // method-by-method consistent.
        let headCount = Issue1110Stub.observedMethods.filter { $0 == "HEAD" }.count
        #expect(headCount == 2, "observed: \(Issue1110Stub.observedMethods)")
    }

    @Test("HEAD reports Content-Length within ceiling: GET runs")
    func headUnderCeilingProceedsToGet() async {
        Issue1110Stub.reset()
        Issue1110Stub.handler = { request in
            if request.httpMethod == "HEAD" {
                let resp = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Length": "\(1024)"] // 1 KB
                )!
                return (resp, Data())
            }
            // GET: return 404 so the extractor moves on without
            // attempting on-disk extraction (the tarball isn't a real
            // tar.gz). Both behaviours are acceptable for this test:
            // we just need to verify the GET WAS attempted.
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (resp, Data())
        }
        let extractor = makeExtractor(maxBytes: 50 * 1024 * 1024)

        do {
            _ = try await extractor.fetchAndExtract(
                owner: "test",
                repo: "small",
                destination: URL(fileURLWithPath: "/dev/null")
            )
            Issue.record("Expected ExtractError (tarballNotFound) because all GETs 404")
        } catch let error as Core.PackageIndexing.PackageArchiveExtractor.ExtractError {
            // 404 across all refs surfaces as tarballNotFound. The
            // important property is that GETs ran (`> 0` below).
            switch error {
            case .tarballNotFound: break
            default: Issue.record("Wrong ExtractError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(Issue1110Stub.getRequestCount > 0)
    }

    @Test("HEAD without Content-Length: GET runs (no precondition denial)")
    func headWithoutContentLengthFallsThroughToGet() async {
        Issue1110Stub.reset()
        Issue1110Stub.handler = { request in
            if request.httpMethod == "HEAD" {
                let resp = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (resp, Data())
            }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (resp, Data())
        }
        let extractor = makeExtractor(maxBytes: 50 * 1024 * 1024)

        do {
            _ = try await extractor.fetchAndExtract(
                owner: "test",
                repo: "unknown-length",
                destination: URL(fileURLWithPath: "/dev/null")
            )
            Issue.record("Expected tarballNotFound after GET 404")
        } catch {
            // Don't care which error; the bytes-on-wire savings are
            // an optimisation. Correctness lives in the GET's
            // existing post-download size check.
        }
        #expect(Issue1110Stub.getRequestCount > 0)
    }

    @Test("HEAD network error: GET runs anyway")
    func headNetworkErrorFallsThroughToGet() async {
        Issue1110Stub.reset()
        Issue1110Stub.handler = { request in
            if request.httpMethod == "HEAD" {
                throw URLError(.timedOut)
            }
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (resp, Data())
        }
        let extractor = makeExtractor(maxBytes: 50 * 1024 * 1024)

        do {
            _ = try await extractor.fetchAndExtract(
                owner: "test",
                repo: "head-broken",
                destination: URL(fileURLWithPath: "/dev/null")
            )
            Issue.record("Expected tarballNotFound after GET 404")
        } catch {
            // Same shape: GET still runs.
        }
        #expect(Issue1110Stub.getRequestCount > 0)
    }

    // MARK: - Helpers

    private func makeExtractor(maxBytes: Int) -> Core.PackageIndexing.PackageArchiveExtractor {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Issue1110Stub.self]
        let session = URLSession(configuration: config)
        return Core.PackageIndexing.PackageArchiveExtractor(
            session: session,
            candidateRefs: ["HEAD"], // one ref keeps the request counter predictable
            maxTarballBytes: maxBytes
        )
    }
}

// MARK: - URLProtocol stub

final class Issue1110Stub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var getRequestCount = 0
    nonisolated(unsafe) static var observedMethods: [String] = []

    static func reset() {
        handler = nil
        requestCount = 0
        getRequestCount = 0
        observedMethods = []
    }

    // `URLProtocol`'s public API requires `class func` overrides
    // (these hooks dispatch through class methods, can't be `static`).
    // swiftlint:disable static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // swiftlint:enable static_over_final_class

    override func startLoading() {
        Self.requestCount += 1
        let method = request.httpMethod?.uppercased() ?? "GET"
        if method == "GET" { Self.getRequestCount += 1 }
        Self.observedMethods.append(method)
        guard let handler = Self.handler else {
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
