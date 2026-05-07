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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryHero
                
                if !viewModel.errorMessage.isEmpty {
                    errorMessageView
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("RECENT TRIPS")
                    
                    if viewModel.isLoading {
                        loadingPlaceholder
                    } else if viewModel.trips.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.trips, id: \.id) { trip in
                                tripRow(trip)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 30)
            }
            .padding(16)
        }
        .background(Color.systemGroupedBg)
        .navigationTitle("Trip Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.navyPrimary)
                }
                .disabled(vehicleId == nil)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTripLogSheet(vehicle: vehicle, viewModel: viewModel)
                .environmentObject(authViewModel)
        }
        .onAppear {
            guard let vehicleId else { return }
            viewModel.loadTrips(for: vehicleId)
            viewModel.startTripListener(fleetId: authViewModel.fleetId, vehicleId: vehicleId, driverId: authViewModel.currentUID)
        }
        .onDisappear {
            viewModel.stopTripListener()
        }
    }

    private var todayTripCount: Int {
        viewModel.trips.filter { trip in
            guard let date = trip.date else { return false }
            return Calendar.current.isDateInToday(date)
        }.count
    }

    private var totalDistanceKm: Double {
        viewModel.trips.reduce(0) { $0 + $1.distanceKm }
    }

    // MARK: - Components
    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTIVITY SUMMARY")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.8))
                        .tracking(1.5)
                    
                    Text(vehicle.registration ?? "VEHICLE")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "road.lanes")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 12) {
                statBox(title: "TRIPS TODAY", value: "\(todayTripCount)")
                statBox(title: "TOTAL DISTANCE", value: String(format: "%.1f km", totalDistanceKm))
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

    private func statBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
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

    private var errorMessageView: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
            Text(viewModel.errorMessage)
                .font(.caption.weight(.medium))
        }
        .foregroundColor(.statusOverdue)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.statusOverdue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var loadingPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView().padding()
            Spacer()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Trips Logged",
            systemImage: "car.side",
            description: Text("Tap + to record your first trip.")
        )
        .padding(.top, 40)
    }

    private func tripRow(_ trip: TripLogEntity) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.navyPrimary.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "location.north.fill")
                    .foregroundColor(.navyPrimary)
                    .font(.system(size: 16))
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
                
                Text("\(mediumDate(trip.date ?? Date()))  ·  \(String(format: "%.0f", trip.startMileage)) to \(String(format: "%.0f", trip.endMileage)) km")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 4)
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
            ScrollView {
                VStack(spacing: 20) {
                    // Form Section
                    VStack(alignment: .leading, spacing: 12) {
                        headerView("TRIP INFORMATION")
                        
                        VStack(spacing: 0) {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                                .padding(14)
                            
                            Divider().padding(.leading, 14)
                            
                            inputRow(title: "Purpose", placeholder: "e.g. Client Delivery", text: $purpose)
                            Divider().padding(.leading, 14)
                            
                            inputRow(title: "Destination", placeholder: "e.g. City Hub", text: $destination)
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        headerView("ODOMETER READING")
                        
                        VStack(spacing: 0) {
                            inputRow(title: "Start km", placeholder: "0", text: $startMileage, keyboardType: .decimalPad)
                            Divider().padding(.leading, 14)
                            inputRow(title: "End km", placeholder: "0", text: $endMileage, keyboardType: .decimalPad)
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if !localError.isEmpty {
                        errorBanner
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(16)
            }
            .background(Color.systemGroupedBg)
            .navigationTitle("Add Trip Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
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
        }
    }

    private func inputRow(title: String, placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            TextField(placeholder, text: text)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboardType)
        }
        .padding(14)
    }

    private func headerView(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 4)
    }

    private var errorBanner: some View {
        Text(localError)
            .font(.caption.weight(.bold))
            .foregroundColor(.white)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.statusOverdue)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

