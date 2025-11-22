import Core
import Foundation

struct PackageEntry {
    let package: SwiftPackageEntry
    var isSelected: Bool
    var isDownloaded: Bool = false
}

enum SortMode: String {
    case stars = "Stars ▼"
    case name = "Name ▲"
    case recent = "Recent ▼"
}
