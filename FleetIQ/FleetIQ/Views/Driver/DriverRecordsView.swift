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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let vehicle = assignedVehicle {
                    summaryCard(for: vehicle)
                    
                    filterPicker
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECENT RECORDS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)
                            .padding(.horizontal, 4)

                        if filteredEntries.isEmpty {
                            ContentUnavailableView(
                                selectedFilter.title,
                                systemImage: "doc.text",
                                description: Text(selectedFilter.emptyText)
                            )
                            .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 12) {
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
                    }
                } else {
                    ContentUnavailableView(
                        "No Vehicle Assigned",
                        systemImage: "doc.text",
                        description: Text("Ask your manager to assign a vehicle to view records.")
                    )
                    .padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(Color.systemGroupedBg)
        .navigationTitle("Records")
        .task(id: normalizedVehicleId) {
            loadRecords()
            await syncFromFirestore()
        }
        .refreshable {
            loadRecords()
            await syncFromFirestore()
        }
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DriverRecordFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedFilter == filter ? Color.navyPrimary : Color(.systemBackground))
                            .foregroundColor(selectedFilter == filter ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedFilter == filter ? Color.clear : Color(.systemGray5), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    private func summaryCard(for vehicle: some VehicleEntity) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MONTHLY SUMMARY")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.8))
                        .tracking(1.5)
                    
                    Text(vehicle.registration ?? "VEHICLE")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 12) {
                summaryItem(title: "DISTANCE", value: String(format: "%.1f km", monthTripDistance))
                summaryItem(title: "FUEL COST", value: "LKR \(String(format: "%.0f", monthFuelCost))")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.navyPrimary, Color(hex: "2E5BA8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.navyPrimary.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
                .tracking(0.5)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tripRow(_ trip: TripLogEntity) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.navyPrimary.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "road.lanes")
                    .foregroundColor(.navyPrimary)
                    .font(.system(size: 18))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(trip.purpose ?? "Trip")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text(String(format: "%.1f km", trip.distanceKm))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.navyPrimary)
                }
                
                Text(trip.destination ?? "Local Trip")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(mediumDate(trip.date ?? Date()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    private func fuelRow(_ fuel: FuelLogEntity) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.statusActive.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "fuelpump.fill")
                    .foregroundColor(.statusActive)
                    .font(.system(size: 18))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Fuel Fill-up")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text("LKR \(String(format: "%.0f", fuel.totalCostLKR))")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.navyPrimary)
                }
                
                Text("\(String(format: "%.1f", fuel.litres)) L at \(String(format: "%.0f", fuel.mileage)) km")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(mediumDate(fuel.date ?? Date()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
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
