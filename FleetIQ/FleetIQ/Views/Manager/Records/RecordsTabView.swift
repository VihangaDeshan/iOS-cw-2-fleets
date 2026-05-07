//
//  RecordsTabView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Unified Record Model
enum UnifiedRecordType: String {
    case service = "Service"
    case fuel = "Fuel"
    case trip = "Trip"
    case document = "V Document"
}

struct UnifiedRecord: Identifiable {
    let id = UUID()
    let type: UnifiedRecordType
    let date: Date
    let vehicle: VehicleEntity
    let title: String
    let subtitle: String
}

// MARK: - Records Tab View
struct RecordsTabView: View {
    @EnvironmentObject private var fleetViewModel: FleetViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var searchText = ""
    @State private var selectedFilter = "All"
    let filters = ["All", "Service", "Fuel", "Trip", "V Document"]

    @State private var allRecords: [UnifiedRecord] = []

    var filteredRecords: [UnifiedRecord] {
        var filtered = allRecords
        
        if selectedFilter != "All" {
            filtered = filtered.filter { $0.type.rawValue == selectedFilter }
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.subtitle.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered
    }

    var todayRecords: [UnifiedRecord] {
        filteredRecords.filter { Calendar.current.isDateInToday($0.date) || $0.type == .document }
    }

    var pastRecords: [UnifiedRecord] {
        filteredRecords.filter { !Calendar.current.isDateInToday($0.date) && $0.type != .document }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search", text: $searchText)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    
                    // Filter Strip
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { filter in
                                Button {
                                    selectedFilter = filter
                                } label: {
                                    Text(filter)
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedFilter == filter ? Color.navyPrimary.opacity(0.1) : Color(.systemGray6))
                                        .foregroundColor(selectedFilter == filter ? .navyPrimary : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    if selectedFilter == "V Document" {
                        // For V Document, just show all vehicles directly (not grouped by today/past)
                        sectionView(title: "ALL VEHICLES", records: todayRecords)
                    } else {
                        if !todayRecords.isEmpty {
                            sectionView(title: "TODAY", records: todayRecords)
                        }
                        if !pastRecords.isEmpty {
                            sectionView(title: "PAST DAYS", records: pastRecords)
                        }
                        
                        if todayRecords.isEmpty && pastRecords.isEmpty {
                            VStack {
                                Spacer(minLength: 40)
                                Text("No records found")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Records")
            .navigationBarTitleDisplayMode(.large)
            .onAppear(perform: loadData)
            .onChange(of: fleetViewModel.vehicles) { _, _ in loadData() }
        }
    }
    
    @ViewBuilder
    private func sectionView(title: String, records: [UnifiedRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1.0)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            VStack(spacing: 12) {
                ForEach(records) { record in
                    recordCard(record)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private func recordCard(_ record: UnifiedRecord) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconBackgroundColor(for: record.type))
                    .frame(width: 44, height: 44)
                
                Image(systemName: iconName(for: record.type))
                    .foregroundColor(iconColor(for: record.type))
                    .font(.system(size: 20))
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(record.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // View Button
            NavigationLink {
                destinationView(for: record)
            } label: {
                Text("View")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    // MARK: - Helpers
    
    @ViewBuilder
    private func destinationView(for record: UnifiedRecord) -> some View {
        switch record.type {
        case .service:
            ServiceHistoryView(vehicle: record.vehicle)
                .environmentObject(authViewModel)
        case .fuel:
            FuelLogView(vehicle: record.vehicle)
                .environmentObject(authViewModel)
        case .trip:
            TripHistoryView(vehicle: record.vehicle)
                .environmentObject(authViewModel)
        case .document:
            VehicleRecordsView(vehicle: record.vehicle)
                .environmentObject(authViewModel)
        }
    }
    
    private func iconName(for type: UnifiedRecordType) -> String {
        switch type {
        case .service: return "wrench.and.screwdriver.fill"
        case .fuel: return "fuelpump.fill"
        case .trip: return "road.lanes"
        case .document: return "car.fill"
        }
    }
    
    private func iconColor(for type: UnifiedRecordType) -> Color {
        switch type {
        case .service: return .navyPrimary
        case .fuel: return .orange
        case .trip: return .green
        case .document: return .red
        }
    }
    
    private func iconBackgroundColor(for type: UnifiedRecordType) -> Color {
        switch type {
        case .service: return Color.navyPrimary.opacity(0.15)
        case .fuel: return Color.orange.opacity(0.15)
        case .trip: return Color.green.opacity(0.15)
        case .document: return Color.red.opacity(0.15)
        }
    }

    private func loadData() {
        var items: [UnifiedRecord] = []
        
        let vehicles = fleetViewModel.vehicles
        let vehicleMap = Dictionary(uniqueKeysWithValues: vehicles.compactMap { $0.id != nil ? ($0.id!, $0) : nil })
        
        // 1. Service
        let serviceReq = ServiceRecordEntity.fetchRequest()
        if let services = try? context.fetch(serviceReq) {
            for service in services {
                guard let vId = service.vehicleId, let v = vehicleMap[vId] else { continue }
                items.append(UnifiedRecord(
                    type: .service,
                    date: service.date ?? Date(),
                    vehicle: v,
                    title: v.registration ?? "Unknown",
                    subtitle: "\(service.serviceType ?? "Service") • LKR \(String(format: "%.0f", service.costLKR))"
                ))
            }
        }
        
        // 2. Fuel
        let fuelReq = FuelLogEntity.fetchRequest()
        if let fuels = try? context.fetch(fuelReq) {
            for fuel in fuels {
                guard let vId = fuel.vehicleId, let v = vehicleMap[vId] else { continue }
                items.append(UnifiedRecord(
                    type: .fuel,
                    date: fuel.date ?? Date(),
                    vehicle: v,
                    title: v.registration ?? "Unknown",
                    subtitle: "Fuel Log • LKR \(String(format: "%.0f", fuel.totalCostLKR))"
                ))
            }
        }
        
        // 3. Trip
        let tripReq = TripLogEntity.fetchRequest()
        if let trips = try? context.fetch(tripReq) {
            for trip in trips {
                guard let vId = trip.vehicleId, let v = vehicleMap[vId] else { continue }
                items.append(UnifiedRecord(
                    type: .trip,
                    date: trip.date ?? Date(),
                    vehicle: v,
                    title: v.registration ?? "Unknown",
                    subtitle: "Trip Log • \(String(format: "%.1f", trip.distanceKm)) km"
                ))
            }
        }
        
        // 4. Vehicles (V Document)
        for v in vehicles {
            items.append(UnifiedRecord(
                type: .document,
                date: v.createdAt ?? Date(),
                vehicle: v,
                title: v.registration ?? "Unknown",
                subtitle: "Vehicle Document"
            ))
        }
        
        allRecords = items.sorted { $0.date > $1.date }
    }
}
