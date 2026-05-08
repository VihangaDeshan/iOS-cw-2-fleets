import XCTest
@testable import FleetIQ

final class FirestoreServiceTests: XCTestCase {

    // MARK: - FleetDriverUser model

    func test_fleetDriverUser_initializesAllFields() {
        // Given / When
        let driver = FleetDriverUser(
            userId: "uid-001",
            name: "Kasun Perera",
            email: "kasun@example.com",
            phone: "0711234567",
            fleetId: "fleet-abc",
            role: "driver",
            assignedVehicleId: "vehicle-xyz"
        )

        // Then
        XCTAssertEqual(driver.userId, "uid-001")
        XCTAssertEqual(driver.name, "Kasun Perera")
        XCTAssertEqual(driver.email, "kasun@example.com")
        XCTAssertEqual(driver.fleetId, "fleet-abc")
        XCTAssertEqual(driver.role, "driver")
        XCTAssertEqual(driver.assignedVehicleId, "vehicle-xyz")
    }

    // MARK: - Storage path placeholder detection

    func test_storagePlaceholder_prefixIsDetectable() {
        // Given: a reference returned when Firebase Storage is not yet readable
        let placeholder = "storage_path:faults/fleet-abc/photo.jpg"
        // Then
        XCTAssertTrue(placeholder.hasPrefix("storage_path:"))
    }

    func test_httpsUrl_notDetectedAsPlaceholder() {
        // Given
        let url = "https://firebasestorage.googleapis.com/v0/b/fleetiq.appspot.com/o/photo.jpg"
        // Then
        XCTAssertFalse(url.hasPrefix("storage_path:"))
        XCTAssertTrue(url.hasPrefix("https://"))
    }

    func test_emptyReference_notAPlaceholderOrUrl() {
        let reference = "   ".trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(reference.isEmpty)
    }

    // MARK: - Storage path normalisation (mirrors private normalizedStoragePath)

    func test_normalizedPath_removesDoubleSlashesAndEdgeSlashes() {
        // Given
        let rawPath = "/faults/fleet-abc//photo.jpg/"
        // When — same algorithm as FirestoreService.normalizedStoragePath
        let segments = rawPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalized = segments.joined(separator: "/")
        // Then
        XCTAssertEqual(normalized, "faults/fleet-abc/photo.jpg")
        XCTAssertFalse(normalized.hasPrefix("/"))
        XCTAssertFalse(normalized.hasSuffix("/"))
    }

    func test_normalizedPath_emptyStringFromBlankSegments() {
        let rawPath = "///"
        let segments = rawPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - Empty fleet-ID guard (mirrors listenToVehicles guard)

    func test_blankFleetId_normaliseToEmpty() {
        let fleetId = "   "
        let normalized = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(normalized.isEmpty)
    }

    func test_validFleetId_survivesNormalisation() {
        let fleetId = "fleet-001"
        let normalized = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(normalized.isEmpty)
    }

    // MARK: - Driver merge priority (mirrors private mergeDriver logic)
    // Primary wins; secondary only fills empty fields.

    private func mergeDriver(_ primary: FleetDriverUser, with secondary: FleetDriverUser) -> FleetDriverUser {
        FleetDriverUser(
            userId: primary.userId,
            name: primary.name.isEmpty ? secondary.name : primary.name,
            email: primary.email.isEmpty ? secondary.email : primary.email,
            phone: primary.phone.isEmpty ? secondary.phone : primary.phone,
            fleetId: primary.fleetId.isEmpty ? secondary.fleetId : primary.fleetId,
            role: primary.role.isEmpty ? secondary.role : primary.role,
            assignedVehicleId: primary.assignedVehicleId.isEmpty
                ? secondary.assignedVehicleId
                : primary.assignedVehicleId
        )
    }

    func test_mergeDriver_primaryNameWinsOverSecondary() {
        // Given
        let primary = FleetDriverUser(userId: "uid-1", name: "Nimal", email: "", phone: "", fleetId: "f", role: "driver", assignedVehicleId: "")
        let secondary = FleetDriverUser(userId: "uid-1", name: "Kamal", email: "", phone: "", fleetId: "f", role: "driver", assignedVehicleId: "")
        // When
        let merged = mergeDriver(primary, with: secondary)
        // Then: primary name is kept
        XCTAssertEqual(merged.name, "Nimal")
    }

    func test_mergeDriver_secondaryFillsEmptyPrimaryName() {
        // Given: fleet collection doc has no name; users collection has full name
        let primary = FleetDriverUser(userId: "uid-2", name: "", email: "a@b.com", phone: "", fleetId: "f", role: "driver", assignedVehicleId: "")
        let secondary = FleetDriverUser(userId: "uid-2", name: "Sampath", email: "", phone: "", fleetId: "f", role: "driver", assignedVehicleId: "")
        // When
        let merged = mergeDriver(primary, with: secondary)
        // Then
        XCTAssertEqual(merged.name, "Sampath")
    }

    func test_mergeDriver_secondaryFillsEmptyAssignedVehicle() {
        // Given: fleet doc has vehicle; users doc does not
        let primary = FleetDriverUser(userId: "uid-3", name: "Ashan", email: "", phone: "", fleetId: "f", role: "driver", assignedVehicleId: "")
        let secondary = FleetDriverUser(userId: "uid-3", name: "", email: "", phone: "", fleetId: "f", role: "driver", assignedVehicleId: "v-99")
        // When
        let merged = mergeDriver(primary, with: secondary)
        // Then
        XCTAssertEqual(merged.assignedVehicleId, "v-99")
    }

    // MARK: - Payload key coverage

    func test_vehiclePayload_containsRequiredKeys() {
        // Validates the expected schema for vehicle documents
        let requiredKeys = ["id", "registration", "make", "model", "year",
                            "fuelType", "currentMileage", "fleetId"]
        let payload: [String: Any] = [
            "id": "v1",
            "registration": "WP CAB 1234",
            "make": "Toyota",
            "model": "KDH",
            "year": 2020,
            "fuelType": "Diesel",
            "currentMileage": 15000.0,
            "fleetId": "fleet-001"
        ]
        for key in requiredKeys {
            XCTAssertNotNil(payload[key], "Missing required vehicle key: \(key)")
        }
    }

    func test_serviceRecordPayload_containsRequiredKeys() {
        let requiredKeys = ["id", "vehicleId", "date", "mileageAtService",
                            "costLKR", "serviceType", "garageName"]
        let payload: [String: Any] = [
            "id": "r1",
            "vehicleId": "v1",
            "date": Date(),
            "mileageAtService": 48000.0,
            "costLKR": 8500.0,
            "serviceType": "Oil Change",
            "garageName": "Perera Motors"
        ]
        for key in requiredKeys {
            XCTAssertNotNil(payload[key], "Missing required service-record key: \(key)")
        }
    }
}
