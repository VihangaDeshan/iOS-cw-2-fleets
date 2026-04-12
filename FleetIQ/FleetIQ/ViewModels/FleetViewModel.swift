//
//  FleetViewModel.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import Combine
import CoreData
import FirebaseFirestore

// MARK: - Fleet View Model
@MainActor
class FleetViewModel: ObservableObject {

    // MARK: - Published Properties
    @Published var vehicles: [VehicleEntity] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""

    // MARK: - Private Properties
    private var listener: ListenerRegistration?
    private let context = PersistenceController.shared.viewContext
    private let firestoreService = FirestoreService.shared

    // MARK: - Load

    /// Loads vehicles from CoreData immediately, then starts a Firestore snapshot listener.
    /// - Parameter fleetId: The current manager fleet identifier.
    func loadVehicles(fleetId: String) {
        errorMessage = ""
        isLoading = true

        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else {
            stopListening()
            vehicles = []
            errorMessage = "Fleet ID is missing for this account."
            isLoading = false
            return
        }

        fetchFromCoreData()
        stopListening()

        listener = firestoreService.listenToVehicles(fleetId: normalizedFleetId) { [weak self] docs in
            Task { @MainActor in
                self?.syncFromFirestore(docs)
            }
        }

        isLoading = false
    }

    /// Fetches all VehicleEntity records from CoreData.
    private func fetchFromCoreData() {
        let request = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "registration", ascending: true)]

        do {
            vehicles = try context.fetch(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Syncs Firestore snapshot documents into CoreData VehicleEntity records.
    /// - Parameter docs: Vehicle documents from Firestore snapshot callback.
    private func syncFromFirestore(_ docs: [QueryDocumentSnapshot]) {
        for doc in docs {
            let data = doc.data()

            let id = parseVehicleID(data: data, documentId: doc.documentID)
            let vehicle = existingVehicle(with: id) ?? VehicleEntity(context: context)

            vehicle.id = id
            vehicle.registration = (data["registration"] as? String ?? "").uppercased()
            vehicle.make = data["make"] as? String ?? ""
            vehicle.model = data["model"] as? String ?? ""
            vehicle.year = Int16(data["year"] as? Int ?? 0)
            vehicle.fuelType = data["fuelType"] as? String ?? ""
            vehicle.currentMileage = data["currentMileage"] as? Double ?? 0
            vehicle.assignedDriverId = data["assignedDriverId"] as? String
            vehicle.createdAt = parseDateValue(data["createdAt"]) ?? Date()
            vehicle.insuranceExpiry = parseDateValue(data["insuranceExpiry"])
            vehicle.licenceExpiry = parseDateValue(data["licenceExpiry"])
        }

        do {
            try context.save()
            fetchFromCoreData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add

    /// Creates a new vehicle in CoreData and Firestore.
    /// - Parameters:
    ///   - registration: Vehicle registration plate.
    ///   - make: Vehicle make name.
    ///   - model: Vehicle model name.
    ///   - year: Vehicle manufacturing year.
    ///   - fuelType: Selected fuel type.
    ///   - currentMileage: Current odometer reading.
    ///   - insuranceExpiry: Optional insurance expiry date.
    ///   - licenceExpiry: Optional licence expiry date.
    ///   - assignedDriverName: Optional assigned driver display name.
    ///   - assignedDriverUserId: Optional assigned driver user/profile id.
    ///   - fleetId: Fleet identifier for Firestore path.
    func addVehicle(
        registration: String,
        make: String,
        model: String,
        year: Int16,
        fuelType: String,
        currentMileage: Double,
        insuranceExpiry: Date?,
        licenceExpiry: Date?,
        assignedDriverName: String?,
        assignedDriverUserId: String?,
        fleetId: String
    ) async {
        errorMessage = ""
        isLoading = true

        let newId = UUID()
        let createdAt = Date()
        let normalizedRegistration = registration.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        let vehicle = VehicleEntity(context: context)
        vehicle.id = newId
        vehicle.registration = normalizedRegistration
        vehicle.make = normalizedMake
        vehicle.model = normalizedModel
        vehicle.year = year
        vehicle.fuelType = fuelType
        vehicle.currentMileage = currentMileage
        vehicle.createdAt = createdAt
        vehicle.assignedDriverId = assignedDriverName
        vehicle.insuranceExpiry = insuranceExpiry
        vehicle.licenceExpiry = licenceExpiry

        do {
            try context.save()

            var payload: [String: Any] = [
                "id": newId.uuidString,
                "registration": normalizedRegistration,
                "make": normalizedMake,
                "model": normalizedModel,
                "year": Int(year),
                "fuelType": fuelType,
                "currentMileage": currentMileage,
                "createdAt": Timestamp(date: createdAt),
                "assignedDriverId": assignedDriverName ?? ""
            ]

            if let insuranceExpiry {
                payload["insuranceExpiry"] = Timestamp(date: insuranceExpiry)
            } else {
                payload["insuranceExpiry"] = NSNull()
            }

            if let licenceExpiry {
                payload["licenceExpiry"] = Timestamp(date: licenceExpiry)
            } else {
                payload["licenceExpiry"] = NSNull()
            }

            try await firestoreService.saveVehicle(payload, fleetId: fleetId, vehicleId: newId.uuidString)

            if let driverUserId = assignedDriverUserId, !driverUserId.isEmpty {
                try await firestoreService.updateDriverUserAssignment(
                    userId: driverUserId,
                    vehicleId: newId.uuidString
                )
                try await firestoreService.updateFleetDriverAssignment(
                    fleetId: fleetId,
                    driverId: driverUserId,
                    vehicleId: newId.uuidString
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        fetchFromCoreData()

        isLoading = false
    }

    // MARK: - Delete

    /// Deletes a vehicle from Firestore and CoreData.
    /// - Parameters:
    ///   - vehicle: Vehicle managed object to remove.
    ///   - fleetId: Fleet identifier for Firestore path.
    func deleteVehicle(_ vehicle: VehicleEntity, fleetId: String) async {
        errorMessage = ""
        isLoading = true

        guard let vehicleId = vehicle.id?.uuidString else {
            errorMessage = "Vehicle ID is missing."
            isLoading = false
            return
        }

        do {
            try await firestoreService.deleteVehicle(fleetId: fleetId, vehicleId: vehicleId)

            context.delete(vehicle)
            try context.save()
            fetchFromCoreData()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Status Helpers

    /// Returns the vehicle service status based on predicted next service mileage.
    /// - Parameter vehicle: Vehicle record to evaluate.
    /// - Returns: "Active", "Due Soon", or "Overdue".
    func vehicleStatus(_ vehicle: VehicleEntity) -> String {
        let days = daysUntilService(vehicle)

        if days < 0 {
            return "Overdue"
        }

        if days <= 30 {
            return "Due Soon"
        }

        return "Active"
    }

    /// Returns days remaining until predicted service based on a simple mileage-to-days estimate.
    /// - Parameter vehicle: Vehicle record to evaluate.
    /// - Returns: Negative value means the vehicle is overdue.
    func daysUntilService(_ vehicle: VehicleEntity) -> Int {
        let remainingMileage = predictedNextServiceMileage(vehicle) - vehicle.currentMileage
        let assumedDailyMileage = 15.0
        return Int((remainingMileage / assumedDailyMileage).rounded(.down))
    }

    /// Returns predicted next service mileage using average historical service interval.
    /// - Parameter vehicle: Vehicle record to evaluate.
    /// - Returns: Predicted next service odometer value.
    func predictedNextServiceMileage(_ vehicle: VehicleEntity) -> Double {
        guard let vehicleId = vehicle.id else {
            return vehicle.currentMileage + 5000
        }

        let request = NSFetchRequest<ServiceRecordEntity>(entityName: "ServiceRecordEntity")
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "mileageAtService", ascending: true)]

        do {
            let records = try context.fetch(request)
            guard records.count >= 2 else {
                return vehicle.currentMileage + 5000
            }

            var intervals: [Double] = []

            for index in 1..<records.count {
                let previous = records[index - 1].mileageAtService
                let current = records[index].mileageAtService
                let interval = current - previous

                if interval > 0 {
                    intervals.append(interval)
                }
            }

            guard !intervals.isEmpty else {
                return vehicle.currentMileage + 5000
            }

            let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
            let lastServiceMileage = records.last?.mileageAtService ?? vehicle.currentMileage
            return lastServiceMileage + averageInterval
        } catch {
            return vehicle.currentMileage + 5000
        }
    }

    // MARK: - Computed

    /// Count of vehicles with status "Active".
    var activeCount: Int {
        vehicles.filter { vehicleStatus($0) == "Active" }.count
    }

    /// Count of vehicles with status "Due Soon".
    var dueSoonCount: Int {
        vehicles.filter { vehicleStatus($0) == "Due Soon" }.count
    }

    /// Count of vehicles with status "Overdue".
    var overdueCount: Int {
        vehicles.filter { vehicleStatus($0) == "Overdue" }.count
    }

    // MARK: - Cleanup

    /// Removes the active Firestore snapshot listener.
    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Ensures Firestore listener is removed when view model is deallocated.
    deinit {
        listener?.remove()
    }

    // MARK: - Private Helpers

    /// Finds an existing vehicle object by UUID.
    /// - Parameter id: Vehicle UUID.
    /// - Returns: Matching VehicleEntity if found.
    private func existingVehicle(with id: UUID) -> VehicleEntity? {
        let request = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    /// Parses a vehicle UUID from Firestore payload or document ID.
    /// - Parameters:
    ///   - data: Firestore document data dictionary.
    ///   - documentId: Firestore document ID.
    /// - Returns: A stable UUID for CoreData syncing.
    private func parseVehicleID(data: [String: Any], documentId: String) -> UUID {
        if let rawId = data["id"] as? String, let uuid = UUID(uuidString: rawId) {
            return uuid
        }

        if let uuid = UUID(uuidString: documentId) {
            return uuid
        }

        return UUID()
    }

    /// Converts Firestore date-like values into Foundation Date.
    /// - Parameter value: Firestore field value.
    /// - Returns: Date if conversion succeeds.
    private func parseDateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }

        if let date = value as? Date {
            return date
        }

        return nil
    }
}
