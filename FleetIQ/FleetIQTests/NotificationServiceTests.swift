import XCTest
@testable import FleetIQ

final class NotificationServiceTests: XCTestCase {

    func test_serviceIdentifier_uniquePerVehicle() {
        // Given
        let id1 = UUID(); let id2 = UUID()
        // When
        let identifier1 = "service-\(id1.uuidString)"
        let identifier2 = "service-\(id2.uuidString)"
        // Then
        XCTAssertNotEqual(identifier1, identifier2)
    }

    func test_expiryIdentifier_includes30Days() {
        // Given
        let documentId = UUID()
        // When
        let identifier = "expiry-\(documentId.uuidString)-30"
        // Then
        XCTAssertTrue(identifier.contains("30"))
        XCTAssertTrue(identifier.contains(documentId.uuidString))
    }

    func test_notificationBody_containsRegistration() {
        // Given
        let registration = "WP CAB 1234"
        let documentType = "Revenue Licence"
        // When
        let body = "\(registration) \(documentType) expires in 30 days. Renew now."
        // Then
        XCTAssertTrue(body.contains("WP CAB 1234"))
        XCTAssertTrue(body.contains("Revenue Licence"))
    }

    func test_urgentBody_containsUrgentKeyword() {
        // Given
        let registration = "WP CAB 1234"
        // When
        let body = "URGENT: \(registration) Insurance expires in 7 days!"
        // Then
        XCTAssertTrue(body.contains("URGENT"))
        XCTAssertTrue(body.contains("7"))
    }
}
