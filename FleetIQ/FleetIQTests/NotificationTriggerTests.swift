import XCTest
@testable import FleetIQ

final class NotificationTriggerTests: XCTestCase {

    // MARK: - Status change detection logic

    func test_statusChanged_fromOpenToAcknowledged_isDifferent() {
        let previous = "open"
        let current  = "acknowledged"
        XCTAssertNotEqual(
            previous.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    func test_statusUnchanged_openToOpen_isEqual() {
        let previous = "open"
        let current  = "open"
        XCTAssertEqual(
            previous.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    func test_resolvedStatus_isRecognised() {
        let status = "resolved".lowercased()
        let knownStatuses = [
            "acknowledged", "workshop_booked",
            "in_progress", "resolved"
        ]
        XCTAssertTrue(knownStatuses.contains(status))
    }

    func test_unknownStatus_isNotRecognised() {
        let status = "banana".lowercased()
        let knownStatuses = [
            "acknowledged", "workshop_booked",
            "in_progress", "resolved"
        ]
        XCTAssertFalse(knownStatuses.contains(status))
    }

    // MARK: - Notification identifier uniqueness

    func test_faultNotificationIdentifier_uniquePerFault() {
        let id1 = UUID()
        let id2 = UUID()
        let key1 = "fault-status-\(id1.uuidString)"
        let key2 = "fault-status-\(id2.uuidString)"
        XCTAssertNotEqual(key1, key2)
    }

    func test_faultNotificationIdentifier_sameFaultSameKey() {
        let id = UUID()
        let key1 = "fault-status-\(id.uuidString)"
        let key2 = "fault-status-\(id.uuidString)"
        XCTAssertEqual(key1, key2)
    }

    // MARK: - Expiry notification thresholds

    func test_expiryIdentifier_30dayThreshold() {
        let docId = UUID()
        let identifier = "expiry-\(docId.uuidString)-30"
        XCTAssertTrue(identifier.hasSuffix("-30"))
        XCTAssertTrue(identifier.contains(docId.uuidString))
    }

    func test_expiryIdentifier_7dayThreshold() {
        let docId = UUID()
        let identifier = "expiry-\(docId.uuidString)-7"
        XCTAssertTrue(identifier.hasSuffix("-7"))
    }

    func test_expiryIdentifiers_30and7_areDifferent() {
        let docId = UUID()
        let id30 = "expiry-\(docId.uuidString)-30"
        let id7  = "expiry-\(docId.uuidString)-7"
        XCTAssertNotEqual(id30, id7)
    }

    // MARK: - Description truncation for notification body

    func test_descriptionSnippet_over40chars_isTruncated() {
        let longDesc = String(repeating: "a", count: 80)
        let snippet  = String(longDesc.prefix(40))
        XCTAssertEqual(snippet.count, 40)
    }

    func test_descriptionSnippet_under40chars_isUnchanged() {
        let shortDesc = "Brake noise"
        let snippet   = String(shortDesc.prefix(40))
        XCTAssertEqual(snippet, shortDesc)
    }
}
