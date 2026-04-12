//
//  FirestoreService.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif

// MARK: - Fleet Driver User Model
struct FleetDriverUser {
    let userId: String
    let name: String
    let email: String
    let phone: String
    let fleetId: String
    let role: String
    let assignedVehicleId: String
}

private final class NoOpListenerRegistration: NSObject, ListenerRegistration {
    func remove() {}
}

// MARK: - Firestore Service
class FirestoreService {
    // MARK: - Shared Instance
    static let shared = FirestoreService()

    // MARK: - Private Properties
    private lazy var db: Firestore = {
        Self.ensureFirebaseConfigured()
        return Firestore.firestore()
    }()

    // MARK: - Initializer
    /// Creates a Firestore service instance.
    private init() {
        Self.ensureFirebaseConfigured()
    }

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
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else {
            onUpdate([])
            return NoOpListenerRegistration()
        }

        return db.collection("fleets")
            .document(normalizedFleetId)
            .collection("vehicles")
            .addSnapshotListener { snapshot, _ in
                guard let documents = snapshot?.documents else {
                    onUpdate([])
                    return
                }

                onUpdate(documents)
            }
    }

    /// Starts a real-time snapshot listener on a single vehicle document for a fleet.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - vehicleId: Vehicle document identifier.
    ///   - onUpdate: Callback invoked with latest vehicle data.
    /// - Returns: The active Firestore listener registration.
    func listenToVehicle(
        fleetId: String,
        vehicleId: String,
        onUpdate: @escaping ([String: Any]) -> Void
    ) -> ListenerRegistration {
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVehicleId = vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFleetId.isEmpty, !normalizedVehicleId.isEmpty else {
            onUpdate([:])
            return NoOpListenerRegistration()
        }

        return db.collection("fleets")
            .document(normalizedFleetId)
            .collection("vehicles")
            .document(normalizedVehicleId)
            .addSnapshotListener { snapshot, _ in
                onUpdate(snapshot?.data() ?? [:])
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

    // MARK: - Service Records

    /// Saves a service record document to fleets/{fleetId}/serviceRecords/{recordId}.
    /// - Parameters:
    ///   - data: Service record payload.
    ///   - fleetId: Fleet document identifier.
    ///   - recordId: Service record document identifier.
    func saveServiceRecord(
        _ data: [String: Any],
        fleetId: String,
        recordId: String
    ) async throws {
        let payload = serviceRecordPayload(from: data, recordId: recordId)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("serviceRecords")
                .document(recordId)
                .setData(payload) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    // MARK: - Photo Upload

    /// Uploads a UIImage to Firebase Storage and returns
    /// the download URL string.
    /// Used for fault photos and document vault only.
    func uploadPhoto(
        _ image: UIImage,
        path: String
    ) async throws -> String {
        guard let data = image.jpegData(
            compressionQuality: 0.75) else {
            throw NSError(domain: "FleetIQ",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Could not convert image to JPEG"])
        }
        let ref = Storage.storage().reference().child(path)
        let _ = try await ref.putDataAsync(data)

        // Storage can briefly return "object does not exist" immediately after upload.
        var lastError: Error?
        for attempt in 1...4 {
            do {
                let url = try await ref.downloadURL()
                return url.absoluteString
            } catch {
                lastError = error
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 300_000_000)
                }
            }
        }

        throw lastError ?? NSError(
            domain: "FleetIQ",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Photo upload completed but URL retrieval failed."]
        )
    }

    /// Builds the Firebase Storage path for a fault report photo.
    /// Path format: fleets/{fleetId}/faults/{faultId}/{filename}.jpg
    func faultPhotoPath(
        fleetId: String,
        faultId: String,
        filename: String
    ) -> String {
        "fleets/\(fleetId)/faults/\(faultId)/\(filename).jpg"
    }

    /// Builds default Firebase Storage path for a fault report photo.
    /// Path format: fleets/{fleetId}/faults/{faultId}/photo.jpg
    func faultPhotoPath(
        fleetId: String,
        faultId: String
    ) -> String {
        "fleets/\(fleetId)/faults/\(faultId)/photo.jpg"
    }

    /// Builds the Firebase Storage path for a document-vault photo.
    /// Path format: fleets/{fleetId}/documents/{vehicleId}/{docType}.jpg
    /// Allowed docType values: insurance, licence, emission.
    func documentPhotoPath(
        fleetId: String,
        vehicleId: String,
        docType: String
    ) throws -> String {
        let normalized = docType.lowercased()
        let allowed = ["insurance", "licence", "emission"]
        guard allowed.contains(normalized) else {
            throw NSError(
                domain: "FleetIQ",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid document type. Use insurance, licence, or emission."
                ]
            )
        }

        return "fleets/\(fleetId)/documents/\(vehicleId)/\(normalized).jpg"
    }

    /// Deletes a service record from Firestore.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - recordId: Service record document identifier.
    func deleteServiceRecord(
        fleetId: String,
        recordId: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("serviceRecords")
                .document(recordId)
                .delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Fetches all service records for a fleet once, sorted by newest first.
    /// - Parameter fleetId: Fleet document identifier.
    /// - Returns: Firestore query documents for service records.
    func fetchServiceRecords(
        fleetId: String
    ) async throws -> [QueryDocumentSnapshot] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[QueryDocumentSnapshot], Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("serviceRecords")
                .order(by: "date", descending: true)
                .getDocuments { snapshot, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: snapshot?.documents ?? [])
                }
        }
    }

    // MARK: - Fuel Logs

    /// Saves a fuel-log document to fleets/{fleetId}/fuelLogs/{logId}.
    /// - Parameters:
    ///   - data: Fuel-log payload.
    ///   - fleetId: Fleet document identifier.
    ///   - logId: Fuel-log identifier.
    func saveFuelLog(
        _ data: [String: Any],
        fleetId: String,
        logId: String
    ) async throws {
        let payload = fuelLogPayload(from: data, logId: logId)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("fuelLogs")
                .document(logId)
                .setData(payload) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Deletes a fuel-log document from Firestore.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - logId: Fuel-log identifier.
    func deleteFuelLog(
        fleetId: String,
        logId: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("fuelLogs")
                .document(logId)
                .delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    // MARK: - Drivers

    /// Saves a driver document to fleets/{fleetId}/drivers/{driverId}.
    /// - Parameters:
    ///   - data: Driver payload.
    ///   - fleetId: Fleet document identifier.
    ///   - driverId: Driver identifier.
    func saveDriver(
        _ data: [String: Any],
        fleetId: String,
        driverId: String
    ) async throws {
        let payload = driverPayload(from: data, driverId: driverId)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("drivers")
                .document(driverId)
                .setData(payload) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    // MARK: - Fault Reports

    /// Saves a fault report document to fleets/{fleetId}/faultReports/{faultId}.
    /// - Parameters:
    ///   - data: Fault report payload.
    ///   - fleetId: Fleet document identifier.
    ///   - faultId: Fault-report identifier.
    func saveFaultReport(
        _ data: [String: Any],
        fleetId: String,
        faultId: String
    ) async throws {
        var payload = data
        payload["id"] = payload["id"] ?? faultId
        payload["updatedAt"] = Timestamp(date: Date())

        if payload["createdAt"] == nil {
            payload["createdAt"] = Timestamp(date: Date())
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("faultReports")
                .document(faultId)
                .setData(payload, merge: true) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Updates only the status field on a fault report document.
    /// Path: fleets/{fleetId}/faultReports/{faultId}
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - faultId: Fault-report identifier.
    ///   - status: New fault status value.
    func updateFaultStatus(
        fleetId: String,
        faultId: String,
        status: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("faultReports")
                .document(faultId)
                .updateData([
                    "status": status,
                    "updatedAt": Timestamp(date: Date())
                ]) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Starts a real-time listener for all fault reports in a fleet.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - onUpdate: Callback invoked with latest fault-report documents.
    /// - Returns: Active listener registration.
    func listenToFaultReports(
        fleetId: String,
        onUpdate: @escaping ([QueryDocumentSnapshot]) -> Void
    ) -> ListenerRegistration {
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else {
            onUpdate([])
            return NoOpListenerRegistration()
        }

        return db.collection("fleets")
            .document(normalizedFleetId)
            .collection("faultReports")
            .addSnapshotListener { snapshot, _ in
                onUpdate(snapshot?.documents ?? [])
            }
    }

    /// Starts a real-time listener for one driver's fault reports in a fleet.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - driverId: Driver identifier.
    ///   - onUpdate: Callback invoked with latest driver-specific fault documents.
    /// - Returns: Active listener registration.
    func listenToMyFaults(
        fleetId: String,
        driverId: String,
        onUpdate: @escaping ([QueryDocumentSnapshot]) -> Void
    ) -> ListenerRegistration {
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDriverId = driverId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFleetId.isEmpty, !normalizedDriverId.isEmpty else {
            onUpdate([])
            return NoOpListenerRegistration()
        }

        return db.collection("fleets")
            .document(normalizedFleetId)
            .collection("faultReports")
            .whereField("driverId", isEqualTo: normalizedDriverId)
            .addSnapshotListener { snapshot, _ in
                onUpdate(snapshot?.documents ?? [])
            }
    }

    /// Updates an existing fault report document.
    /// Path: fleets/{fleetId}/faultReports/{faultId}
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - faultId: Fault-report identifier.
    ///   - data: Partial dictionary of fields to update.
    func updateFaultReport(
        fleetId: String,
        faultId: String,
        data: [String: Any]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("faultReports")
                .document(faultId)
                .updateData(data) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    // MARK: - Documents

    /// Saves a document-vault item to fleets/{fleetId}/documents/{docId}.
    /// - Parameters:
    ///   - data: Document payload.
    ///   - fleetId: Fleet document identifier.
    ///   - docId: Document identifier.
    func saveDocument(
        _ data: [String: Any],
        fleetId: String,
        docId: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("documents")
                .document(docId)
                .setData(data, merge: true) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Deletes a document-vault item from Firestore.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - docId: Document identifier.
    func deleteDocument(
        fleetId: String,
        docId: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(fleetId)
                .collection("documents")
                .document(docId)
                .delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    // MARK: - Driver Users

    /// Fetches all drivers linked to a fleet.
    /// Source: fleets/{fleetId}/drivers/{driverId}
    /// - Parameter fleetId: Fleet identifier used to scope users.
    /// - Returns: Driver users for assignment UIs.
    func fetchFleetDriverUsers(fleetId: String) async throws -> [FleetDriverUser] {
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else {
            return []
        }

        let fleetCollectionDocs = try await fetchDocuments(
            for: db.collection("fleets")
                .document(normalizedFleetId)
                .collection("drivers")
        )

        let usersByFleetIdDocs = await fetchUserDriverDocsIfAllowed(
            for: db.collection("users")
                .whereField("fleetId", isEqualTo: normalizedFleetId)
        )
        let usersByLegacyFleetIdDocs = await fetchUserDriverDocsIfAllowed(
            for: db.collection("users")
                .whereField("fleetID", isEqualTo: normalizedFleetId)
        )
        let usersByFleetNameDocs = await fetchUserDriverDocsIfAllowed(
            for: db.collection("users")
                .whereField("fleetName", isEqualTo: normalizedFleetId)
        )

        let fleetDrivers = mapFleetDriverDocsToFleetDrivers(fleetCollectionDocs, fleetId: normalizedFleetId)
        let driversFromUsersByFleetId = mapUserDocsToFleetDrivers(usersByFleetIdDocs, fleetId: normalizedFleetId)
        let driversFromUsersByLegacyFleetId = mapUserDocsToFleetDrivers(usersByLegacyFleetIdDocs, fleetId: normalizedFleetId)
        let driversFromUsersByFleetName = mapUserDocsToFleetDrivers(usersByFleetNameDocs, fleetId: normalizedFleetId)

        return mergeFleetDriverLists([
            fleetDrivers,
            driversFromUsersByFleetId,
            driversFromUsersByLegacyFleetId,
            driversFromUsersByFleetName
        ])
    }

    /// Creates or updates a manager-created driver profile in users collection.
    /// Role is forced to `driver` to support role-based assignment filtering.
    /// - Parameters:
    ///   - userId: Driver profile identifier.
    ///   - data: Driver profile fields.
    func saveDriverUserProfile(
        userId: String,
        data: [String: Any]
    ) async throws {
        var payload = data
        payload["role"] = "driver"

        let fleetIdValue = (payload["fleetId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fleetNameValue = (payload["fleetName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if fleetIdValue.isEmpty, !fleetNameValue.isEmpty {
            payload["fleetId"] = fleetNameValue
        }

        if fleetNameValue.isEmpty, !fleetIdValue.isEmpty {
            payload["fleetName"] = fleetIdValue
        }

        payload["updatedAt"] = Timestamp(date: Date())

        if payload["createdAt"] == nil {
            payload["createdAt"] = Timestamp(date: Date())
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("users")
                .document(userId)
                .setData(payload, merge: true) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Updates assignedVehicleId for a user profile.
    /// - Parameters:
    ///   - userId: User document identifier.
    ///   - vehicleId: Assigned vehicle identifier, empty to clear assignment.
    func updateDriverUserAssignment(
        userId: String,
        vehicleId: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("users")
                .document(userId)
                .updateData([
                    "assignedVehicleId": vehicleId,
                    "updatedAt": Timestamp(date: Date())
                ]) { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume(returning: ())
                }
        }
    }

    /// Updates assignedVehicleId for a fleet-scoped driver profile document.
    /// - Parameters:
    ///   - fleetId: Fleet document identifier.
    ///   - driverId: Driver document identifier within fleets/{fleetId}/drivers.
    ///   - vehicleId: Assigned vehicle identifier, empty to clear assignment.
    func updateFleetDriverAssignment(
        fleetId: String,
        driverId: String,
        vehicleId: String
    ) async throws {
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDriverId = driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty, !normalizedDriverId.isEmpty else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.collection("fleets")
                .document(normalizedFleetId)
                .collection("drivers")
                .document(normalizedDriverId)
                .setData([
                    "assignedVehicleId": vehicleId,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true) { error in
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

    /// Builds a strict Firestore payload for service records.
    /// Service records are text/numeric data only and never include image URLs.
    /// - Parameters:
    ///   - data: Incoming payload candidate.
    ///   - recordId: Service record identifier to persist as the `id` field.
    /// - Returns: Dictionary matching the expected service record schema.
    private func serviceRecordPayload(from data: [String: Any], recordId: String) -> [String: Any] {
        let dateValue: Timestamp
        if let timestamp = data["date"] as? Timestamp {
            dateValue = timestamp
        } else if let date = data["date"] as? Date {
            dateValue = Timestamp(date: date)
        } else {
            dateValue = Timestamp(date: Date())
        }

        return [
            "id": recordId,
            "vehicleId": data["vehicleId"] as? String ?? "",
            "date": dateValue,
            "mileageAtService": data["mileageAtService"] as? Double ?? 0,
            "garageName": data["garageName"] as? String ?? "",
            "serviceType": data["serviceType"] as? String ?? "",
            "costLKR": data["costLKR"] as? Double ?? 0,
            "notes": data["notes"] as? String ?? ""
        ]
    }

    /// Builds a strict Firestore payload for fuel-log documents.
    /// - Parameters:
    ///   - data: Incoming payload candidate.
    ///   - logId: Fuel-log identifier to persist as the `id` field.
    /// - Returns: Dictionary matching fuel-log schema.
    private func fuelLogPayload(from data: [String: Any], logId: String) -> [String: Any] {
        let dateValue: Timestamp
        if let timestamp = data["date"] as? Timestamp {
            dateValue = timestamp
        } else if let date = data["date"] as? Date {
            dateValue = Timestamp(date: date)
        } else {
            dateValue = Timestamp(date: Date())
        }

        return [
            "id": logId,
            "vehicleId": data["vehicleId"] as? String ?? "",
            "date": dateValue,
            "mileage": data["mileage"] as? Double ?? 0,
            "litres": data["litres"] as? Double ?? 0,
            "totalCostLKR": data["totalCostLKR"] as? Double ?? 0,
            "costPerLitre": data["costPerLitre"] as? Double ?? 0,
            "kmPerLitre": data["kmPerLitre"] as? Double ?? 0
        ]
    }

    /// Builds a strict Firestore payload for driver documents.
    /// - Parameters:
    ///   - data: Incoming payload candidate.
    ///   - driverId: Driver identifier to persist as the `id` field.
    /// - Returns: Dictionary matching driver schema.
    private func driverPayload(from data: [String: Any], driverId: String) -> [String: Any] {
        return [
            "id": driverId,
            "role": "driver",
            "name": data["name"] as? String ?? "",
            "email": data["email"] as? String ?? "",
            "phone": data["phone"] as? String ?? "",
            "assignedVehicleId": data["assignedVehicleId"] as? String ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }

    /// Ensures the default Firebase app is configured before using Firestore.
    private static func ensureFirebaseConfigured() {
#if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            if Thread.isMainThread {
                FirebaseApp.configure()
            } else {
                DispatchQueue.main.sync {
                    if FirebaseApp.app() == nil {
                        FirebaseApp.configure()
                    }
                }
            }
        }
#endif
    }

    /// Maps fleet drivers collection docs into fleet-driver models.
    private func mapFleetDriverDocsToFleetDrivers(_ docs: [QueryDocumentSnapshot], fleetId: String) -> [FleetDriverUser] {
        docs.compactMap { doc in
            let data = doc.data()
            let role = (data["role"] as? String ?? "driver").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard role == "driver" else {
                return nil
            }

            return FleetDriverUser(
                userId: doc.documentID,
                name: data["name"] as? String ?? "",
                email: data["email"] as? String ?? "",
                phone: data["phone"] as? String ?? "",
                fleetId: fleetId,
                role: role,
                assignedVehicleId: data["assignedVehicleId"] as? String ?? ""
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Maps users collection docs into fleet-driver models.
    private func mapUserDocsToFleetDrivers(_ docs: [QueryDocumentSnapshot], fleetId: String) -> [FleetDriverUser] {
        docs.compactMap { doc in
            let data = doc.data()
            let rawRole = (data["role"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !rawRole.isEmpty && rawRole != "driver" {
                return nil
            }
            let role = rawRole.isEmpty ? "driver" : rawRole

            let resolvedFleetId = (data["fleetId"] as? String)
                ?? (data["fleetID"] as? String)
                ?? (data["fleetName"] as? String)
                ?? fleetId

            return FleetDriverUser(
                userId: doc.documentID,
                name: data["name"] as? String ?? "",
                email: data["email"] as? String ?? "",
                phone: data["phone"] as? String ?? "",
                fleetId: resolvedFleetId,
                role: role,
                assignedVehicleId: data["assignedVehicleId"] as? String ?? ""
            )
        }
    }

    /// Merges driver lists from multiple Firestore sources by user id.
    private func mergeFleetDriverLists(_ lists: [[FleetDriverUser]]) -> [FleetDriverUser] {
        var mergedByUserId: [String: FleetDriverUser] = [:]

        for list in lists {
            for driver in list {
                if let existing = mergedByUserId[driver.userId] {
                    mergedByUserId[driver.userId] = mergeDriver(existing, with: driver)
                } else {
                    mergedByUserId[driver.userId] = driver
                }
            }
        }

        return mergedByUserId.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Keeps the primary model and fills only missing fields from secondary.
    private func mergeDriver(_ primary: FleetDriverUser, with secondary: FleetDriverUser) -> FleetDriverUser {
        FleetDriverUser(
            userId: primary.userId,
            name: primary.name.isEmpty ? secondary.name : primary.name,
            email: primary.email.isEmpty ? secondary.email : primary.email,
            phone: primary.phone.isEmpty ? secondary.phone : primary.phone,
            fleetId: primary.fleetId.isEmpty ? secondary.fleetId : primary.fleetId,
            role: primary.role.isEmpty ? secondary.role : primary.role,
            assignedVehicleId: primary.assignedVehicleId.isEmpty ? secondary.assignedVehicleId : primary.assignedVehicleId
        )
    }

    /// Fetches query documents from Firestore for async/await consumers.
    private func fetchDocuments(for query: Query) async throws -> [QueryDocumentSnapshot] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[QueryDocumentSnapshot], Error>) in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: snapshot?.documents ?? [])
            }
        }
    }

    /// Fetches users docs best-effort and returns an empty list when blocked by rules.
    private func fetchUserDriverDocsIfAllowed(for query: Query) async -> [QueryDocumentSnapshot] {
        (try? await fetchDocuments(for: query)) ?? []
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
