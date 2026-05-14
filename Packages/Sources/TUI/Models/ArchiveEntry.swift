import Foundation
import SharedConstants
// MARK: - Archive Guide Entry

/// Entry representing an archive guide in the TUI
struct ArchiveEntry {
    let title: String
    let framework: String
    let category: String
    let path: String
    let description: String
    var isSelected: Bool
    var isDownloaded: Bool
    var isRequired: Bool // Cannot be deselected if true

    /// Full URL to the archive guide
    var url: URL? {
        URL(string: "\(Shared.Constants.BaseURL.appleArchiveDocs)\(path)")
    }
}
