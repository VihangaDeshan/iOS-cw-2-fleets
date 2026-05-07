//
//  VehicleDetailViewModel.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import Combine
import CoreData
import FirebaseFirestore

// MARK: - Vehicle Detail View Model
@MainActor
final class VehicleDetailViewModel: ObservableObject {

    // MARK: - Published
    @Published var vehicle: VehicleEntity
    @Published var isLoading = false
    @Published var showEditVehicle = false

    // MARK: - Private Properties
    private let context = PersistenceController.shared.viewContext
    private let firestoreService = FirestoreService.shared

    // MARK: - Initializer

    /// Creates a detail view model with a selected vehicle.
    /// - Parameter vehicle: Vehicle managed object to display and edit.
    init(vehicle: VehicleEntity) {
        self.vehicle = vehicle
    }

    // MARK: - Document Expiry Helpers

    /// Returns days remaining until a given date.
    /// - Parameter date: Target expiry date.
    /// - Returns: Number of days or nil when date is not set.
    func daysRemaining(until date: Date?) -> Int? {
        guard let date else {
            return nil
        }

        return Calendar.current.dateComponents([.day], from: Date(), to: date).day
    }

    /// Returns a status color based on days left until expiry.
    /// - Parameter date: Optional expiry date.
    /// - Returns: Green, orange, red, or secondary when date is missing.
    func expiryColour(for date: Date?) -> Color {
        guard let days = daysRemaining(until: date) else {
            return .secondary
        }

        if days > 30 {
            return .statusActive
        }

        if days > 7 {
            return .statusDueSoon
        }

        return .statusOverdue
    }

    /// Returns a readable chip text for a document expiry date.
    /// - Parameter date: Optional expiry date.
    /// - Returns: Day count label, expires-today label, expired label, or not-set.
    func expiryChipText(for date: Date?) -> String {
        guard let days = daysRemaining(until: date) else {
            return "Not set"
        }

        if days < 0 {
            return "Expired"
        }

        if days == 0 {
            return "Expires today"
        }

        return "\(days) days"
    }

    /// Notifies SwiftUI that the backing vehicle data changed externally.
    func notifyVehicleChanged() {
        objectWillChange.send()
    }

    // MARK: - Update

    /// Updates vehicle fields in CoreData and Firestore.
    /// - Parameters:
    ///   - registration: Updated registration number.
    ///   - make: Updated make.
    ///   - model: Updated model.
    ///   - year: Updated year.
    ///   - fuelType: Updated fuel type.
    ///   - currentMileage: Updated odometer.
    ///   - insuranceExpiry: Updated insurance expiry date.
    ///   - licenceExpiry: Updated licence expiry date.
    ///   - fleetId: Fleet identifier for Firestore path.
    func updateVehicle(
        registration: String,
        make: String,
        model: String,
        year: Int16,
        fuelType: String,
        currentMileage: Double,
        insuranceExpiry: Date?,
        licenceExpiry: Date?,
        emissionExpiry: Date?,
        fleetId: String
    ) async {
        isLoading = true

        let normalizedRegistration = registration
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let normalizedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            var data: [String: Any] = [
                "registration": normalizedRegistration,
                "make": normalizedMake,
                "model": normalizedModel,
                "year": Int(year),
                "fuelType": fuelType,
                "currentMileage": currentMileage,
                "insuranceExpiry": insuranceExpiry.map { Timestamp(date: $0) } ?? NSNull(),
                "licenceExpiry": licenceExpiry.map { Timestamp(date: $0) } ?? NSNull()
            ]

            if let createdAt = vehicle.createdAt {
                data["createdAt"] = Timestamp(date: createdAt)
            }

            try await firestoreService.updateVehicle(
                fleetId: fleetId,
                vehicleId: vehicle.id?.uuidString ?? "",
                data: data
            )

            vehicle.registration = normalizedRegistration
            vehicle.make = normalizedMake
            vehicle.model = normalizedModel
            vehicle.year = year
            vehicle.fuelType = fuelType
            vehicle.currentMileage = currentMileage
            vehicle.insuranceExpiry = insuranceExpiry
            vehicle.licenceExpiry = licenceExpiry

            try context.save()

            if let id = vehicle.id, let reg = vehicle.registration {
                if let insuranceExpiry {
                    NotificationService.shared.scheduleAllExpiryWarnings(
                        vehicleRegistration: reg,
                        documentType: "insurance",
                        expiryDate: insuranceExpiry,
                        vehicleId: id
                    )
                }
                if let licenceExpiry {
                    NotificationService.shared.scheduleAllExpiryWarnings(
                        vehicleRegistration: reg,
                        documentType: "licence",
                        expiryDate: licenceExpiry,
                        vehicleId: id
                    )
                }

                // Upsert or clear the emission DocumentEntity and Firestore document.
                let docId = "\(id.uuidString)_emission"
                let req = DocumentEntity.fetchRequest()
                req.predicate = NSPredicate(format: "vehicleId == %@ AND type == %@",
                                            id as CVarArg, "emission")
                req.fetchLimit = 1
                let existing = (try? context.fetch(req))?.first

                if let expiry = emissionExpiry {
                    let entity = existing ?? DocumentEntity(context: context)
                    if existing == nil { entity.id = UUID() }
                    entity.vehicleId = id
                    entity.type = "emission"
                    entity.expiryDate = expiry
                    entity.photoURL = existing?.photoURL ?? ""
                    try context.save()

                    let payload: [String: Any] = [
                        "id": docId,
                        "vehicleId": id.uuidString,
                        "type": "emission",
                        "expiryDate": Timestamp(date: expiry),
                        "photoURL": existing?.photoURL ?? "",
                        "updatedAt": Timestamp(date: Date())
                    ]
                    try await firestoreService.saveDocument(payload, fleetId: fleetId, docId: docId)

                    NotificationService.shared.scheduleAllExpiryWarnings(
                        vehicleRegistration: reg,
                        documentType: "emission",
                        expiryDate: expiry,
                        vehicleId: id
                    )
                } else if let existing {
                    context.delete(existing)
                    try context.save()
                }
            }
        } catch {
            print("VehicleDetailViewModel update error: \(error)")
        }

