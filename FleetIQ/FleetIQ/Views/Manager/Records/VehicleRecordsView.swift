//
//  VehicleRecordsView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI

// MARK: - Vehicle Records Hub
struct VehicleRecordsView: View {
    let vehicle: VehicleEntity

    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        List {
            Section("VEHICLE") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.registration ?? "Unknown")
                        .font(.headline)

                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("RECORD TYPES") {
                NavigationLink {
                    ServiceHistoryView(vehicle: vehicle)
                        .environmentObject(authViewModel)
                } label: {
                    Label("Service History", systemImage: "wrench.and.screwdriver")
                }

                NavigationLink {
                    FuelLogView(vehicle: vehicle)
                        .environmentObject(authViewModel)
                } label: {
                    Label("Fuel Logs", systemImage: "fuelpump")
                }

                NavigationLink {
                    TripHistoryView(vehicle: vehicle)
                        .environmentObject(authViewModel)
                } label: {
                    Label("Trip History", systemImage: "road.lanes")
                }
            }
        }
        .navigationTitle("Vehicle Records")
        .navigationBarTitleDisplayMode(.inline)
    }
}
