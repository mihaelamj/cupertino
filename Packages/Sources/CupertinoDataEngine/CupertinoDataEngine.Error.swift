import Foundation

// MARK: - CupertinoDataEngine.Error

extension CupertinoDataEngine {
    public enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case missingCorpusResource(role: String, path: String)
        case schemaVersionMismatch(role: String, path: String, expected: Int32, actual: Int32)
        case schemaVersionUnavailable(role: String, path: String, message: String)
        case duplicateSourceID(String)
        case sourceReaderFactoryNotConfigured
        case sampleReaderFactoryNotConfigured
        case packageReaderFactoryNotConfigured
        case sourceNotConfigured(String)
        case documentBrowserUnavailable(String)
        case samplesNotConfigured
        case packagesNotConfigured

        public var errorDescription: String? {
            switch self {
            case .missingCorpusResource(let role, let path):
                "\(role) is missing at \(path). Download or bundle the Cupertino corpus before opening CupertinoDataEngine."
            case .schemaVersionMismatch(let role, let path, let expected, let actual):
                "\(role) at \(path) has schema version \(actual), but this engine expects \(expected). Ship a matching Cupertino engine/corpus pair."
            case .schemaVersionUnavailable(let role, let path, let message):
                "\(role) at \(path) does not expose a readable schema version: \(message)."
            case .duplicateSourceID(let id):
                "Duplicate source id: \(id)."
            case .sourceReaderFactoryNotConfigured:
                "Source resources are configured, but no Cupertino source reader factory was supplied."
            case .sampleReaderFactoryNotConfigured:
                "A sample resource is configured, but no Cupertino sample reader factory was supplied."
            case .packageReaderFactoryNotConfigured:
                "A packages resource is configured, but no Cupertino packages reader factory was supplied."
            case .sourceNotConfigured(let id):
                "No source configured for id \(id)."
            case .documentBrowserUnavailable(let id):
                "Source \(id) does not implement document browsing."
            case .samplesNotConfigured:
                "No samples reader configured."
            case .packagesNotConfigured:
                "No packages reader configured."
            }
        }
    }
}
