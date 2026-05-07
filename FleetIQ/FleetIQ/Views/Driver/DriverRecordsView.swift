//
//  DriverRecordsView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import CoreData
import FirebaseFirestore

// MARK: - Driver Records View
struct DriverRecordsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var assignedVehicle: VehicleEntity?
    @State private var trips: [TripLogEntity] = []
    @State private var fuelLogs: [FuelLogEntity] = []
    @State private var selectedFilter: DriverRecordFilter = .all

    private let firestoreService = FirestoreService.shared

    private var normalizedVehicleId: String {
        authViewModel.assignedVehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredEntries: [DriverRecordEntry] {
        combinedEntries.filter { entry in
            switch selectedFilter {
            case .all:
                return true
            case .trips:
                return entry.kind == .trip
            case .fuel:
                return entry.kind == .fuel
            }
        }
    }

    private var combinedEntries: [DriverRecordEntry] {
        let tripEntries = trips.map(DriverRecordEntry.trip)
        let fuelEntries = fuelLogs.map(DriverRecordEntry.fuel)
        return (tripEntries + fuelEntries).sorted { $0.date > $1.date }
    }

    private var monthTripDistance: Double {
        trips
            .filter { Calendar.current.isDate($0.date ?? .distantPast, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.distanceKm }
    }

    private var monthFuelCost: Double {
        fuelLogs
            .filter { Calendar.current.isDate($0.date ?? .distantPast, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.totalCostLKR }
    }

    var body: some View {
        NavigationStack {
            List {
                if let vehicle = assignedVehicle {
                    Section {
                        summaryCard(for: vehicle)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 14, bottom: 8, trailing: 14))
                    .listRowBackground(Color.clear)

                    Section {
                        filterPicker
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                    .listRowBackground(Color.clear)

                    Section("RECENT RECORDS") {
                        if filteredEntries.isEmpty {
                            Text(selectedFilter.emptyText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(filteredEntries, id: \.id) { entry in
                                switch entry {
                                case .trip(let trip):
                                    tripRow(trip)
                                case .fuel(let fuel):
                                    fuelRow(fuel)
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "No Vehicle Assigned",
                            systemImage: "doc.text",
                            description: Text("Ask your manager to assign a vehicle to view records.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Records")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: normalizedVehicleId) {
                loadRecords()
                await syncFromFirestore()
            }
            .refreshable {
                loadRecords()
                await syncFromFirestore()
            }
        }
    }

    private var filterPicker: some View {
        Picker("Type", selection: $selectedFilter) {
            ForEach(DriverRecordFilter.allCases, id: \.self) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private func summaryCard(for vehicle: VehicleEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vehicle.registration ?? "Vehicle")
                .font(.headline.weight(.bold))

            HStack {
                summaryItem(title: "Trips", value: "\(trips.count)")
                summaryItem(title: "Fuel Logs", value: "\(fuelLogs.count)")
            }

            HStack {
                summaryItem(title: "This Month KM", value: String(format: "%.1f", monthTripDistance))
                summaryItem(title: "This Month Fuel", value: "LKR \(String(format: "%.0f", monthFuelCost))")
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.navyPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tripRow(_ trip: TripLogEntity) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Trip", systemImage: "road.lanes")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.navyPrimary)

                Spacer()

                Text(String(format: "%.1f km", trip.distanceKm))
                    .font(.caption.weight(.bold))
                    .foregroundColor(.navyPrimary)
            }

            Text(trip.purpose ?? "Trip")
                .font(.subheadline.weight(.semibold))

            Text(trip.destination ?? "-")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(mediumDate(trip.date ?? Date()))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func fuelRow(_ fuel: FuelLogEntity) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Fuel", systemImage: "fuelpump")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.statusDueSoon)

                Spacer()

                Text("LKR \(String(format: "%.0f", fuel.totalCostLKR))")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.navyPrimary)
            }

            Text("\(String(format: "%.1f", fuel.litres)) L at \(String(format: "%.0f", fuel.mileage)) km")
                .font(.subheadline.weight(.semibold))

            Text("LKR \(String(format: "%.2f", fuel.costPerLitre))/L")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(mediumDate(fuel.date ?? Date()))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func syncFromFirestore() async {
        guard let vehicleUUID = UUID(uuidString: normalizedVehicleId) else { return }
        let fleetId = authViewModel.fleetId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fleetId.isEmpty else { return }

        // Sync trip logs
        if let tripDocs = try? await firestoreService.fetchTripLogs(
            fleetId: fleetId,
            vehicleId: vehicleUUID.uuidString) {
            for doc in tripDocs {
                let data = doc.data()
                let id = (data["id"] as? String).flatMap(UUID.init) ?? UUID(uuidString: doc.documentID) ?? UUID()
                let req = NSFetchRequest<TripLogEntity>(entityName: "TripLogEntity")
                req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                req.fetchLimit = 1
                let entity = (try? context.fetch(req).first) ?? TripLogEntity(context: context)
                entity.id = id
                entity.vehicleId = vehicleUUID
                entity.driverId = data["driverId"] as? String ?? ""
                entity.startMileage = (data["startMileage"] as? Double) ?? 0
                entity.endMileage = (data["endMileage"] as? Double) ?? 0
                entity.distanceKm = (data["distanceKm"] as? Double) ?? 0
                if let ts = data["date"] as? Timestamp { entity.date = ts.dateValue() }
            }
        }

        // Sync fuel logs
        if let fuelDocs = try? await firestoreService.fetchFuelLogs(
            fleetId: fleetId,
            vehicleId: vehicleUUID.uuidString) {
            for doc in fuelDocs {
                let data = doc.data()
                let id = (data["id"] as? String).flatMap(UUID.init) ?? UUID(uuidString: doc.documentID) ?? UUID()
                let req = NSFetchRequest<FuelLogEntity>(entityName: "FuelLogEntity")
                req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                req.fetchLimit = 1
                let entity = (try? context.fetch(req).first) ?? FuelLogEntity(context: context)
                entity.id = id
                entity.vehicleId = vehicleUUID
                entity.litres = (data["litres"] as? Double) ?? 0
                entity.totalCostLKR = (data["totalCostLKR"] as? Double) ?? 0
                if let ts = data["date"] as? Timestamp { entity.date = ts.dateValue() }
            }
        }

        try? context.save()
        loadRecords()
    }

    private func loadRecords() {
        guard let vehicleUUID = UUID(uuidString: normalizedVehicleId) else {
            assignedVehicle = nil
            trips = []
            fuelLogs = []
            return
        }

        let vehicleRequest = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        vehicleRequest.fetchLimit = 1
        vehicleRequest.predicate = NSPredicate(format: "id == %@", vehicleUUID as CVarArg)
        assignedVehicle = try? context.fetch(vehicleRequest).first

        let tripRequest = NSFetchRequest<TripLogEntity>(entityName: "TripLogEntity")
        tripRequest.predicate = NSPredicate(format: "vehicleId == %@", vehicleUUID as CVarArg)
        tripRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        trips = (try? context.fetch(tripRequest)) ?? []

        let fuelRequest = NSFetchRequest<FuelLogEntity>(entityName: "FuelLogEntity")
        fuelRequest.predicate = NSPredicate(format: "vehicleId == %@", vehicleUUID as CVarArg)
        fuelRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        fuelLogs = (try? context.fetch(fuelRequest)) ?? []
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

private enum DriverRecordFilter: String, CaseIterable {
    case all
    case trips
    case fuel

    var title: String {
        switch self {
        case .all:
            return "All"
        case .trips:
            return "Trips"
        case .fuel:
            return "Fuel"
        }
    }

    var emptyText: String {
        switch self {
        case .all:
            return "No records yet."
        case .trips:
            return "No trip records yet."
        case .fuel:
            return "No fuel logs yet."
        }
    }
}

private enum DriverRecordEntry {
    case trip(TripLogEntity)
    case fuel(FuelLogEntity)

    enum Kind {
        case trip
        case fuel
    }

    var id: String {
        switch self {
        case .trip(let trip):
            return "trip-\(trip.id?.uuidString ?? UUID().uuidString)"
        case .fuel(let fuel):
            return "fuel-\(fuel.id?.uuidString ?? UUID().uuidString)"
        }
    }

    var kind: Kind {
        switch self {
        case .trip:
            return .trip
        case .fuel:
            return .fuel
        }
    }

    var date: Date {
        switch self {
        case .trip(let trip):
            return trip.date ?? .distantPast
        case .fuel(let fuel):
            return fuel.date ?? .distantPast
        }
    }
}

#Preview {
    DriverRecordsView()
        .environmentObject(AuthViewModel())
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
