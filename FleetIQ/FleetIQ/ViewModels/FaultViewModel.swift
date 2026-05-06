//
//  FaultViewModel.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import Combine
import CoreData
import CoreLocation
import FirebaseFirestore
import FirebaseStorage
import UIKit
import UserNotifications

// MARK: - Fault View Model
@MainActor
final class FaultViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var faultReports: [FaultReportEntity] = []
    @Published var myFaults: [FaultReportEntity] = []
    @Published var isSending: Bool = false
    @Published var openFaultCount: Int = 0
    @Published private(set) var faultPhotoReferences: [UUID: [String]] = [:]

    // MARK: - Private Properties
    private let context = PersistenceController.shared.viewContext
    private let firestoreService = FirestoreService.shared
    private let locationService = LocationService()
    private var resolvingPhotoReferenceKeys: Set<String> = []

    private var managerFaultListener: ListenerRegistration?
    private var myFaultListener: ListenerRegistration?

    // MARK: - Lifecycle
    deinit {
        managerFaultListener?.remove()
        myFaultListener?.remove()
    }

    // MARK: - Public API

    /// Submits a fault report with GPS, optional photo upload(s), cloud save, then local save.
    /// Order: GPS -> photo upload -> Firestore save -> CoreData save.
    func submitFault(
        vehicleId: String,
        driverId: String,
        description: String,
        urgency: String,
        photos: [UIImage],
        fleetId: String
    ) async throws -> UUID {
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

        // 2) Upload photos if available (up to 3)
        let selectedPhotos = Array(photos.prefix(3))
        var photoReferences: [String] = []
        var hadUploadFailure = false

        for (index, photo) in selectedPhotos.enumerated() {
            let path = firestoreService.faultPhotoPath(
                fleetId: normalizedFleetId,
                faultId: faultUUID.uuidString,
                filename: "photo\(index + 1)"
            )

            do {
                let uploadedReference = try await firestoreService.uploadPhoto(photo, path: path)
                photoReferences.append(uploadedReference)
            } catch {
                // Keep report submission flowing even if optional photo upload fails.
                #if DEBUG
                let nsError = error as NSError
                print("[FaultViewModel] Photo upload fallback triggered: \(nsError.domain) (\(nsError.code)) - \(nsError.localizedDescription)")
                #endif

                if shouldUsePendingStoragePath(for: error) {
                    photoReferences.append("storage_path:\(path)")
                } else {
                    hadUploadFailure = true
                }
            }
        }

        let primaryPhotoReference = photoReferences.first(where: { $0.hasPrefix("http") })
            ?? photoReferences.first
            ?? (hadUploadFailure ? "upload_failed" : nil)

        // 3) Prepare payload
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

        if let primaryPhotoReference {
            payload["photoURL"] = primaryPhotoReference
        }

        if !photoReferences.isEmpty {
            payload["photoURLs"] = photoReferences
        }

        // 4) Attempt cloud save FIRST to ensure synchronization
        try await firestoreService.saveFaultReport(
            payload,
            fleetId: normalizedFleetId,
            faultId: faultUUID.uuidString
        )

        // 5) If cloud save succeeded, save locally
        let localFault = upsertFaultEntity(with: faultUUID)
        localFault.vehicleId = vehicleUUID
        localFault.driverId = normalizedDriverId
        localFault.descriptionText = normalizedDescription
        localFault.urgency = normalizedUrgency.isEmpty ? "medium" : normalizedUrgency
        localFault.status = "open"
        localFault.latitude = coordinate.latitude
        localFault.longitude = coordinate.longitude
        localFault.photoURL = primaryPhotoReference
        localFault.createdAt = Date()

        if !photoReferences.isEmpty {
            faultPhotoReferences[faultUUID] = deduplicatedPhotoReferences(photoReferences)
        }

        do {
            try context.save()
            
            // Insert into in-memory lists for immediate UI feedback
            myFaults.insert(localFault, at: 0)
            recalculateOpenFaultCount()
        } catch {
            throw NSError(domain: "FaultViewModel", code: -30, userInfo: [NSLocalizedDescriptionKey: "Failed to save fault locally."])
        }

        return faultUUID
    }

    /// Starts manager listener for all fleet faults.
    func startFaultListener(fleetId: String) {
        managerFaultListener?.remove()

        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else {
            faultReports = []
            recalculateOpenFaultCount()
            return
        }

        managerFaultListener = firestoreService.listenToFaultReports(fleetId: normalizedFleetId) { [weak self] docs in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.syncFaultDocsIntoState(docs, fleetId: normalizedFleetId, target: .manager)
            }
        }
    }

    /// Starts driver listener for only current driver's faults.
    func startMyFaultListener(fleetId: String, driverId: String) {
        myFaultListener?.remove()

        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDriverId = driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty, !normalizedDriverId.isEmpty else {
            myFaults = []
            recalculateOpenFaultCount()
            return
        }

        myFaultListener = firestoreService.listenToMyFaults(fleetId: normalizedFleetId, driverId: normalizedDriverId) { [weak self] docs in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.syncFaultDocsIntoState(docs, fleetId: normalizedFleetId, target: .driver)
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

    /// Returns all known photo references for a fault (URLs or storage placeholders).
    func photoReferences(for fault: FaultReportEntity) -> [String] {
        if let faultId = fault.id,
           let references = faultPhotoReferences[faultId],
           !references.isEmpty {
            return references
        }

        guard let single = fault.photoURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !single.isEmpty else {
            return []
        }

        return [single]
    }

    // MARK: - Private Helpers
    private enum FaultSyncTarget {
        case manager
        case driver
    }

    private func syncFaultDocsIntoState(
        _ docs: [QueryDocumentSnapshot],
        fleetId: String,
        target: FaultSyncTarget
    ) {
        let entities = docs.map { upsertFaultEntity(from: $0, fleetId: fleetId) }

        try? context.save()

        let sorted = entities.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }

        switch target {
        case .manager:
            let existingIds = Set(faultReports.compactMap { $0.id })
            let isInitialLoad = existingIds.isEmpty
            
            faultReports = sorted
            
            if !isInitialLoad {
                for fault in sorted {
                    guard let faultId = fault.id, !existingIds.contains(faultId) else { continue }
                    
                    Task {
                        let reg = fault.vehicleId.flatMap { vehicleId in
                            try? context.fetch(NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")).first(where: { $0.id == vehicleId })?.registration
                        } ?? "Vehicle"
                        
                        NotificationService.shared.sendNewFaultToManager(
                            vehicleReg: reg,
                            description: fault.descriptionText ?? "",
                            urgency: fault.urgency ?? "medium"
                        )
                    }
                }
            }
        case .driver:
            myFaults = sorted
            // Fire notification for any status that changed
            for fault in sorted {
                guard let faultId = fault.id else { continue }
                notifyDriverIfStatusChanged(
                    faultId: faultId,
                    newStatus: fault.status ?? "",
                    description: fault.descriptionText ?? "")
            }
        }

        recalculateOpenFaultCount()
    }

    private func upsertFaultEntity(from doc: QueryDocumentSnapshot, fleetId: String?) -> FaultReportEntity {
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
        let references = photoReferences(from: data)
        faultPhotoReferences[faultUUID] = references
        entity.photoURL = preferredPhotoReference(from: references)
        entity.latitude = numericValue(from: data["latitude"])
        entity.longitude = numericValue(from: data["longitude"])
        entity.createdAt = parseDateValue(data["createdAt"]) ?? Date()

        if let vehicleUUID = parseUUID(from: data["vehicleId"]) {
            entity.vehicleId = vehicleUUID
        }

        if let fleetId,
           !fleetId.isEmpty,
           !references.isEmpty {
            resolvePendingPhotoReferencesIfNeeded(
                references,
                faultId: faultUUID,
                fleetId: fleetId,
                entity: entity
            )
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

    private func photoReferences(from data: [String: Any]) -> [String] {
        var references: [String] = []

        if let list = data["photoURLs"] as? [String] {
            references.append(contentsOf: list)
        }

        if let single = data["photoURL"] as? String {
            references.append(single)
        }

        return deduplicatedPhotoReferences(references)
    }

    private func deduplicatedPhotoReferences(_ references: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for rawReference in references {
            let reference = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reference.isEmpty, !seen.contains(reference) else {
                continue
            }

            seen.insert(reference)
            output.append(reference)
        }

        return output
    }

    private func preferredPhotoReference(from references: [String]) -> String? {
        if let preferred = references.first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }) {
            return preferred
        }

        return references.first
    }

    private func resolvePendingPhotoReferencesIfNeeded(
        _ references: [String],
        faultId: UUID,
        fleetId: String,
        entity: FaultReportEntity
    ) {
        for reference in references where reference.hasPrefix("storage_path:") {
            let key = "\(faultId.uuidString)|\(reference)"
            guard !resolvingPhotoReferenceKeys.contains(key) else {
                continue
            }

            resolvingPhotoReferenceKeys.insert(key)

            Task {
                defer {
                    resolvingPhotoReferenceKeys.remove(key)
                }

                do {
                    guard let resolvedURL = try await firestoreService.resolveStoragePathReference(reference),
                          !resolvedURL.isEmpty,
                          entity.managedObjectContext != nil else {
                        return
                    }

                    let existing = faultPhotoReferences[faultId] ?? references
                    let replaced = existing.map { $0 == reference ? resolvedURL : $0 }
                    let deduplicated = deduplicatedPhotoReferences(replaced)
                    faultPhotoReferences[faultId] = deduplicated

                    let preferred = preferredPhotoReference(from: deduplicated)
                    entity.photoURL = preferred
                    try context.save()

                    var updatePayload: [String: Any] = [
                        "photoURLs": deduplicated,
                        "updatedAt": Timestamp(date: Date())
                    ]
                    if let preferred {
                        updatePayload["photoURL"] = preferred
                    }

                    try await firestoreService.updateFaultReport(
                        fleetId: fleetId,
                        faultId: faultId.uuidString,
                        data: updatePayload
                    )
                } catch {
                    #if DEBUG
                    let nsError = error as NSError
                    print("[FaultViewModel] Deferred photo URL resolution failed for \(faultId.uuidString): \(nsError.domain) (\(nsError.code)) - \(nsError.localizedDescription)")
                    #endif
                }
            }
        }
    }

    private func notifyDriverIfStatusChanged(
        faultId: UUID,
        newStatus: String,
        description: String
    ) {
        let current = newStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !current.isEmpty else { return }

        let key = "notified_status_\(faultId.uuidString)"
        let previous = UserDefaults.standard.string(forKey: key) ?? ""

        guard current != previous else { return }
        
        // Save the new status so we don't notify again for this state
        UserDefaults.standard.set(current, forKey: key)

        // Don't notify for the initial 'open' state when the driver first submits it
        if previous.isEmpty && current == "open" { return }

        NotificationService.shared.sendFaultStatusUpdate(
            newStatus: current,
            description: description,
            faultId: faultId)
    }

    private func vehicleRegistration(for vehicleId: UUID) async -> String {
        let request = NSFetchRequest<VehicleEntity>(
            entityName: "VehicleEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(
            format: "id == %@", vehicleId as CVarArg)
        return (try? context.fetch(request).first)?
            .registration ?? "Vehicle"
    }

    private func recalculateOpenFaultCount() {
        let source = faultReports.isEmpty ? myFaults : faultReports
        openFaultCount = source.filter { fault in
            (fault.status ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() != "resolved"
        }.count
    }

    /// Returns true when Storage reports object-not-found during immediate post-upload URL fetch.
    private func shouldUsePendingStoragePath(for error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == StorageErrorDomain,
           nsError.code == StorageErrorCode.objectNotFound.rawValue {
            return true
        }

        return nsError.localizedDescription.lowercased().contains("does not exist")
    }
}
