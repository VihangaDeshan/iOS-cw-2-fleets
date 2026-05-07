//
//  ManageDriversView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Manage Drivers View
struct ManageDriversView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var fleetViewModel: FleetViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var drivers: [FleetDriverUser] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorText = ""

    @State private var showAddDriver = false
    @State private var showAddVehicle = false

    private let firestoreService = FirestoreService.shared

    private var filteredDrivers: [FleetDriverUser] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return drivers
        }

        return drivers.filter { driver in
            driver.name.localizedCaseInsensitiveContains(query) ||
            driver.email.localizedCaseInsensitiveContains(query) ||
            driver.phone.localizedCaseInsensitiveContains(query)
        }
    }

    private var assignedDrivers: [FleetDriverUser] {
        filteredDrivers.filter { !$0.assignedVehicleId.isEmpty }
    }

    private var unassignedDrivers: [FleetDriverUser] {
        filteredDrivers.filter { $0.assignedVehicleId.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search", text: $searchText)
                    }
                }

                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundColor(.statusOverdue)
                    }
                }

                Section("ALL DRIVERS (\(drivers.count))") {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading fleet drivers...")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    } else if assignedDrivers.isEmpty {
                        Text("No assigned drivers")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(assignedDrivers, id: \.userId) { driver in
                            NavigationLink(destination: DriverDetailView(driver: driver)) {
                                driverRow(driver)
                            }
                        }
                    }
                }

                Section("UNASSIGNED") {
                    if unassignedDrivers.isEmpty {
                        Text("No unassigned drivers")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(unassignedDrivers, id: \.userId) { driver in
                            NavigationLink(destination: DriverDetailView(driver: driver)) {
                                driverRow(driver)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Manage Drivers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showAddVehicle = true
                    } label: {
                        Label("Add Vehicle", systemImage: "car.fill")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddDriver = true
                    } label: {
                        Text("+ Add")
                            .fontWeight(.bold)
                    }
                }
            }
            .sheet(isPresented: $showAddDriver, onDismiss: {
                Task {
                    await loadDrivers()
                }
            }) {
                AddDriverView()
                    .environmentObject(fleetViewModel)
                    .environmentObject(authViewModel)
            }
            .sheet(isPresented: $showAddVehicle, onDismiss: {
                Task {
                    await loadDrivers()
                }
            }) {
                AddVehicleView()
                    .environmentObject(fleetViewModel)
                    .environmentObject(authViewModel)
            }
            .task(id: authViewModel.fleetId) {
                await loadDrivers()
            }
            .onAppear {
                Task {
                    await loadDrivers()
                }
            }
        }
    }

    private func driverRow(_ driver: FleetDriverUser) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.navyPrimary)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(initials(driver.name))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(driver.name.isEmpty ? "Unnamed Driver" : driver.name)
                    .font(.headline)

                if let vehicle = fleetViewModel.vehicles.first(where: { $0.id?.uuidString == driver.assignedVehicleId }) {
                    Text("\(vehicle.registration ?? "Unknown") · \(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(driver.assignedVehicleId.isEmpty ? "No vehicle assigned" : "Assigned vehicle unavailable")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            statusChip(for: driver)
        }
        .padding(.vertical, 4)
    }

    private func statusChip(for driver: FleetDriverUser) -> some View {
        let hasFault = hasOpenFault(forAssignedVehicle: driver.assignedVehicleId)
        let status: String
        let color: Color

        if driver.assignedVehicleId.isEmpty {
            status = "Unassigned"
            color = .secondary
        } else if hasFault {
            status = "Fault Reported"
            color = .statusOverdue
        } else {
            status = "Active"
            color = .statusActive
        }

        return Text(status)
            .font(.caption.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func hasOpenFault(forAssignedVehicle assignedVehicleId: String) -> Bool {
        guard !assignedVehicleId.isEmpty,
              let vehicleUUID = UUID(uuidString: assignedVehicleId) else {
            return false
        }

        let request = FaultReportEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "vehicleId == %@ AND status != %@", vehicleUUID as CVarArg, "resolved")

        return (try? context.count(for: request)) ?? 0 > 0
    }

    @MainActor
    private func loadDrivers() async {
        let normalizedFleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else {
            drivers = []
            errorText = "Fleet ID is not ready yet."
            isLoading = false
            return
        }

        errorText = ""
        isLoading = true

        do {
            drivers = try await firestoreService.fetchFleetDriverUsers(fleetId: normalizedFleetId)
        } catch {
            drivers = []
            errorText = "Could not load fleet drivers from database."
        }

        isLoading = false
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }

        return String(name.prefix(2)).uppercased()
    }
}
