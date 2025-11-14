@testable import SharedModels
import XCTest

final class IBANValidationTests: XCTestCase {
    // MARK: - Valid German IBANs

    func testValidGermanIBAN() {
        // Valid German IBAN with correct checksum
        let iban = "DE89370400440532013000"
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid, "Valid German IBAN should pass validation")
        XCTAssertEqual(result, .valid)
        XCTAssertNil(result.errorMessage)
    }

    func testValidGermanIBANWithSpaces() {
        // Valid German IBAN formatted with spaces (should be cleaned)
        let iban = "DE89 3704 0044 0532 0130 00"
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid, "Valid German IBAN with spaces should pass validation")
        XCTAssertEqual(result, .valid)
    }

    func testValidGermanIBANLowercase() {
        // Valid German IBAN in lowercase (should be uppercased)
        let iban = "de89370400440532013000"
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid, "Valid German IBAN in lowercase should pass validation")
        XCTAssertEqual(result, .valid)
    }

    func testValidGermanIBANMixedCase() {
        // Valid German IBAN with mixed case
        let iban = "De89370400440532013000"
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid, "Valid German IBAN in mixed case should pass validation")
        XCTAssertEqual(result, .valid)
    }

    func testAnotherValidGermanIBAN() {
        // Another valid German IBAN
        let iban = "DE44500105175407324931"
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid, "Another valid German IBAN should pass validation")
        XCTAssertEqual(result, .valid)
    }

    // MARK: - Invalid Checksums

    func testInvalidChecksum() {
        // German IBAN with invalid checksum (changed last digit)
        let iban = "DE89370400440532013001" // Last digit changed from 0 to 1
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .invalidChecksum)
        XCTAssertEqual(result.errorMessage, "IBAN checksum validation failed.")
    }

    func testInvalidChecksumInCheckDigits() {
        // German IBAN with invalid check digits
        let iban = "DE00370400440532013000" // Check digits changed to 00
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .invalidChecksum)
    }

    // MARK: - Non-German IBANs

    func testFrenchIBAN() {
        // Valid French IBAN (but not German)
        let iban = "FR1420041010050500013M02606"
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .notGermanIBAN)
        XCTAssertEqual(result.errorMessage, "Only German IBANs (starting with DE) are accepted.")
    }

    func testAustrianIBAN() {
        // Valid Austrian IBAN (but not German)
        let iban = "AT611904300234573201"
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .notGermanIBAN)
    }

    func testDutchIBAN() {
        // Valid Dutch IBAN (but not German)
        let iban = "NL91ABNA0417164300"
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .notGermanIBAN)
    }

    // MARK: - Invalid Format

    func testTooShort() {
        // German IBAN that is too short
        let iban = "DE8937040044053201300"
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .invalidFormat)
        XCTAssertEqual(result.errorMessage, "IBAN format is invalid. Expected format: DE followed by 20 digits.")
    }

    func testTooLong() {
        // German IBAN that is too long
        let iban = "DE893704004405320130000"
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .invalidFormat)
    }

    func testContainsLettersAfterDE() {
        // German IBAN with letters in the number part
        let iban = "DE89370400440532013ABC"
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .invalidFormat)
    }

    func testEmptyString() {
        let iban = ""
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .notGermanIBAN)
    }

    func testNoCountryCode() {
        // IBAN without country code
        let iban = "89370400440532013000"
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .notGermanIBAN)
    }

    func testSpecialCharacters() {
        // IBAN with special characters
        let iban = "DE89-3704-0044-0532-0130-00"
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .invalidFormat)
    }

    func testOnlySpaces() {
        let iban = "     "
        let result = iban.validateGermanIBAN()

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result, .notGermanIBAN)
    }

    // MARK: - Edge Cases

    func testLeadingAndTrailingSpaces() {
        // Valid IBAN with leading and trailing spaces
        let iban = "  DE89370400440532013000  "
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid, "IBAN with leading/trailing spaces should be cleaned and validated")
    }

    func testMultipleSpaces() {
        // Valid IBAN with multiple spaces between groups
        let iban = "DE89  3704  0044  0532  0130  00"
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid, "IBAN with multiple spaces should be cleaned and validated")
    }

    // MARK: - Additional Valid German IBANs (Real Examples)

    func testRealGermanIBAN1() {
        // Another valid German IBAN example
        let iban = "DE68210501700012345678"
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid)
    }

    func testRealGermanIBAN2() {
        // Another valid German IBAN example
        let iban = "DE02120300000000202051"
        let result = iban.validateGermanIBAN()

        XCTAssertTrue(result.isValid)
    }
}
