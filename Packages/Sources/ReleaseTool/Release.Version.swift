import Foundation

// MARK: - Semver Version

extension Release {
    struct Version: CustomStringConvertible {
        let major: Int
        let minor: Int
        let patch: Int

        var description: String {
            "\(major).\(minor).\(patch)"
        }

        var tag: String {
            "v\(description)"
        }

        init?(_ string: String) {
            let parts = string.replacingOccurrences(of: "v", with: "").split(separator: ".")
            guard parts.count == 3,
                  let major = Int(parts[0]),
                  let minor = Int(parts[1]),
                  let patch = Int(parts[2]) else {
                return nil
            }
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        init(major: Int, minor: Int, patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        func bumped(_ type: BumpType) -> Version {
            switch type {
            case .major:
                return Version(major: major + 1, minor: 0, patch: 0)
            case .minor:
                return Version(major: major, minor: minor + 1, patch: 0)
            case .patch:
                return Version(major: major, minor: minor, patch: patch + 1)
            }
        }
    }
}
