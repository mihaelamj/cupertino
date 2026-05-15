import CryptoKit
import Foundation

// MARK: - Hash Utilities

/// Utilities for content hashing
extension Shared.Models {
    public enum HashUtilities {
        /// Compute SHA-256 hash of a string
        public static func sha256(of string: String) -> String {
            let data = Data(string.utf8)
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }

        /// Compute SHA-256 hash of data
        public static func sha256(of data: Data) -> String {
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }
    }
}
