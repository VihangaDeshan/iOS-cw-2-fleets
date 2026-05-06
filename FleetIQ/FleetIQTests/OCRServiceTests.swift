import XCTest
@testable import FleetIQ

final class OCRServiceTests: XCTestCase {

    let service = OCRService.shared

    func test_extractCost_fromTotalLine() {
        // Given
        let lines = ["Perera Motors", "Oil Change",
                     "Date: 28/03/2026", "Total: 8,500"]
        // When
        let result = service.extractInvoiceFields(from: lines)
        // Then
        XCTAssertEqual(result.costLKR ?? 0, 8500, accuracy: 0.1)
    }

    func test_extractRegistration_sriLankaPlateFormat() {
        // Given
        let lines = ["Perera Motors Negombo",
                     "Vehicle: WP CAB 1234",
                     "Service: Oil Change"]
        // When
        let result = service.extractInvoiceFields(from: lines)
        // Then
        XCTAssertNotNil(result.registration)
        XCTAssertTrue(
            result.registration?.contains("1234") ?? false)
    }

    func test_extractDate_slashFormat() {
        // Given
        let lines = ["Date: 28/03/2026", "Amount: 5000"]
        // When
        let result = service.extractInvoiceFields(from: lines)
        // Then
        XCTAssertNotNil(result.serviceDate)
    }

    func test_extractExpiryDate_fromCertificateLines() {
        // Given
        let lines = [
            "Department of Motor Traffic",
            "Revenue Licence Certificate",
            "Valid Until: 15/01/2027"]
        // When
        let date = service.extractExpiryDate(from: lines)
        // Then
        XCTAssertNotNil(date)
    }
}
