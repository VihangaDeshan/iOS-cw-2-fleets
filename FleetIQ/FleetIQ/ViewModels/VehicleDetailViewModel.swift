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
        fleetId: String
    ) async {
        isLoading = true

        let normalizedRegistration = registration
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        vehicle.registration = normalizedRegistration
        vehicle.make = make.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        vehicle.year = year
        vehicle.fuelType = fuelType
        vehicle.currentMileage = currentMileage
        vehicle.insuranceExpiry = insuranceExpiry
        vehicle.licenceExpiry = licenceExpiry

        do {
            try context.save()

            var data: [String: Any] = [
                "registration": vehicle.registration ?? "",
                "make": vehicle.make ?? "",
                "model": vehicle.model ?? "",
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
        } catch {
            print("VehicleDetailViewModel update error: \(error)")
        }

        isLoading = false
    }
}
