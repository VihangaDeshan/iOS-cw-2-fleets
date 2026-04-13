//
//  TripLogView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import CoreData

// MARK: - Trip Log View
struct TripLogView: View {
    let vehicle: VehicleEntity

    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = TripLogViewModel()
    @State private var showAddSheet = false

    private var vehicleId: UUID? {
        vehicle.id
    }

    var body: some View {
        List {
            Section("SUMMARY") {
                HStack {
                    Label("Trips Today", systemImage: "road.lanes")
                    Spacer()
                    Text("\(todayTripCount)")
                        .fontWeight(.bold)
                        .foregroundColor(.navyPrimary)
                }

                HStack {
                    Label("Total Distance", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    Spacer()
                    Text(String(format: "%.1f km", totalDistanceKm))
                        .fontWeight(.bold)
                        .foregroundColor(.navyPrimary)
                }
            }

            if !viewModel.errorMessage.isEmpty {
                Section {
                    Text(viewModel.errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.statusOverdue)
                }
            }

            Section("TRIPS") {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.trips.isEmpty {
                    ContentUnavailableView(
                        "No Trips Logged",
                        systemImage: "car.side",
                        description: Text("Tap + to record your first trip")
                    )
                } else {
                    ForEach(viewModel.trips, id: \.id) { trip in
                        tripRow(trip)
                    }
                    .onDelete { offsets in
                        Task {
                            await deleteTrips(at: offsets)
                        }
                    }
                }
            }
        }
        .navigationTitle("Trip Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(vehicleId == nil)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTripLogSheet(
                vehicle: vehicle,
                viewModel: viewModel
            )
            .environmentObject(authViewModel)
        }
        .onAppear {
            guard let vehicleId else {
                return
            }

            viewModel.loadTrips(for: vehicleId)
            viewModel.startTripListener(
                fleetId: authViewModel.fleetId,
                vehicleId: vehicleId,
                driverId: authViewModel.currentUID
            )
        }
        .onDisappear {
            viewModel.stopTripListener()
        }
    }

    private var todayTripCount: Int {
        viewModel.trips.filter { trip in
            guard let date = trip.date else {
                return false
            }

            return Calendar.current.isDateInToday(date)
        }.count
    }

    private var totalDistanceKm: Double {
        viewModel.trips.reduce(0) { $0 + $1.distanceKm }
    }

    private func deleteTrips(at offsets: IndexSet) async {
        guard let vehicleId else {
            return
        }

        let targetTrips: [TripLogEntity] = offsets.compactMap { index in
            guard viewModel.trips.indices.contains(index) else {
                return nil
            }

            return viewModel.trips[index]
        }

        for trip in targetTrips {
            await viewModel.deleteTrip(
                trip,
                fleetId: authViewModel.fleetId,
                vehicleId: vehicleId
            )
        }
    }

    private func tripRow(_ trip: TripLogEntity) -> some View {
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

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Add Trip Sheet
private struct AddTripLogSheet: View {
    let vehicle: VehicleEntity
    @ObservedObject var viewModel: TripLogViewModel

    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var purpose = ""
    @State private var destination = ""
    @State private var startMileage = ""
    @State private var endMileage = ""
    @State private var localError = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("TRIP DETAILS") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    TextField("Purpose", text: $purpose)
                    TextField("Destination", text: $destination)

                    TextField("Start Mileage (km)", text: $startMileage)
                        .keyboardType(.decimalPad)

                    TextField("End Mileage (km)", text: $endMileage)
                        .keyboardType(.decimalPad)
                }

                if !localError.isEmpty {
                    Section {
                        Text(localError)
                            .font(.subheadline)
                            .foregroundColor(.statusOverdue)
                    }
                }
            }
            .navigationTitle("Add Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(viewModel.isSaving)
                }
            }
            .onAppear {
                let currentMileage = vehicle.currentMileage
                startMileage = String(format: "%.0f", currentMileage)
                endMileage = String(format: "%.0f", currentMileage)
            }
            .disabled(viewModel.isSaving)
        }
    }

    private func save() async {
        localError = ""

        guard let vehicleId = vehicle.id else {
            localError = "Vehicle ID is missing."
            return
        }

        guard let startValue = Double(startMileage.replacingOccurrences(of: ",", with: "")),
              let endValue = Double(endMileage.replacingOccurrences(of: ",", with: "")) else {
            localError = "Please enter valid mileage values."
            return
        }

        let saved = await viewModel.addTrip(
            vehicleId: vehicleId,
            driverId: authViewModel.currentUID,
            purpose: purpose,
            destination: destination,
            startMileage: startValue,
            endMileage: endValue,
            date: date,
            fleetId: authViewModel.fleetId,
            vehicle: vehicle
        )

        if saved {
            dismiss()
        } else {
            localError = viewModel.errorMessage
        }
    }
}

