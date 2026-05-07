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
    @State private var syncToggle = false
    @StateObject private var driverFaultVM = FaultViewModel()

    private var startKey: String {
        "\(authViewModel.currentUID)|\(authViewModel.fleetId)|\(authViewModel.assignedVehicleId)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                        .padding(.top, 12)

                    vehicleSection
                    
                    statsSection
                    
                    quickActionsSection
                    
                    todayActivitySection
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 30)
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

            let fleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
            let driverId = authViewModel.currentUID.trimmingCharacters(in: .whitespacesAndNewlines)

            if !fleetId.isEmpty, !driverId.isEmpty {
                driverFaultVM.startMyFaultListener(fleetId: fleetId, driverId: driverId)
            }

            if !hasFireredLoginNotification {
                hasFireredLoginNotification = true
                NotificationService.shared.sendDriverWelcome(name: authViewModel.currentUserName)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DriverAnalyticsDidSync"))) { _ in
            syncToggle.toggle()
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Hi \(displayName)")
                    .font(.title.weight(.bold))
                    .foregroundColor(.primary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    showDriverNotifications = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .padding(10)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)

                        let unresolved = driverFaultVM.myFaults.filter {
                            let s = ($0.status ?? "open").lowercased()
                            guard s != "open" && s != "resolved" && s != "acknowledged" else { return false }
                            let id = $0.id?.uuidString ?? ""
                            return !driverFaultVM.readNotificationIds.contains(id)
                        }.count
                        
                        let badgeCount = unresolved + viewModel.expiredDocsSummary.count

                        if badgeCount > 0 {
                            Text("\(badgeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.statusOverdue)
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }

                NavigationLink {
                    DriverProfileView()
                        .environmentObject(authViewModel)
                } label: {
                    Text(managerInitials)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.navyPrimary)
                        .clipShape(Circle())
                }
            }
        }
    }

    private var managerInitials: String {
        let name = authViewModel.currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "D" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    // MARK: - Vehicle
    @ViewBuilder
    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MY ASSIGNED VEHICLE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

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
                    description: Text("Ask your manager for a vehicle assignment.")
                )
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func vehicleHeroCard(_ vehicle: VehicleEntity) -> some View {
        let remainingDays = viewModel.daysUntilService(for: vehicle)
        let status = viewModel.serviceStatus(for: vehicle)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.uppercased())
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.8))
                        .tracking(1.5)

                    Text(vehicle.registration ?? "UNKNOWN")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("\(vehicle.make ?? "") \(vehicle.model ?? "")")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                metricPill(title: "ODOMETER", value: String(format: "%.0f km", vehicle.currentMileage))
                metricPill(title: "NEXT SERVICE", value: remainingDays < 0 ? "OVERDUE" : "\(remainingDays)d")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 220)
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

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Stats
    private var statsSection: some View {
        HStack(spacing: 12) {
            statCard(title: "TRIPS", value: "\(viewModel.todayTrips)", icon: "road.lanes")
            statCard(title: "DISTANCE", value: String(format: "%.0f km", viewModel.todayKmDriven), icon: "gauge.with.needle")
            statCard(title: "FAULTS", value: "\(viewModel.openFaults)", icon: "exclamationmark.octagon")
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK ACTIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            HStack(spacing: 12) {
                if let vehicle = viewModel.assignedVehicle {
                    NavigationLink {
                        TripLogView(vehicle: vehicle)
                            .environmentObject(authViewModel)
                    } label: {
                        actionCard(title: "Start Trip", icon: "play.fill", color: .navyPrimary)
                    }
                } else {
                    Button {
                        showTripUnavailableAlert = true
                    } label: {
                        actionCard(title: "Start Trip", icon: "play.fill", color: .secondary)
                    }
                }

                NavigationLink {
                    ReportFaultView()
                        .environmentObject(authViewModel)
                } label: {
                    actionCard(title: "Report Fault", icon: "exclamationmark.bubble.fill", color: .statusOverdue)
                }
            }
        }
    }

    private func actionCard(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    // MARK: - Today Activity
    private var todayActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY'S ACTIVITY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                
                Spacer()
                
                NavigationLink {
                    DriverRecordsView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.navyPrimary)
                }
            }

            VStack(spacing: 0) {
                if viewModel.todayActivityItems.isEmpty {
                    Text("No activity logged today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 30)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(viewModel.todayActivityItems.prefix(5)) { item in
                        activityRow(item)
                        if item.id != viewModel.todayActivityItems.prefix(5).last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
    }

    private func activityRow(_ item: DriverActivityItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .trip ? "road.lanes" : "fuelpump.fill")
                .font(.subheadline)
                .foregroundStyle(item.kind == .trip ? Color.navyPrimary : Color.statusDueSoon)
                .frame(width: 32, height: 32)
                .background((item.kind == .trip ? Color.navyPrimary : Color.statusDueSoon).opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    // MARK: - Helpers
    private var displayName: String {
        let trimmed = authViewModel.currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Driver" }
        return String(trimmed.split(separator: " ").first ?? "Driver")
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
