//
//  DriverHomeView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Driver Home View
struct DriverHomeView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = DriverHomeViewModel()

    @State private var showTripUnavailableAlert = false
    @State private var showDriverNotifications = false
    @State private var hasFireredLoginNotification = false
    @StateObject private var driverFaultVM = FaultViewModel()

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
            .alert("No Vehicle Assigned", isPresented: $showTripUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Ask your manager to assign a vehicle before creating trip logs.")
            }
            .alert("Document Warning ⚠️", isPresented: $viewModel.showExpiredDocsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your assigned vehicle has documents requiring attention:\n\n\(viewModel.expiredDocsSummary.joined(separator: "\n"))\n\nPlease notify your manager.")
            }
        }
        .task(id: startKey) {
            viewModel.start(authViewModel: authViewModel)

            let fleetId = authViewModel.fleetId
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let driverId = authViewModel.currentUID
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !fleetId.isEmpty, !driverId.isEmpty {
                driverFaultVM.startMyFaultListener(
                    fleetId: fleetId,
                    driverId: driverId)
            }

            // Fire welcome notification once per session
            if !hasFireredLoginNotification {
                hasFireredLoginNotification = true
                let name = authViewModel.currentUserName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                NotificationService.shared.sendDriverWelcome(name: name)
            }
        }
        .sheet(isPresented: $showDriverNotifications) {
            DriverNotificationsView(
                faultVM: driverFaultVM,
                fleetId: authViewModel.fleetId,
                expiredDocsSummary: viewModel.expiredDocsSummary
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .center) {
            Text("Hi \(displayName)")
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer()

            Button {
                showDriverNotifications = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.black)

                    let unresolved = driverFaultVM.myFaults.filter {
                        let s = ($0.status ?? "open").lowercased()
                        guard s != "open" && s != "resolved" && s != "acknowledged" else { return false }
                        let id = $0.id?.uuidString ?? ""
                        return !driverFaultVM.readNotificationIds.contains(id)
                    }.count
                    
                    let badgeCount = unresolved + viewModel.expiredDocsSummary.count

                    if badgeCount > 0 {
                        Text("\(min(badgeCount, 9))")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.statusOverdue)
                            .clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .accessibilityLabel("View notifications")

            NavigationLink {
                DriverProfileView()
                    .environmentObject(authViewModel)
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
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
        let remainingDays = viewModel.daysUntilService(for: vehicle)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.serviceStatus(for: vehicle).uppercased())
                        .font(.title2.weight(.bold))
                        .opacity(0.001)
                        .frame(height: 0)

                    Text(viewModel.serviceStatus(for: vehicle).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(1)

                    Text(vehicle.registration ?? "Unknown")
                        .font(.largeTitle.weight(.heavy))
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
                metricPill(title: "NEXT SERVICE", value: remainingDays < 0 ? "\(abs(remainingDays))d over" : (remainingDays == 0 ? "Due now" : "In \(remainingDays) days"))
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
                .font(.largeTitle.weight(.bold))
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
                .font(.caption.weight(.bold))
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
                if let vehicle = viewModel.assignedVehicle {
                    NavigationLink {
                        TripLogView(vehicle: vehicle)
                            .environmentObject(authViewModel)
                    } label: {
                        actionCardLabel(
                            icon: "play.circle",
                            iconColor: Color(hex: "1562D4"),
                            iconBackground: Color(hex: "E6EDF9"),
                            title: "Start Trip"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    actionCard(
                        icon: "play.circle",
                        iconColor: Color(hex: "1562D4"),
                        iconBackground: Color(hex: "E6EDF9"),
                        title: "Start Trip"
                    ) {
                        showTripUnavailableAlert = true
                    }
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
                    .font(.title.weight(.semibold))
                    .opacity(0.001)
                    .frame(height: 0)

                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
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
                if viewModel.todayActivityItems.isEmpty {
                    Text("No trip or fuel activity logged today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Fuel logs today: \(viewModel.todayFuelLogs)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.todayActivityItems) { item in
                        activityRow(item)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func activityRow(_ item: DriverActivityItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind == .trip ? "road.lanes" : "fuelpump")
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.kind == .trip ? Color.navyPrimary : Color.statusDueSoon)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
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

// MARK: - Driver Notifications View
private struct DriverNotificationsView: View {
    @ObservedObject var faultVM: FaultViewModel
    let fleetId: String
    let expiredDocsSummary: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !expiredDocsSummary.isEmpty {
                    Section("Expiring Documents") {
                        ForEach(expiredDocsSummary, id: \.self) { doc in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.badge.exclamationmark")
                                    .foregroundColor(doc.contains("Expired") ? .statusOverdue : .statusDueSoon)
                                    .font(.title3)
                                    .frame(width: 32, height: 32)
                                    .background((doc.contains("Expired") ? Color.statusOverdue : Color.statusDueSoon).opacity(0.12))
                                    .clipShape(Circle())
                                
                                Text(doc)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(faultVM.myFaults.isEmpty ? "" : "Fault Updates") {
                    if faultVM.myFaults.isEmpty {
                        ContentUnavailableView(
                            "No Fault Notifications",
                            systemImage: "bell.slash",
                            description: Text(
                                "Fault status updates from your manager appear here.")
                        )
                    } else {
                        ForEach(faultVM.myFaults.prefix(20), id: \.id) { fault in
                            notificationRow(for: fault)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if faultVM.myFaults.contains(where: {
                        let s = ($0.status ?? "open").lowercased()
                        guard s != "open" && s != "resolved" && s != "acknowledged" else { return false }
                        let id = $0.id?.uuidString ?? ""
                        return !faultVM.readNotificationIds.contains(id)
                    }) {
                        Button("Mark All as Read") {
                            markAllAsRead()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func markAllAsRead() {
        faultVM.markNotificationsRead()
    }

    private func notificationRow(
        for fault: FaultReportEntity
    ) -> some View {
        let status = (fault.status ?? "open")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let (icon, color, statusText): (String, Color, String) = {
            switch status {
            case "resolved":
                return ("checkmark.circle.fill",
                        Color.statusActive, "Resolved")
            case "workshop_booked", "workshop booked":
                return ("wrench.and.screwdriver.fill",
                        Color.statusDueSoon, "Workshop Booked")
            case "in_progress", "in progress":
                return ("hammer.fill",
                        Color.statusDueSoon, "In Progress")
            case "acknowledged":
                return ("eye.fill",
                        Color.navyPrimary, "Acknowledged")
            default:
                return ("exclamationmark.triangle.fill",
                        Color.statusOverdue, "Open")
            }
        }()

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(fault.descriptionText ?? "Fault report")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text("Status: \(statusText)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)

                if let date = fault.createdAt {
                    Text(date.formatted(
                        date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DriverHomeView()
        .environmentObject(AuthViewModel())
}
