import Foundation

/// IBAN validation result
public enum IBANValidationResult {
    case valid
    case invalidFormat
    case invalidChecksum
    case notGermanIBAN

    public var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }

    public var errorMessage: String? {
        switch self {
        case .valid:
            return nil
        case .invalidFormat:
            return "IBAN format is invalid. Expected format: DE followed by 20 digits."
        case .invalidChecksum:
            return "IBAN checksum validation failed."
        case .notGermanIBAN:
            return "Only German IBANs (starting with DE) are accepted."
        }
    }
}

public extension String {
    /// Validates a German IBAN according to ISO 13616
    ///
    /// Requirements:
    /// - Must start with "DE" (German country code)
    /// - Must be exactly 22 characters long (DE + 2 check digits + 18 digits)
    /// - Must pass mod-97 checksum validation
    ///
    /// - Returns: `IBANValidationResult` indicating validation status
    func validateGermanIBAN() -> IBANValidationResult {
        // Remove all whitespace to handle formatted IBANs (e.g., "DE89 3704 0044 0532 0130 00")
        let cleanedIBAN = replacingOccurrences(of: " ", with: "").uppercased()

        // Check if it starts with "DE"
        guard cleanedIBAN.hasPrefix("DE") else {
            return .notGermanIBAN
        }

        // German IBAN must be exactly 22 characters (DE + 2 check digits + 18 digits)
        guard cleanedIBAN.count == 22 else {
            return .invalidFormat
        }

        // Validate format: DE followed by 20 digits
        let pattern = "^DE\\d{20}$"
        guard cleanedIBAN.range(of: pattern, options: .regularExpression) != nil else {
            return .invalidFormat
        }

        // Validate checksum using mod-97 algorithm
        guard validateIBANChecksum(cleanedIBAN) else {
            return .invalidChecksum
        }

        return .valid
    }

    /// Validates IBAN checksum using the mod-97 algorithm
    ///
    /// Algorithm:
    /// 1. Move the first 4 characters to the end
    /// 2. Replace letters with numbers (A=10, B=11, ..., Z=35)
    /// 3. Calculate mod 97 of the resulting number
    /// 4. Valid if result is 1
    ///
    /// - Parameter iban: The IBAN string to validate (must be cleaned, no spaces)
    /// - Returns: `true` if checksum is valid, `false` otherwise
    private func validateIBANChecksum(_ iban: String) -> Bool {
        // Move first 4 characters to the end
        let rearranged = String(iban.dropFirst(4)) + String(iban.prefix(4))

        // Convert letters to numbers (A=10, B=11, ..., Z=35)
        var numericString = ""
        for char in rearranged {
            if let digit = char.wholeNumberValue {
                numericString.append(String(digit))
            } else if char.isLetter {
                // A=10, B=11, ..., Z=35
                let value = Int(char.asciiValue!) - Int(Character("A").asciiValue!) + 10
                numericString.append(String(value))
            } else {
                return false
            }
        }

        // Calculate mod 97 using string arithmetic to handle large numbers
        var remainder = 0
        for char in numericString {
            guard let digit = char.wholeNumberValue else {
                return false
            }
            remainder = (remainder * 10 + digit) % 97
        }

        return remainder == 1
    }
}
