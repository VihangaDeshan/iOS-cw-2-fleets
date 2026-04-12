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
        let url = try await ref.downloadURL()
        return url.absoluteString
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
            "name": data["name"] as? String ?? "",
            "email": data["email"] as? String ?? "",
            "phone": data["phone"] as? String ?? "",
            "assignedVehicleId": data["assignedVehicleId"] as? String ?? "",
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
