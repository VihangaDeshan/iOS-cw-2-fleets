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

    private var startKey: String {
        "\(authViewModel.currentUID)|\(authViewModel.fleetId)|\(authViewModel.assignedVehicleId)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    Text("My Vehicle")
                        .font(.title3.weight(.bold))
                        .padding(.horizontal, 16)

                    vehicleSection
                        .padding(.horizontal, 16)

                    statsSection
                        .padding(.horizontal, 16)

                    quickActionsSection
                        .padding(.horizontal, 16)

                    todayActivitySection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
            .background(Color.systemGroupedBg)
            .navigationBarHidden(true)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingTitle)
                    .font(.largeTitle.weight(.heavy))

                Text(authViewModel.currentUserName.isEmpty ? "Driver" : authViewModel.currentUserName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
            } label: {
                Image(systemName: "bell.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }

            Circle()
                .fill(Color.driverGreen)
                .frame(width: 42, height: 42)
                .overlay(
                    Text(initials(from: authViewModel.currentUserName))
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                )
        }
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
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func vehicleHeroCard(_ vehicle: VehicleEntity) -> some View {
        let nextServiceMileage = viewModel.predictedNextServiceMileage(for: vehicle)
        let remainingDays = max(Int(((nextServiceMileage - vehicle.currentMileage) / 15.0).rounded(.down)), 0)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.serviceStatus(for: vehicle).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(0.8)

                    Text(vehicle.registration ?? "Unknown")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundColor(.white)

                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer(minLength: 10)

                Text("View")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                metricPill(
                    title: "TOTAL ODOMETER",
                    value: String(format: "%.0f km", vehicle.currentMileage)
                )

                metricPill(
                    title: "NEXT SERVICE",
                    value: remainingDays == 0 ? "Due now" : "In \(remainingDays) days"
                )
            }

            ProgressView(value: viewModel.serviceProgress(for: vehicle))
                .tint(.white)
                .progressViewStyle(.linear)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.navyPrimary, Color.navySecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color.navyPrimary.opacity(0.25), radius: 14, x: 0, y: 8)
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.white.opacity(0.8))
                .tracking(0.7)

            Text(value)
                .font(.title3.weight(.heavy))
                .foregroundColor(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Stats
    private var statsSection: some View {
        HStack(spacing: 10) {
            statCard(title: "TRIPS TODAY", value: "\(viewModel.todayTrips)")
            statCard(title: "KM DRIVEN", value: String(format: "%.0f", viewModel.todayKmDriven))
            statCard(title: "OPEN FAULTS", value: "\(viewModel.openFaults)")
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)

            Text(value)
                .font(.title2.weight(.heavy))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title2.weight(.bold))

            Button {
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Report a Fault")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)

                        Text("Send urgent issue to manager")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.white)
                }
                .padding(16)
                .background(Color.statusOverdue)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                smallActionButton(icon: "map.fill", title: "Log Trip")
                smallActionButton(icon: "fuelpump.fill", title: "Log Fuel")
                smallActionButton(icon: "doc.text.fill", title: "My Records")
            }
        }
    }

    private func smallActionButton(icon: String, title: String) -> some View {
        Button {
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.driverGreen)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today Activity
    private var todayActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today’s Activity")
                .font(.title3.weight(.bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Trip and fuel events will appear here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Fuel logs today: \(viewModel.todayFuelLogs)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Helpers
    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good Morning"
        }

        if hour < 18 {
            return "Good Afternoon"
        }

        return "Good Evening"
    }

    private func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "DR"
        }

        let parts = trimmed.split(separator: " ")
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }

        return String(trimmed.prefix(2)).uppercased()
    }
}

#Preview {
    DriverHomeView()
        .environmentObject(AuthViewModel())
}
