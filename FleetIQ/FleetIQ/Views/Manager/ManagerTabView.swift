//
//  ManagerTabView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Manager Tab View
struct ManagerTabView: View {
    // MARK: - Stored Properties
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var fleetViewModel = FleetViewModel()

    // MARK: - Body
    var body: some View {
        TabView {
            // Tab 1 - Home
            ManagerHomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            // Tab 2 - Fleet
            FleetTabView()
                .tabItem {
                    Label("Fleet", systemImage: "truck.box.fill")
                }

            // Tab 3 - Faults (placeholder for now)
            Text("Faults - coming in Part 7")
                .tabItem {
                    Label("Faults", systemImage: "exclamationmark.triangle.fill")
                }

            // Tab 4 - Records (placeholder for now)
            Text("Records - coming in Part 8")
                .tabItem {
                    Label("Records", systemImage: "doc.text.fill")
                }

            // Tab 5 - Settings (placeholder for now)
            Text("Settings - coming in Part 13")
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .accentColor(.navyPrimary)
        .environmentObject(fleetViewModel)
        .onAppear {
            fleetViewModel.loadVehicles(fleetId: authViewModel.fleetId)
        }
    }
}

#Preview {
    ManagerTabView()
        .environmentObject(AuthViewModel())
}
