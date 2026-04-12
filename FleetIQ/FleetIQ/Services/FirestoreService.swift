//
//  FirestoreService.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import FirebaseFirestore

// MARK: - Firestore Service
class FirestoreService {
    // MARK: - Shared Instance
    static let shared = FirestoreService()

    // MARK: - Private Properties
    private let db = Firestore.firestore()

    // MARK: - Initializer
    /// Creates a Firestore service instance.
    private init() {}

    // MARK: - Vehicles

    /// Writes a vehicle document to fleets/{fleetId}/vehicles/{vehicleId}.
    /// - Parameters:
    ///   - data: Vehicle payload to save.
    ///   - fleetId: Fleet document identifier.
    ///   - vehicleId: Vehicle document identifier.
    func saveVehicle(
        _ data: [String: Any],
        fleetId: String,
        vehicleId: String
    ) async throws {
        let payload = vehiclePayload(from: data, vehicleId: vehicleId)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("vehicles")
                .document(vehicleId)
                .setData(payload) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Starts a real-time snapshot listener on the vehicles collection for a fleet.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - onUpdate: Callback invoked when snapshot documents change.
    /// - Returns: The active Firestore listener registration.
    func listenToVehicles(
        fleetId: String,
        onUpdate: @escaping ([QueryDocumentSnapshot]) -> Void
    ) -> ListenerRegistration {
        db.collection("fleets")
            .document(fleetId)
            .collection("vehicles")
            .addSnapshotListener { snapshot, _ in
                guard let documents = snapshot?.documents else {
                    onUpdate([])
                    return
                }

                onUpdate(documents)
            }
    }

    /// Deletes a vehicle document from Firestore.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - vehicleId: Vehicle document identifier.
    func deleteVehicle(
        fleetId: String,
        vehicleId: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("vehicles")
                .document(vehicleId)
                .delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Updates one or more fields on a vehicle document in Firestore.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - vehicleId: Vehicle document identifier.
    ///   - data: Partial field dictionary to update.
    func updateVehicle(
        fleetId: String,
        vehicleId: String,
        data: [String: Any]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("vehicles")
                .document(vehicleId)
                .updateData(data) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    // MARK: - Private Helpers

    /// Builds a strict Firestore payload for vehicle documents.
    /// - Parameters:
    ///   - data: Incoming payload candidate.
    ///   - vehicleId: Vehicle identifier to persist as the `id` field.
    /// - Returns: Dictionary matching the expected Firestore schema.
    private func vehiclePayload(from data: [String: Any], vehicleId: String) -> [String: Any] {
        let insuranceExpiry = firestoreNullableDateValue(data["insuranceExpiry"])
        let licenceExpiry = firestoreNullableDateValue(data["licenceExpiry"])

        return [
            "id": vehicleId,
            "registration": data["registration"] as? String ?? "",
            "make": data["make"] as? String ?? "",
            "model": data["model"] as? String ?? "",
            "year": data["year"] as? Int ?? 0,
            "fuelType": data["fuelType"] as? String ?? "",
            "currentMileage": data["currentMileage"] as? Double ?? 0,
            "insuranceExpiry": insuranceExpiry,
            "licenceExpiry": licenceExpiry,
            "createdAt": FieldValue.serverTimestamp()
        ]
    }

    /// Converts optional date-like values into Firestore-compatible values.
    /// - Parameter value: Potential Date, Timestamp, nil, or NSNull.
    /// - Returns: Date/Timestamp if valid, otherwise NSNull.
    private func firestoreNullableDateValue(_ value: Any?) -> Any {
        if let timestamp = value as? Timestamp {
            return timestamp
        }

        if let date = value as? Date {
            return Timestamp(date: date)
        }

        return NSNull()
    }
}
