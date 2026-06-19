import Foundation
import MCPCore
@testable import SearchAPI
import SearchModels
@testable import SearchSQLite
@testable import SearchToolProvider
import SharedConstants
import Testing
import TestSupport

// MARK: - #1283 — sample-code tools throw an actionable frame when the samples DB is absent

///
/// The "self-diagnosing" promise (#50/#645) was well covered for the search.db
/// tool family by `Issue645ToolsListHonestyTests` (a parameterised error-frame
/// test over the 10 search.db-dependent tools), but the three sample-code tools
/// (`list_samples`, `read_sample`, `read_sample_file`) had only happy-path
/// advertise tests and no missing-DB error-frame test. They guard on a nil
/// `sampleDatabase` and previously threw a dead-end "Sample code database not
/// available" with no remediation.
///
/// Post-#1283 each sample handler throws an ACTIONABLE frame naming both
/// remediation paths (`cupertino setup` to download, `cupertino save --source
/// samples` to build). This mirrors `Issue645ToolsListHonestyTests`'s
/// `handlersSurfaceDisabledReason` for the sample-tool family, so a regression
/// at any one site fails as a discrete row.
@Suite("#1283 — sample-code tools surface an actionable missing-DB frame")
struct Issue1283SampleToolMissingDBFrameTests {
    @Test(
        "sample-code handlers throw an actionable frame when the samples DB is absent",
        arguments: [
            Shared.Constants.Search.toolListSamples,
            Shared.Constants.Search.toolReadSample,
            Shared.Constants.Search.toolReadSampleFile,
        ]
    )
    func sampleHandlersSurfaceMissingDBFrame(toolName: String) async throws {
        // No samples database, no docs index: the legitimate "samples not
        // installed" deployment. The handler guard fires before arg parsing,
        // so empty args reach the frame for every sample tool.
        let provider = CompositeToolProvider(searchIndex: nil, sampleDatabase: nil)

        await #expect {
            _ = try await provider.callTool(name: toolName, arguments: [:])
        } throws: { error in
            guard case let Shared.Core.ToolError.invalidArgument(_, message) = error else {
                return false
            }
            // Actionable: names BOTH remediation paths, not a dead-end.
            return message.contains("cupertino setup")
                && message.contains("cupertino save --source samples")
        }
    }
}
