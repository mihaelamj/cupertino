import Foundation
import SearchModels

// MARK: - Search.PackageIndex <-> Search.PackageWriter witness

/// `Search.PackageIndex` (the concrete actor in this SearchSQLite target)
/// already implements `applyAppleStaticConstraints` and `applyAppleImports`
/// with the exact shapes named by the protocol. This one-line witness
/// lets the `Enrichment.Packages*Pass` types (in the sibling Enrichment
/// target) receive `any Search.PackageWriter` instead of the concrete
/// actor. Added by #906.
extension Search.PackageIndex: Search.PackageWriter {}