        isLoading = false
    }

    /// Assigns or clears a driver for the current vehicle and syncs related driver profiles.
    /// - Parameters:
    ///   - assignedDriverName: Selected driver display name, nil to clear.
    ///   - assignedDriverUserId: Selected driver profile ID, nil to clear.
    ///   - previousDriverUserId: Previously assigned driver profile ID, if known.
    ///   - fleetId: Current manager fleet identifier.
    /// - Returns: True when assignment is synced locally and to Firestore.
    func assignDriver(
        assignedDriverName: String?,
        assignedDriverUserId: String?,
        previousDriverUserId: String?,
        fleetId: String
    ) async -> Bool {
        guard let vehicleId = vehicle.id?.uuidString, !vehicleId.isEmpty else {
            return false
        }

        let normalizedDriverName = assignedDriverName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDriverUserId = assignedDriverUserId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPreviousUserId = previousDriverUserId?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        isLoading = true

        do {
            // Store the userId (UUID) so the display layer can always look up the correct name.
            // Fall back to the name string only when there is no userId (legacy / manual assignment).
            let assignedDriverIdValue: String?
            if let userId = normalizedDriverUserId, !userId.isEmpty {
                assignedDriverIdValue = userId
            } else if let name = normalizedDriverName, !name.isEmpty {
                assignedDriverIdValue = name
            } else {
                assignedDriverIdValue = nil
            }

            vehicle.assignedDriverId = assignedDriverIdValue
            try context.save()

            try await firestoreService.updateVehicle(
                fleetId: fleetId,
                vehicleId: vehicleId,
                data: ["assignedDriverId": assignedDriverIdValue ?? ""]
            )

            if let previousUserId = normalizedPreviousUserId,
               !previousUserId.isEmpty,
               previousUserId != (normalizedDriverUserId ?? "") {
                try await firestoreService.updateDriverUserAssignment(
                    userId: previousUserId,
                    vehicleId: ""
                )
                try await firestoreService.updateFleetDriverAssignment(
                    fleetId: fleetId,
                    driverId: previousUserId,
                    vehicleId: ""
                )
            }

            if let newDriverUserId = normalizedDriverUserId,
               !newDriverUserId.isEmpty {
                try await firestoreService.updateDriverUserAssignment(
                    userId: newDriverUserId,
                    vehicleId: vehicleId
                )
                try await firestoreService.updateFleetDriverAssignment(
                    fleetId: fleetId,
                    driverId: newDriverUserId,
                    vehicleId: vehicleId
                )
            }

            isLoading = false
            return true
        } catch {
            print("VehicleDetailViewModel assignDriver error: \(error)")
            isLoading = false
            return false
        }
    }
}
