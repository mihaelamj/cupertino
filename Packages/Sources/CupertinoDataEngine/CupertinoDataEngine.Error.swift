import Foundation

// MARK: - CupertinoDataEngine.Error

extension CupertinoDataEngine {
    public enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case missingDatabase(role: String, path: String)
        case schemaVersionMismatch(role: String, path: String, expected: Int32, actual: Int32)
        case schemaVersionUnavailable(role: String, path: String, message: String)
        case duplicateSearchDatabaseID(String)
        case searchDatabaseFactoryNotConfigured
        case sampleDatabaseFactoryNotConfigured
        case packageDatabaseFactoryNotConfigured
        case searchDatabaseNotConfigured(String)
        case documentBrowserUnavailable(String)
        case sampleDatabaseNotConfigured
        case packagesDatabaseNotConfigured

        public var errorDescription: String? {
            switch self {
            case .missingDatabase(let role, let path):
                "\(role) is missing at \(path). Download or bundle the database before opening CupertinoDataEngine."
            case .schemaVersionMismatch(let role, let path, let expected, let actual):
                "\(role) at \(path) has schema version \(actual), but this engine expects \(expected). Ship a matching engine/database pair."
            case .schemaVersionUnavailable(let role, let path, let message):
                "\(role) at \(path) does not expose a readable schema version: \(message)."
            case .duplicateSearchDatabaseID(let id):
                "Duplicate search database id: \(id)."
            case .searchDatabaseFactoryNotConfigured:
                "Search databases are configured, but no search database factory was supplied."
            case .sampleDatabaseFactoryNotConfigured:
                "A sample database is configured, but no sample database factory was supplied."
            case .packageDatabaseFactoryNotConfigured:
                "A packages database is configured, but no packages database factory was supplied."
            case .searchDatabaseNotConfigured(let id):
                "No search database configured for id \(id)."
            case .documentBrowserUnavailable(let id):
                "Search database \(id) does not implement document browsing."
            case .sampleDatabaseNotConfigured:
                "No sample database configured."
            case .packagesDatabaseNotConfigured:
                "No packages database configured."
            }
        }
    }
}
