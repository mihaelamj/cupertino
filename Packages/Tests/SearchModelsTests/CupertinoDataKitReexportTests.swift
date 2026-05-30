import Foundation
@testable import SearchModels
import Testing

// MARK: - CupertinoDataKit re-export seam (docs side)

// The `Search` namespace, its read value types, and its read protocols live
// in the external CupertinoDataKit package. `SearchModels` re-exports it
// (`@_exported import CupertinoDataKit` in SearchModels.Reexport.swift) so
// every in-repo consumer keeps naming `Search.*` through SearchModels with no
// direct CupertinoDataKit import.
//
// These tests are the guard for that seam: each names a re-exported protocol
// or type WITHOUT importing CupertinoDataKit. If the re-export is dropped (or
// the import is removed), this file fails to COMPILE — surfacing the break
// here instead of cascading through every downstream consumer target.
@Suite("CupertinoDataKit re-export seam (docs)")
struct CupertinoDataKitReexportTests {
    @Test("read protocols are reachable through SearchModels")
    func readProtocolsReachable() {
        // Metatype references compile only if the protocol name resolves
        // through the re-export. No concrete lives in SearchModels, so a
        // metatype is the right (and sufficient) assertion.
        _ = (any Search.DocumentReading).self
        _ = (any Search.SymbolReading).self
        _ = (any Search.Database).self
    }

    @Test("read value types are reachable through SearchModels")
    func readValueTypesReachable() {
        _ = Search.Result.self
        _ = Search.MatchedSymbol.self
        _ = Search.PlatformAvailability.self
        _ = Search.DocumentFormat.self
        _ = Search.SymbolSearchResult.self
        _ = Search.InheritanceTree.self
        _ = Search.InheritanceCandidate.self
        _ = Search.URIResource.self
        _ = Search.ResourceListMode.self
        _ = Search.FrameworkAvailability.self
        _ = Search.PlatformMinima.self
    }

    @Test("contract limits are reachable and carry the expected values")
    func contractLimitsReachable() {
        // The 3 contract constants moved into CupertinoDataKit.Limits.
        // Pin their values so a contract bump is a deliberate, visible change.
        #expect(CupertinoDataKit.Limits.summaryMaxLength == 1500)
        #expect(CupertinoDataKit.Limits.defaultSearchLimit == 20)
        #expect(CupertinoDataKit.Limits.maxSearchLimit == 100)
    }
}
