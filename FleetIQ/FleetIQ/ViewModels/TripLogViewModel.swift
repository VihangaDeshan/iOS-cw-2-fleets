//
//  TripLogViewModel.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import Foundation
import Combine
import CoreData
import FirebaseFirestore

// MARK: - Trip Log View Model
@MainActor
final class TripLogViewModel: ObservableObject {
    @Published var trips: [TripLogEntity] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage = ""

    private let context = PersistenceController.shared.viewContext
    private let firestoreService = FirestoreService.shared
    private var tripListener: ListenerRegistration?

    deinit {
        tripListener?.remove()
    }

    /// Starts real-time cloud sync for trip logs of the selected vehicle.
    func startTripListener(fleetId: String, vehicleId: UUID, driverId: String) {
        tripListener?.remove()

        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDriverId = driverId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFleetId.isEmpty else {
            return
        }

        tripListener = firestoreService.listenToTripLogs(fleetId: normalizedFleetId) { [weak self] docs in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.syncTripDocsIntoLocal(
                    docs,
                    vehicleId: vehicleId,
                    driverId: normalizedDriverId
                )
            }
        }
    }

    /// Stops active trip listener.
    func stopTripListener() {
        tripListener?.remove()
        tripListener = nil
    }

    /// Loads all trip logs for a vehicle from CoreData.
    func loadTrips(for vehicleId: UUID) {
        isLoading = true
        errorMessage = ""

        let request = NSFetchRequest<TripLogEntity>(entityName: "TripLogEntity")
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            trips = try context.fetch(request)
        } catch {
            trips = []
            errorMessage = "Could not load trip logs."
        }

        isLoading = false
    }

    /// Saves a trip log to Firestore first, then CoreData.
    func addTrip(
        vehicleId: UUID,
        driverId: String,
        purpose: String,
        destination: String,
        startMileage: Double,
        endMileage: Double,
        date: Date,
        fleetId: String,
        vehicle: VehicleEntity?
    ) async -> Bool {
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDriverId = driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFleetId.isEmpty else {
            errorMessage = "Fleet ID is missing."
            return false
        }

        guard !normalizedDriverId.isEmpty else {
            errorMessage = "Driver session is missing."
            return false
        }

        guard !normalizedPurpose.isEmpty, !normalizedDestination.isEmpty else {
            errorMessage = "Purpose and destination are required."
            return false
        }

        guard endMileage >= startMileage else {
            errorMessage = "End mileage must be greater than or equal to start mileage."
            return false
        }

        let distanceKm = max(0, endMileage - startMileage)
        let tripId = UUID()

        isSaving = true
        defer { isSaving = false }

        // Persist locally first so the realtime listener upsert does not create a duplicate
        let trip = TripLogEntity(context: context)
        trip.id = tripId
        trip.vehicleId = vehicleId
        trip.driverId = normalizedDriverId
        trip.purpose = normalizedPurpose
        trip.destination = normalizedDestination
        trip.startMileage = startMileage
        trip.endMileage = endMileage
        trip.distanceKm = distanceKm
        trip.date = date

        if let vehicle {
            vehicle.currentMileage = max(vehicle.currentMileage, endMileage)
        }

        do {
            try context.save()
        } catch {
            errorMessage = "Could not save trip log locally."
            return false
        }

        // Attempt cloud sync but keep local record if it fails. Using same id prevents duplicates.
        do {
            let payload: [String: Any] = [
                "id": tripId.uuidString,
                "vehicleId": vehicleId.uuidString,
                "driverId": normalizedDriverId,
                "purpose": normalizedPurpose,
                "destination": normalizedDestination,
                "startMileage": startMileage,
                "endMileage": endMileage,
                "distanceKm": distanceKm,
                "date": Timestamp(date: date)
            ]

            try await firestoreService.saveTripLog(
                payload,
                fleetId: normalizedFleetId,
                logId: tripId.uuidString
            )
        } catch {
            errorMessage = "Cloud sync failed for trip log; saved locally."
            // still return true because local save succeeded
            loadTrips(for: vehicleId)
            return true
        }

        loadTrips(for: vehicleId)
        return true
    }

    /// Deletes a trip from CoreData and Firestore.
    func deleteTrip(
        _ trip: TripLogEntity,
        fleetId: String,
        vehicleId: UUID
    ) async {
        errorMessage = ""
        let tripId = trip.id?.uuidString ?? ""

        context.delete(trip)

        do {
            try context.save()
        } catch {
            errorMessage = "Could not delete trip locally."
            loadTrips(for: vehicleId)
            return
        }

        if !tripId.isEmpty {
            do {
                try await firestoreService.deleteTripLog(
                    fleetId: fleetId,
                    logId: tripId
                )
            } catch {
                errorMessage = "Deleted locally, but cloud delete failed."
            }
        }

        loadTrips(for: vehicleId)
    }

    private func syncTripDocsIntoLocal(
        _ docs: [QueryDocumentSnapshot],
        vehicleId: UUID,
        driverId: String
    ) {
        let vehicleIdString = vehicleId.uuidString

        let matchingDocs = docs.filter { doc in
            let data = doc.data()
            guard (data["vehicleId"] as? String ?? "") == vehicleIdString else {
                return false
            }

            let remoteDriverId = (data["driverId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return driverId.isEmpty || remoteDriverId.isEmpty || remoteDriverId == driverId
        }

        let syncedIDs: Set<UUID> = Set(matchingDocs.compactMap { doc in
            let data = doc.data()
            let rawId = (data["id"] as? String) ?? doc.documentID
            return UUID(uuidString: rawId)
        })

        let request = NSFetchRequest<TripLogEntity>(entityName: "TripLogEntity")
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        let existing = (try? context.fetch(request)) ?? []

        for item in existing {
            guard let existingId = item.id else {
                continue
            }

            if !syncedIDs.contains(existingId) {
                context.delete(item)
            }
        }

        for doc in matchingDocs {
            let data = doc.data()
            let rawId = (data["id"] as? String) ?? doc.documentID
            guard let tripUUID = UUID(uuidString: rawId) else {
                continue
            }

            let trip = upsertTripEntity(with: tripUUID)
            trip.id = tripUUID
            trip.vehicleId = vehicleId
            trip.driverId = (data["driverId"] as? String ?? "")
            trip.purpose = (data["purpose"] as? String ?? "")
            trip.destination = (data["destination"] as? String ?? "")
            trip.startMileage = numericValue(from: data["startMileage"])
            trip.endMileage = numericValue(from: data["endMileage"])
            trip.distanceKm = numericValue(from: data["distanceKm"])
            trip.date = parseDateValue(data["date"]) ?? Date()
        }

        try? context.save()
        loadTrips(for: vehicleId)
    }

    private func upsertTripEntity(with id: UUID) -> TripLogEntity {
        let request = NSFetchRequest<TripLogEntity>(entityName: "TripLogEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let created = TripLogEntity(context: context)
        created.id = id
        return created
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
}
