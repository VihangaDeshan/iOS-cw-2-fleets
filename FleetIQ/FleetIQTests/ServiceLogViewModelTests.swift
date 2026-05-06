import XCTest
import CoreData
@testable import FleetIQ

final class ServiceLogViewModelTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()

        // Given: isolated in-memory store
        let container = NSPersistentContainer(name: "FleetIQ")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }
        context = container.viewContext
    }

    func test_serviceRecord_savesAndFetchesByVehicleId() throws {
        // Given
        let vehicleId = UUID()
        let record = ServiceRecordEntity(context: context)
        record.id = UUID()
        record.vehicleId = vehicleId
        record.date = Date()
        record.mileageAtService = 48000
        record.costLKR = 8500
        record.serviceType = "Oil Change"
        record.garageName = "Perera Motors"

        // When
        try context.save()
        let request = ServiceRecordEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "vehicleId == %@",
            vehicleId as CVarArg)
        let results = try context.fetch(request)

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.costLKR, 8500)
    }

    func test_averageServiceInterval_twoRecordsFiveThousandKm() throws {
        // Given
        let viewModel = ServiceLogViewModel()
        let firstRecord = ServiceRecordEntity(context: context)
        firstRecord.id = UUID()
        firstRecord.vehicleId = UUID()
        firstRecord.mileageAtService = 43000
        firstRecord.date = Date().addingTimeInterval(-86400 * 30)
        firstRecord.costLKR = 5000
        firstRecord.serviceType = "Oil Change"

        let secondRecord = ServiceRecordEntity(context: context)
        secondRecord.id = UUID()
        secondRecord.vehicleId = firstRecord.vehicleId
        secondRecord.mileageAtService = 48000
        secondRecord.date = Date()
        secondRecord.costLKR = 5000
        secondRecord.serviceType = "Oil Change"

        try context.save()
        viewModel.records = [firstRecord, secondRecord]

        // When
        let interval = viewModel.averageServiceIntervalKm()

        // Then
        XCTAssertEqual(interval, 5000, accuracy: 1.0)
    }

    func test_recordsByYear_twoYearsDescending() throws {
        // Given
        var firstComponents = DateComponents()
        firstComponents.year = 2025
        firstComponents.month = 6
        firstComponents.day = 1

        var secondComponents = DateComponents()
        secondComponents.year = 2026
        secondComponents.month = 3
        secondComponents.day = 1

        let calendar = Calendar.current
        let firstRecord = ServiceRecordEntity(context: context)
        firstRecord.id = UUID()
        firstRecord.vehicleId = UUID()
        firstRecord.date = calendar.date(from: firstComponents)
        firstRecord.costLKR = 3000
        firstRecord.serviceType = "Brake"

        let secondRecord = ServiceRecordEntity(context: context)
        secondRecord.id = UUID()
        secondRecord.vehicleId = UUID()
        secondRecord.date = calendar.date(from: secondComponents)
        secondRecord.costLKR = 5000
        secondRecord.serviceType = "Oil Change"

        try context.save()
        let viewModel = ServiceLogViewModel()
        viewModel.records = [firstRecord, secondRecord]

        // When
        let grouped = viewModel.recordsByYear()

        // Then
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped.first?.year, 2026)
    }
}
