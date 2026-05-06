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
    @StateObject private var faultViewModel = FaultViewModel()

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

            // Tab 3 - Faults
            FaultListView()
                .tabItem {
                    Label("Faults", systemImage: "exclamationmark.triangle.fill")
                }
                .badge(faultViewModel.openFaultCount > 0 ? faultViewModel.openFaultCount : 0)

            // Tab 4 - Records
            RecordsTabView()
                .tabItem {
                    Label("Records", systemImage: "doc.text.fill")
                }

            // Tab 5 - Settings
            ManagerSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .accentColor(.navyPrimary)
        .environmentObject(fleetViewModel)
        .onAppear {
            startVehicleSyncIfPossible()
            startFaultSyncIfPossible()
        }
        .onChange(of: authViewModel.fleetId) { _, _ in
            startVehicleSyncIfPossible()
            startFaultSyncIfPossible()
        }
        .onDisappear {
            fleetViewModel.stopListening()
        }
    }

    // MARK: - Private Methods
    /// Starts vehicle sync only when a valid fleet id is available.
    private func startVehicleSyncIfPossible() {
        let normalizedFleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedFleetId.isEmpty else {
            fleetViewModel.stopListening()
            fleetViewModel.errorMessage = "Fleet setup is incomplete for this account."
            return
        }

        fleetViewModel.loadVehicles(fleetId: normalizedFleetId)
    }

    /// Starts fault listener only when a valid fleet id is available.
    private func startFaultSyncIfPossible() {
        let normalizedFleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else {
            return
        }

        faultViewModel.startFaultListener(fleetId: normalizedFleetId)
    }
}

#Preview {
    ManagerTabView()
        .environmentObject(AuthViewModel())
}
