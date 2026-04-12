//
//  DriverHomeView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI

// MARK: - Driver Home View
struct DriverHomeView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = DriverHomeViewModel()

    @State private var showTripPlaceholder = false

    private var startKey: String {
        "\(authViewModel.currentUID)|\(authViewModel.fleetId)|\(authViewModel.assignedVehicleId)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerSection
                    vehicleTitle
                    vehicleSection
                    statsSection
                    quickActionsSection
                    todayActivitySection
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 26)
            }
            .background(Color.systemGroupedBg)
            .navigationBarHidden(true)
            .alert("Trip Logging", isPresented: $showTripPlaceholder) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Start Trip will be connected in the trip module steps.")
            }
        }
        .task(id: startKey) {
            viewModel.start(authViewModel: authViewModel)
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .center) {
            Text("Hi \(displayName)")
                .font(.system(size: 44, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer()

            Button {
            } label: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(.black)
            }

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.black)
        }
    }

    private var vehicleTitle: some View {
        Text("My Vehicle")
            .font(.title.weight(.bold))
    }

    // MARK: - Vehicle
    @ViewBuilder
    private var vehicleSection: some View {
        if let vehicle = viewModel.assignedVehicle {
            NavigationLink {
                MyVehicleDetailView(vehicle: vehicle)
                    .environmentObject(authViewModel)
            } label: {
                vehicleHeroCard(vehicle)
            }
            .buttonStyle(.plain)
        } else {
            ContentUnavailableView(
                "No Vehicle Assigned",
                systemImage: "car.fill",
                description: Text("Your manager has not assigned a vehicle yet.")
            )
            .frame(maxWidth: .infinity, minHeight: 230)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
    }

    private func vehicleHeroCard(_ vehicle: VehicleEntity) -> some View {
        let nextServiceMileage = viewModel.predictedNextServiceMileage(for: vehicle)
        let remainingDays = max(Int(((nextServiceMileage - vehicle.currentMileage) / 15.0).rounded(.down)), 0)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.serviceStatus(for: vehicle).uppercased())
                        .font(.system(size: 27, weight: .bold))
                        .opacity(0.001)
                        .frame(height: 0)

                    Text(viewModel.serviceStatus(for: vehicle).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(1)

                    Text(vehicle.registration ?? "Unknown")
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)

                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.95))
                }

                Spacer(minLength: 12)

                Text("View")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                metricPill(title: "TOTAL ODOMETER", value: String(format: "%.0f km", vehicle.currentMileage))
                metricPill(title: "NEXT SERVICE", value: remainingDays == 0 ? "Due now" : "In \(remainingDays) days")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(hex: "1A75DE"), Color(hex: "155FD4")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "1E88F2").opacity(0.55), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 150)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))
                .tracking(0.8)

            Text(value)
                .font(.system(size: 39, weight: .bold))
                .opacity(0.001)
                .frame(height: 0)

            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Stats
    private var statsSection: some View {
        HStack(spacing: 12) {
            statCard(title: "TRIPS TODAY", value: "\(viewModel.todayTrips)")
            statCard(title: "KM DRIVEN", value: String(format: "%.0f", viewModel.todayKmDriven))
            statCard(title: "OPEN FAULTS", value: "\(viewModel.openFaults)")
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "8595AD"))

            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Actions")
                    .font(.title.weight(.bold))

                Spacer()

                Text("Customize")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: "1562D4"))
            }

            HStack(spacing: 12) {
                actionCard(
                    icon: "play.circle",
                    iconColor: Color(hex: "1562D4"),
                    iconBackground: Color(hex: "E6EDF9"),
                    title: "Start Trip"
                ) {
                    showTripPlaceholder = true
                }

                NavigationLink {
                    ReportFaultView()
                        .environmentObject(authViewModel)
                } label: {
                    actionCardLabel(
                        icon: "exclamationmark.triangle",
                        iconColor: Color(hex: "C12822"),
                        iconBackground: Color(hex: "F8EAE9"),
                        title: "Report Fault"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionCard(
        icon: String,
        iconColor: Color,
        iconBackground: Color,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionCardLabel(icon: icon, iconColor: iconColor, iconBackground: iconBackground, title: title)
        }
        .buttonStyle(.plain)
    }

    private func actionCardLabel(
        icon: String,
        iconColor: Color,
        iconBackground: Color,
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 62, height: 62)

                Image(systemName: icon)
                    .font(.system(size: 31, weight: .semibold))
                    .opacity(0.001)
                    .frame(height: 0)

                Image(systemName: icon)
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: - Today Activity
    private var todayActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Activity")
                .font(.headline.weight(.bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Trip and fuel events will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Fuel logs today: \(viewModel.todayFuelLogs)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Helpers
    private var displayName: String {
        let trimmed = authViewModel.currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Driver"
        }

        let first = trimmed.split(separator: " ").first ?? "Driver"
        return String(first)
    }
}

#Preview {
    DriverHomeView()
        .environmentObject(AuthViewModel())
}
