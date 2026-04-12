//
//  FaultViewModel.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import Foundation
import Combine
import CoreData
import CoreLocation
import FirebaseFirestore
import UIKit

// MARK: - Fault View Model
@MainActor
final class FaultViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var faultReports: [FaultReportEntity] = []
    @Published var myFaults: [FaultReportEntity] = []
    @Published var isSending: Bool = false
    @Published var openFaultCount: Int = 0

    // MARK: - Private Properties
    private let context = PersistenceController.shared.viewContext
    private let firestoreService = FirestoreService.shared
    private let locationService = LocationService()

    private var managerFaultListener: ListenerRegistration?
    private var myFaultListener: ListenerRegistration?

    // MARK: - Lifecycle
    deinit {
        managerFaultListener?.remove()
        myFaultListener?.remove()
    }

    // MARK: - Public API

    /// Submits a fault report with GPS, optional photo upload, cloud save, then local save.
    /// Order: GPS -> photo upload -> Firestore save -> CoreData save.
    func submitFault(
        vehicleId: String,
        driverId: String,
        description: String,
        urgency: String,
        photo: UIImage?,
        fleetId: String
    ) async throws {
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDriverId = driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUrgency = urgency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalizedFleetId.isEmpty else {
            throw NSError(domain: "FaultViewModel", code: -21, userInfo: [NSLocalizedDescriptionKey: "Fleet ID is required."])
        }

        guard !normalizedDriverId.isEmpty else {
            throw NSError(domain: "FaultViewModel", code: -22, userInfo: [NSLocalizedDescriptionKey: "Driver ID is required."])
        }

        guard !normalizedDescription.isEmpty else {
            throw NSError(domain: "FaultViewModel", code: -23, userInfo: [NSLocalizedDescriptionKey: "Fault description is required."])
        }

        guard let vehicleUUID = UUID(uuidString: vehicleId) else {
            throw NSError(domain: "FaultViewModel", code: -24, userInfo: [NSLocalizedDescriptionKey: "Invalid vehicle ID."])
        }

        isSending = true
        defer { isSending = false }

        let faultUUID = UUID()

        // 1) Get GPS
        let coordinate: CLLocationCoordinate2D
        do {
            coordinate = try await locationService.requestOneTimeLocation()
        } catch {
            // Keep fault reporting usable when simulator/device location is unavailable.
            coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        // 2) Upload photo if available
        var photoURL: String?
        if let photo {
            let path = firestoreService.faultPhotoPath(
                fleetId: normalizedFleetId,
                faultId: faultUUID.uuidString
            )
            do {
                photoURL = try await firestoreService.uploadPhoto(photo, path: path)
            } catch {
                // Keep report submission flowing even if optional photo upload fails.
                photoURL = "upload_failed"
            }
        }

        // 3) Save to Firestore
        var payload: [String: Any] = [
            "id": faultUUID.uuidString,
            "vehicleId": vehicleUUID.uuidString,
            "driverId": normalizedDriverId,
            "descriptionText": normalizedDescription,
            "description": normalizedDescription,
            "urgency": normalizedUrgency.isEmpty ? "medium" : normalizedUrgency,
            "status": "open",
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]

        if let photoURL {
            payload["photoURL"] = photoURL
        }

        try await firestoreService.saveFaultReport(
            payload,
            fleetId: normalizedFleetId,
            faultId: faultUUID.uuidString
        )

        // 4) Save to CoreData
        let localFault = upsertFaultEntity(with: faultUUID)
        localFault.vehicleId = vehicleUUID
        localFault.driverId = normalizedDriverId
        localFault.descriptionText = normalizedDescription
        localFault.urgency = normalizedUrgency.isEmpty ? "medium" : normalizedUrgency
        localFault.status = "open"
        localFault.latitude = coordinate.latitude
        localFault.longitude = coordinate.longitude
        localFault.photoURL = photoURL
        localFault.createdAt = Date()

        try context.save()

        myFaults.insert(localFault, at: 0)
        recalculateOpenFaultCount()
    }

    /// Starts manager listener for all fleet faults.
    func startFaultListener(fleetId: String) {
        managerFaultListener?.remove()

        managerFaultListener = firestoreService.listenToFaultReports(fleetId: fleetId) { [weak self] docs in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.syncFaultDocsIntoState(docs, target: .manager)
            }
        }
    }

    /// Starts driver listener for only current driver's faults.
    func startMyFaultListener(fleetId: String, driverId: String) {
        myFaultListener?.remove()

        myFaultListener = firestoreService.listenToMyFaults(fleetId: fleetId, driverId: driverId) { [weak self] docs in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.syncFaultDocsIntoState(docs, target: .driver)
            }
        }
    }

    /// Updates manager fault status in Firestore and local state.
    func updateStatus(
        fault: FaultReportEntity,
        status: String,
        fleetId: String
    ) async throws {
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let faultId = fault.id?.uuidString else {
            throw NSError(domain: "FaultViewModel", code: -25, userInfo: [NSLocalizedDescriptionKey: "Fault ID is missing."])
        }

        try await firestoreService.updateFaultStatus(
            fleetId: fleetId,
            faultId: faultId,
            status: normalizedStatus
        )

        fault.status = normalizedStatus

        if let managerIndex = faultReports.firstIndex(where: { $0.id == fault.id }) {
            faultReports[managerIndex].status = normalizedStatus
        }

        if let driverIndex = myFaults.firstIndex(where: { $0.id == fault.id }) {
            myFaults[driverIndex].status = normalizedStatus
        }

        try context.save()
        recalculateOpenFaultCount()
    }

    // MARK: - Private Helpers
    private enum FaultSyncTarget {
        case manager
        case driver
    }

    private func syncFaultDocsIntoState(_ docs: [QueryDocumentSnapshot], target: FaultSyncTarget) {
        let entities = docs.map { upsertFaultEntity(from: $0) }

        try? context.save()

        let sorted = entities.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }

        switch target {
        case .manager:
            faultReports = sorted
        case .driver:
            myFaults = sorted
        }

        recalculateOpenFaultCount()
    }

    private func upsertFaultEntity(from doc: QueryDocumentSnapshot) -> FaultReportEntity {
        let data = doc.data()

        let rawId = (data["id"] as? String) ?? doc.documentID
        let faultUUID = UUID(uuidString: rawId) ?? UUID()

        let entity = upsertFaultEntity(with: faultUUID)

        entity.id = faultUUID
        entity.driverId = (data["driverId"] as? String ?? "")
        entity.descriptionText = (data["descriptionText"] as? String)
            ?? (data["description"] as? String)
            ?? ""
        entity.urgency = (data["urgency"] as? String ?? "medium")
        entity.status = (data["status"] as? String ?? "open")
        entity.photoURL = data["photoURL"] as? String
        entity.latitude = numericValue(from: data["latitude"])
        entity.longitude = numericValue(from: data["longitude"])
        entity.createdAt = parseDateValue(data["createdAt"]) ?? Date()

        if let vehicleUUID = parseUUID(from: data["vehicleId"]) {
            entity.vehicleId = vehicleUUID
        }

        return entity
    }

    private func upsertFaultEntity(with id: UUID) -> FaultReportEntity {
        let request = NSFetchRequest<FaultReportEntity>(entityName: "FaultReportEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let created = FaultReportEntity(context: context)
        created.id = id
        return created
    }

    private func parseUUID(from value: Any?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }

        if let string = value as? String {
            return UUID(uuidString: string)
        }

        return nil
    }

    private func parseDateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }

        if let date = value as? Date {
            return date
        }

        return nil
    }

    private func numericValue(from value: Any?) -> Double {
        if let double = value as? Double {
            return double
        }

        if let int = value as? Int {
            return Double(int)
        }

        if let string = value as? String {
            return Double(string) ?? 0
        }

        return 0
    }

    private func recalculateOpenFaultCount() {
        let source = faultReports.isEmpty ? myFaults : faultReports
        openFaultCount = source.filter { fault in
            (fault.status ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() != "resolved"
        }.count
    }
}
