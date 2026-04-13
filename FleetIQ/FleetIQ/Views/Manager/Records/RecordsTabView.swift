//
//  RecordsTabView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Records Tab View
struct RecordsTabView: View {
    @EnvironmentObject private var fleetViewModel: FleetViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var serviceCount = 0
    @State private var fuelCount = 0
    @State private var tripCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section("OVERVIEW") {
                    HStack {
                        Label("Service Records", systemImage: "wrench.and.screwdriver")
                        Spacer()
                        Text("\(serviceCount)")
                            .fontWeight(.bold)
                            .foregroundColor(.navyPrimary)
                    }

                    HStack {
                        Label("Fuel Logs", systemImage: "fuelpump")
                        Spacer()
                        Text("\(fuelCount)")
                            .fontWeight(.bold)
                            .foregroundColor(.navyPrimary)
                    }

                    HStack {
                        Label("Trip Logs", systemImage: "road.lanes")
                        Spacer()
                        Text("\(tripCount)")
                            .fontWeight(.bold)
                            .foregroundColor(.navyPrimary)
                    }
                }

                Section("VEHICLES") {
                    if fleetViewModel.vehicles.isEmpty {
                        Text("No vehicles available")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(fleetViewModel.vehicles, id: \.id) { vehicle in
                            NavigationLink {
                                VehicleRecordsView(vehicle: vehicle)
                                    .environmentObject(authViewModel)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vehicle.registration ?? "Unknown")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Records")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadCounts)
        }
    }

    private func loadCounts() {
        let serviceRequest = ServiceRecordEntity.fetchRequest()
        let fuelRequest = FuelLogEntity.fetchRequest()
        let tripRequest = TripLogEntity.fetchRequest()

        do {
            serviceCount = try context.count(for: serviceRequest)
            fuelCount = try context.count(for: fuelRequest)
            tripCount = try context.count(for: tripRequest)
        } catch {
            serviceCount = 0
            fuelCount = 0
            tripCount = 0
        }
    }
}
