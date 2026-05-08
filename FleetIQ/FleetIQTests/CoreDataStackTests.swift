import XCTest
import CoreData
@testable import FleetIQ

final class CoreDataStackTests: XCTestCase {

    private func makeInMemoryContext() -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "FleetIQ")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        return container.viewContext
    }

    func test_persistenceController_viewContextNotNil() {
        // Given / When
        let context = PersistenceController.shared.viewContext
        // Then
        XCTAssertNotNil(context)
    }

    func test_vehicleEntity_savesAndFetches() throws {
        // Given
        let context = makeInMemoryContext()
        let vehicle = VehicleEntity(context: context)
        vehicle.id = UUID()
        vehicle.registration = "TEST1234"
        vehicle.make = "Toyota"
        vehicle.model = "KDH"
        vehicle.year = 2020
        vehicle.fuelType = "Diesel"
        vehicle.currentMileage = 10000
        vehicle.createdAt = Date()

        // When
        try context.save()
        let request = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "registration == %@",
            "TEST1234")
        let results = try context.fetch(request)

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.registration, "TEST1234")
    }

    func test_serviceRecord_linkedToCorrectVehicle() throws {
        // Given
        let context = makeInMemoryContext()
        let vehicleId = UUID()
        let record = ServiceRecordEntity(context: context)
        record.id = UUID()
        record.vehicleId = vehicleId
        record.costLKR = 7500
        record.serviceType = "Brake Service"
        record.date = Date()

        // When
        try context.save()
        let request = ServiceRecordEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "vehicleId == %@",
            vehicleId as CVarArg)
        let results = try context.fetch(request)

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.costLKR, 7500)
    }
}
