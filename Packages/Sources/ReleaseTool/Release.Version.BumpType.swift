import ArgumentParser

// MARK: - Version Bump Type

extension Release.Version {
    enum BumpType: String, ExpressibleByArgument, CaseIterable {
        case major
        case minor
        case patch
    }
}
