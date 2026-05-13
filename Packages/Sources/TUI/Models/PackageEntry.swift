import Core
import CoreProtocols
import Foundation

struct PackageEntry {
    let package: Core.Protocols.SwiftPackageEntry
    var isSelected: Bool
    var isDownloaded: Bool = false
    /// True when the resolver pulled this package in via a seed's dependency graph
    /// even though the user never explicitly selected it.
    var isDiscovered: Bool = false
    /// True when the user has put this package on the exclusion list; the resolver
    /// drops it from future closures even if transitively reached.
    var isExcluded: Bool = false
}

// SortMode moved to SortMode.swift
