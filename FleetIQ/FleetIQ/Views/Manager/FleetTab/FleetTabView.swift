//
//  FleetTabView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Fleet Tab View
struct FleetTabView: View {
    // MARK: - Environment
    @EnvironmentObject var fleetViewModel: FleetViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    // MARK: - State
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var showAddVehicle = false

    // MARK: - Constants
    let filters = ["All", "Active", "Due Soon", "Overdue"]

    // MARK: - Filtered Vehicles
    var filteredVehicles: [VehicleEntity] {
        let searched = searchText.isEmpty
            ? fleetViewModel.vehicles
            : fleetViewModel.vehicles.filter {
                ($0.registration ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.make ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.model ?? "").localizedCaseInsensitiveContains(searchText)
            }

        if selectedFilter == "All" {
            return searched
        }

        return searched.filter {
            fleetViewModel.vehicleStatus($0) == selectedFilter
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search vehicles…", text: $searchText)
                    }
                    .padding(9)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityLabel("Search vehicles by registration, make or model")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { filter in
                                FilterPill(
                                    title: filter,
                                    count: countForFilter(filter),
                                    isSelected: selectedFilter == filter
                                ) {
                                    selectedFilter = filter
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    if fleetViewModel.isLoading {
                        VStack {
                            Spacer(minLength: 0)
                            ProgressView()
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else if fleetViewModel.vehicles.isEmpty {
                        ContentUnavailableView(
                            "No Vehicles",
                            systemImage: "truck.box",
                            description: Text("Tap + to add your first vehicle")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else if filteredVehicles.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search or filter")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredVehicles, id: \.id) { vehicle in
                                VehicleCardView(vehicle: vehicle)
                                    .padding(.horizontal, 12)
                            }
                        }
                        .padding(.top, 4)
                    }

                    Button {
                        showAddVehicle = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                            Text("Add New Vehicle to Fleet")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.navyPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    Color.navyPrimary.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                                )
                        )
                    }
                    .padding(12)
                    .padding(.bottom, 20)
                    .accessibilityLabel("Add a new vehicle to your fleet")
                    .accessibilityHint("Opens the add vehicle form")
                }
            }
            .background(Color.systemGroupedBg)
            .navigationTitle("Fleet")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddVehicle = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add new vehicle")
                }
            }
            .sheet(isPresented: $showAddVehicle) {
                AddVehicleView()
                    .environmentObject(fleetViewModel)
                    .environmentObject(authViewModel)
            }
        }
    }

    // MARK: - Helpers
    /// Returns the count of vehicles for the selected filter label.
    /// - Parameter filter: Filter title.
    /// - Returns: Number of vehicles matching that filter.
    private func countForFilter(_ filter: String) -> Int {
        switch filter {
        case "Active":
            return fleetViewModel.activeCount
        case "Due Soon":
            return fleetViewModel.dueSoonCount
        case "Overdue":
            return fleetViewModel.overdueCount
        default:
            return fleetViewModel.vehicles.count
        }
    }
}

// MARK: - Filter Pill Component
struct FilterPill: View {
    // MARK: - Stored Properties
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    // MARK: - Body
    var body: some View {
        Button(action: action) {
            Text(count > 0 ? "\(title) \(count)" : title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isSelected ? .white : Color.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(isSelected ? Color.navyPrimary : Color(.systemGray5))
                .clipShape(Capsule())
        }
        .accessibilityLabel("\(title) filter, \(count) vehicles")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    FleetTabView()
        .environmentObject(FleetViewModel())
        .environmentObject(AuthViewModel())
}
