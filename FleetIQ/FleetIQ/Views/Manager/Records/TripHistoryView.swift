//
//  TripHistoryView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import CoreData
import FirebaseFirestore

// MARK: - Trip History View
struct TripHistoryView: View {
    let vehicle: VehicleEntity

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var trips: [TripLogEntity] = []
    @State private var errorText = ""
    @State private var tripListener: ListenerRegistration?

    private let firestoreService = FirestoreService.shared

    var body: some View {
        List {
            Section("SUMMARY") {
                HStack {
                    Label("Total Trips", systemImage: "road.lanes")
                    Spacer()
                    Text("\(trips.count)")
                        .fontWeight(.bold)
                        .foregroundColor(.navyPrimary)
                }

                HStack {
                    Label("Distance", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    Spacer()
                    Text(String(format: "%.1f km", totalDistance))
                        .fontWeight(.bold)
                        .foregroundColor(.navyPrimary)
                }
            }

            if !errorText.isEmpty {
                Section {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundColor(.statusOverdue)
                }
            }

            Section("TRIP LOGS") {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "No Trip Logs",
                        systemImage: "car.side",
                        description: Text("Driver-created trip logs for this vehicle will appear here")
                    )
                } else {
                    ForEach(trips, id: \.id) { trip in
                        row(for: trip)
                    }
                    .onDelete { offsets in
                        Task {
                            await deleteTrips(at: offsets)
                        }
                    }
                }
            }
        }
        .navigationTitle("Trip History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadTrips()
            startTripListener()
        }
        .onDisappear {
            tripListener?.remove()
            tripListener = nil
        }
        .refreshable {
            loadTrips()
        }
    }

    private var totalDistance: Double {
        trips.reduce(0) { $0 + $1.distanceKm }
    }

    private func row(for trip: TripLogEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trip.purpose ?? "Trip")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(String(format: "%.1f km", trip.distanceKm))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.navyPrimary)
            }

            Text(trip.destination ?? "-")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(mediumDate(trip.date ?? Date()))  ·  \(String(format: "%.0f", trip.startMileage)) to \(String(format: "%.0f", trip.endMileage)) km")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loadTrips() {
        guard let vehicleId = vehicle.id else {
            trips = []
            return
        }

        let request = TripLogEntity.fetchRequest()
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            trips = try context.fetch(request)
        } catch {
            trips = []
        }
    }

    private func deleteTrips(at offsets: IndexSet) async {
        errorText = ""
        var deletedIds: [String] = []

        for offset in offsets {
            if let id = trips[offset].id?.uuidString {
                deletedIds.append(id)
            }
            context.delete(trips[offset])
        }

        do {
            try context.save()
            loadTrips()
        } catch {
            errorText = "Could not delete trip log locally."
            return
        }

        let fleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fleetId.isEmpty else {
            return
        }

        for id in deletedIds {
            do {
                try await firestoreService.deleteTripLog(fleetId: fleetId, logId: id)
            } catch {
                errorText = "Deleted locally, but cloud delete failed."
            }
        }
    }

    private func startTripListener() {
        tripListener?.remove()
        tripListener = nil

        guard let vehicleId = vehicle.id else {
            return
        }

        let fleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fleetId.isEmpty else {
            return
        }

        tripListener = firestoreService.listenToTripLogs(fleetId: fleetId) { docs in
            Task { @MainActor in
                syncTripDocsIntoLocal(docs, vehicleId: vehicleId)
            }
        }
    }

    private func syncTripDocsIntoLocal(_ docs: [QueryDocumentSnapshot], vehicleId: UUID) {
        let vehicleIdString = vehicleId.uuidString

        let matchingDocs = docs.filter { doc in
            let data = doc.data()
            return (data["vehicleId"] as? String ?? "") == vehicleIdString
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
            guard let id = item.id else {
                continue
            }

            if !syncedIDs.contains(id) {
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
        loadTrips()
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

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        TripHistoryView(vehicle: VehicleEntity())
            .environmentObject(AuthViewModel())
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}
