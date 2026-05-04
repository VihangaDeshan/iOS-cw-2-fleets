//
//  ManagerHomeView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Manager Home View
struct ManagerHomeView: View {
    // MARK: - Stored Properties
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var fleetViewModel: FleetViewModel

    @Environment(\.managedObjectContext) private var context

    @State private var showAddVehicle = false
    @State private var showManageDrivers = false
    @State private var showRecords = false
    @State private var showFaults = false
    @State private var showAnalytics = false
    @State private var showUserProfile = false
    @State private var showNotifications = false
    @State private var selectedAlertVehicle: VehicleEntity? = nil

    @State private var heroPage = 0
    @State private var monthlySpend: Double = 0
    @State private var averageEfficiency: Double = 0
    @State private var bestVehicleRegistration = "-"
    @State private var openFaultCount = 0
    @State private var expiringInsuranceCount = 0
    @State private var latestCriticalMessage = "No critical alerts right now."
    @State private var notifications: [ManagerNotificationItem] = []
    @AppStorage("managerReadNotificationIDs") private var readNotificationIdsRaw: String = ""

    /// Total count shown on the bell badge:
    /// unread notifications + overdue vehicles + expiring licences.
    private var totalAlertCount: Int {
        let unread = notifications.filter { !$0.isRead }.count
        let overdue = fleetViewModel.vehicles.filter {
            fleetViewModel.vehicleStatus($0) == "Overdue"
        }.count
        let expiring = fleetViewModel.vehicles.filter {
            isLicenceExpiringSoon($0)
        }.count
        return unread + overdue + expiring
    }

    // MARK: - Greeting
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 0..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    var todayDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }

    var managerInitials: String {
        let name = authViewModel.currentUID
        let parts = name.split(separator: " ")

        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }

        return "M"
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    homeHeader
                        .padding(.top, 12)

                    heroSlider
                        .padding(.top, 8)

                    urgentAlertsSection

                    quickActionsSection

                    todayActivitySection

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 12)
            }
            .background(Color.systemGroupedBg)
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddVehicle) {
                AddVehicleView()
                    .environmentObject(fleetViewModel)
                    .environmentObject(authViewModel)
            }
            .sheet(isPresented: $showManageDrivers) {
                ManageDriversView()
                    .environmentObject(fleetViewModel)
                    .environmentObject(authViewModel)
            }
            .sheet(isPresented: $showRecords) {
                RecordsTabView()
                    .environmentObject(fleetViewModel)
            }
            .sheet(isPresented: $showFaults) {
                FaultListView()
                    .environmentObject(authViewModel)
                    .environmentObject(fleetViewModel)
            }
            .sheet(isPresented: $showAnalytics) {
                NavigationStack {
                    AnalyticsView()
                        .environmentObject(fleetViewModel)
                }
            }
            .sheet(isPresented: $showNotifications) {
                NavigationStack {
                    managerNotificationsView
                }
            }
            .fullScreenCover(isPresented: $showUserProfile) {
                NavigationStack {
                    UserProfileView()
                        .environmentObject(authViewModel)
                }
            }
            .onAppear {
                loadHomeMetrics()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
                loadHomeMetrics()
            }
        }
    }

    // MARK: - Home Header
    var homeHeader: some View {
        HStack {
            Text("Hi Manager")
                .font(.title.weight(.bold))

            Spacer()

            Button {
                showNotifications = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.title3)

                    if totalAlertCount > 0 {
                        Text("\(min(totalAlertCount, 9))")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.statusOverdue)
                            .clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }
                }
                .padding(.trailing, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View notifications")
            .accessibilityHint("Opens recent critical alerts and updates")

            Button {
                showUserProfile = true
            } label: {
                Circle()
                    .fill(Color.black)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                    )
            }
        }
    }

    // MARK: - Hero Slider
    var heroSlider: some View {
        TabView(selection: $heroPage) {
            fleetHeroCard
                .tag(0)

            efficiencyHeroCard
                .tag(1)

            riskHeroCard
                .tag(2)
        }
        .frame(height: 210)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    // MARK: - Fleet Hero Card
    var fleetHeroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FLEET STATUS")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(0.5)

                    Text("\(fleetViewModel.vehicles.count) Vehicles")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("MONTHLY SPEND")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(0.5)

                    Text("LKR \(String(format: "%.0f", monthlySpend))")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                }
            }

            statusProgressBar
                .padding(.top, 12)

            HStack(spacing: 16) {
                legendItem(
                    colour: .statusActive,
                    label: "Active",
                    count: fleetViewModel.activeCount
                )

                legendItem(
                    colour: .statusDueSoon,
                    label: "Due Soon",
                    count: fleetViewModel.dueSoonCount
                )

                legendItem(
                    colour: .statusOverdue,
                    label: "Overdue",
                    count: fleetViewModel.overdueCount
                )
            }
            .padding(.top, 8)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.navyPrimary, Color.navySecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
    }

    var efficiencyHeroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("EFFICIENCY")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .tracking(0.5)

                    Text("\(String(format: "%.1f", averageEfficiency)) km/L")
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("BEST VEHICLE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .tracking(0.5)

                    Text(bestVehicleRegistration)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.25 + Double(index) * 0.07))
                        .frame(width: 26, height: CGFloat(22 + index * 7))
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(hex: "60C98D"), Color(hex: "2F74C6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
    }

    var riskHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("→  \(openFaultCount) VEHICLE FAULT")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            Text("→  \(expiringInsuranceCount) INSURANCE WILL EXPIRE SOON")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            Text(latestCriticalMessage)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(hex: "FF3B30"), Color(hex: "A9487B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
    }

    var statusProgressBar: some View {
        let total = Double(fleetViewModel.vehicles.count)

        guard total > 0 else {
            return AnyView(
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 6)
            )
        }

        let activeWidth = Double(fleetViewModel.activeCount) / total
        let dueSoonWidth = Double(fleetViewModel.dueSoonCount) / total
        let overdueWidth = Double(fleetViewModel.overdueCount) / total

        return AnyView(
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if activeWidth > 0 {
                        Capsule()
                            .fill(Color.statusActive)
                            .frame(width: geo.size.width * activeWidth)
                    }

                    if dueSoonWidth > 0 {
                        Capsule()
                            .fill(Color.statusDueSoon)
                            .frame(width: geo.size.width * dueSoonWidth)
                    }

                    if overdueWidth > 0 {
                        Capsule()
                            .fill(Color.statusOverdue)
                            .frame(width: geo.size.width * overdueWidth)
                    }
                }
            }
            .frame(height: 6)
            .accessibilityLabel(
                "\(fleetViewModel.activeCount) active, " +
                "\(fleetViewModel.dueSoonCount) due soon, " +
                "\(fleetViewModel.overdueCount) overdue"
            )
        )
    }

    /// Builds a legend row item for fleet status counts.
    /// - Parameters:
    ///   - colour: Indicator color.
    ///   - label: Status label text.
    ///   - count: Status count value.
    /// - Returns: A small legend row view.
    func legendItem(colour: Color, label: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colour)
                .frame(width: 7, height: 7)

            Text("\(count) \(label)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
        }
    }

    // MARK: - Urgent Alerts
    var urgentAlertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Urgent Alerts")
                    .font(.caption.weight(.semibold))

                Spacer()

                Button("See All") {
                    showFaults = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.top, 14)

            let overdue = fleetViewModel.vehicles.filter {
                fleetViewModel.vehicleStatus($0) == "Overdue"
            }

            let expiring = fleetViewModel.vehicles.filter {
                isLicenceExpiringSoon($0)
            }

            let priorityNotifications = Array(
                notifications
                    .filter { !$0.isRead }
                    .sorted { $0.date > $1.date }
                    .prefix(2)
            )

            if overdue.isEmpty && expiring.isEmpty && priorityNotifications.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.statusActive)

                    Text("No urgent alerts today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
            } else {
                // Fault / notification alerts → tap to open Fault Reports
                ForEach(priorityNotifications) { item in
                    Button {
                        showFaults = true
                    } label: {
                        alertRow(
                            icon: item.level.icon,
                            iconBg: item.level.background,
                            iconColour: item.level.color,
                            title: item.title,
                            subtitle: item.subtitle
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Overdue service alerts → tap to open vehicle detail
                ForEach(overdue.prefix(2), id: \.id) { vehicle in
                    Button {
                        selectedAlertVehicle = vehicle
                    } label: {
                        alertRow(
                            icon: "exclamationmark.triangle.fill",
                            iconBg: Color.chipRedBg,
                            iconColour: Color.chipRedText,
                            title: "Service Overdue - \(vehicle.registration ?? "")",
                            subtitle: "\(abs(fleetViewModel.daysUntilService(vehicle))) days past due"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Expiring licence alerts → tap to open vehicle detail
                ForEach(expiring.prefix(2), id: \.id) { vehicle in
                    Button {
                        selectedAlertVehicle = vehicle
                    } label: {
                        alertRow(
                            icon: "doc.fill",
                            iconBg: Color.chipOrangeBg,
                            iconColour: Color.chipOrangeText,
                            title: "Licence Expiring - \(vehicle.registration ?? "")",
                            subtitle: licenceDaysText(vehicle)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // Hidden NavigationLink driven by selectedAlertVehicle
        .background(
            Group {
                if let vehicle = selectedAlertVehicle {
                    NavigationLink(
                        destination: VehicleDetailView(vehicle: vehicle)
                            .environmentObject(authViewModel)
                            .environmentObject(fleetViewModel),
                        isActive: Binding(
                            get: { selectedAlertVehicle != nil },
                            set: { if !$0 { selectedAlertVehicle = nil } }
                        )
                    ) { EmptyView() }
                    .hidden()
                }
            }
        )
    }

    /// Builds a single urgent alert row.
    /// - Parameters:
    ///   - icon: SF Symbol icon name.
    ///   - iconBg: Icon background color.
    ///   - iconColour: Icon foreground color.
    ///   - title: Primary row title.
    ///   - subtitle: Secondary row subtitle.
    /// - Returns: Styled alert row view.
    func alertRow(
        icon: String,
        iconBg: Color,
        iconColour: Color,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColour)
                .frame(width: 34, height: 34)
                .background(iconBg)
                .cornerRadius(9)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color(.systemGray3))
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    // MARK: - Quick Actions
    var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Actions")
                .font(.caption.weight(.semibold))
                .padding(.top, 14)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 7
            ) {
                quickActionCell(
                    icon: "truck.box.fill",
                    iconBg: Color(hex: "E8F0FB"),
                    title: "Add Vehicle",
                    subtitle: "Register new van"
                ) {
                    showAddVehicle = true
                }

                quickActionCell(
                    icon: "person.2.fill",
                    iconBg: Color(hex: "E4F5EA"),
                    title: "Manage Drivers",
                    subtitle: "Onboard and assign"
                ) {
                    showManageDrivers = true
                }

                quickActionCell(
                    icon: "chart.bar.fill",
                    iconBg: Color(hex: "FFF3E0"),
                    title: "Analytics",
                    subtitle: "View all analysis reports"
                ) {
                    showAnalytics = true
                }

                quickActionCell(
                    icon: "exclamationmark.triangle.fill",
                    iconBg: Color(hex: "FFEAEA"),
                    title: "View Faults",
                    subtitle: "\(openFaultCount) open faults"
                ) {
                    showFaults = true
                }
            }
        }
    }

    /// Builds a quick action card used in the home grid.
    /// - Parameters:
    ///   - icon: SF Symbol icon name.
    ///   - iconBg: Icon background color.
    ///   - title: Action title.
    ///   - subtitle: Action subtitle.
    ///   - action: Tap action callback.
    /// - Returns: Quick action button cell view.
    func quickActionCell(
        icon: String,
        iconBg: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.navyPrimary)
                    .frame(width: 36, height: 36)
                    .background(iconBg)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(minHeight: 28, alignment: .topLeading)
                }

                Spacer()
            }
            .padding(12)
            .frame(minHeight: 94)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        }
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    // MARK: - Today's Activity
    var todayActivitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today's Activity")
                    .font(.caption.weight(.semibold))

                Spacer()

                Text("All Records")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.top, 14)

            Text("No activity logged today")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        }
    }

    // MARK: - Helpers

    /// Returns true if vehicle licence expires within 30 days.
    /// - Parameter vehicle: Vehicle to evaluate.
    /// - Returns: True when expiry is within the next 30 days.
    func isLicenceExpiringSoon(_ vehicle: VehicleEntity) -> Bool {
        guard let expiry = vehicle.licenceExpiry else {
            return false
        }

        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return days >= 0 && days <= 30
    }

    /// Returns a readable licence expiry days label.
    /// - Parameter vehicle: Vehicle to evaluate.
    /// - Returns: Text describing licence expiry countdown.
    func licenceDaysText(_ vehicle: VehicleEntity) -> String {
        guard let expiry = vehicle.licenceExpiry else {
            return "Expiry date unknown"
        }

        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return "\(days) days remaining"
    }

    private func loadHomeMetrics() {
        let serviceRequest = ServiceRecordEntity.fetchRequest()
        let fuelRequest = FuelLogEntity.fetchRequest()
        let faultRequest = FaultReportEntity.fetchRequest()

        let faults = (try? context.fetch(faultRequest)) ?? []
        let activeFaults = faults.filter { ($0.status ?? "open") != "resolved" }

        do {
            let serviceRecords = try context.fetch(serviceRequest)
            let fuelLogs = try context.fetch(fuelRequest)

            let calendar = Calendar.current
            let month = calendar.component(.month, from: Date())
            let year = calendar.component(.year, from: Date())

            let monthServiceCost = serviceRecords.filter {
                guard let date = $0.date else { return false }
                return calendar.component(.month, from: date) == month &&
                    calendar.component(.year, from: date) == year
            }
            .reduce(0) { $0 + $1.costLKR }

            let monthFuelCost = fuelLogs.filter {
                guard let date = $0.date else { return false }
                return calendar.component(.month, from: date) == month &&
                    calendar.component(.year, from: date) == year
            }
            .reduce(0) { $0 + $1.totalCostLKR }

            monthlySpend = monthServiceCost + monthFuelCost

            let validEfficiencies = fuelLogs.filter { $0.kmPerLitre > 0 }
            averageEfficiency = validEfficiencies.isEmpty
                ? 0
                : validEfficiencies.reduce(0) { $0 + $1.kmPerLitre } / Double(validEfficiencies.count)

            if let bestFuel = validEfficiencies.max(by: { $0.kmPerLitre < $1.kmPerLitre }),
               let id = bestFuel.vehicleId,
               let vehicle = fleetViewModel.vehicles.first(where: { $0.id == id }) {
                bestVehicleRegistration = vehicle.registration ?? "-"
            } else {
                bestVehicleRegistration = "-"
            }
        } catch {
            monthlySpend = 0
            averageEfficiency = 0
            bestVehicleRegistration = "-"
        }

        openFaultCount = activeFaults.count

        expiringInsuranceCount = fleetViewModel.vehicles.filter { vehicle in
            guard let expiry = vehicle.insuranceExpiry else { return false }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
            return days >= 0 && days <= 30
        }.count

        rebuildNotifications(from: activeFaults)
    }

    private func rebuildNotifications(from activeFaults: [FaultReportEntity]) {
        var items: [ManagerNotificationItem] = []

        let sortedFaults = activeFaults.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }

        for fault in sortedFaults.prefix(10) {
            let registration = registrationForFault(fault)
            let message = (fault.descriptionText ?? "Fault reported")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let urgency = (fault.urgency ?? "medium").lowercased()
            let titlePrefix = (urgency == "high" || urgency == "critical") ? "Critical fault" : "Fault report"

            items.append(
                ManagerNotificationItem(
                    id: fault.id?.uuidString ?? UUID().uuidString,
                    title: "\(titlePrefix): \(registration)",
                    subtitle: message.isEmpty ? "Driver submitted a fault report." : message,
                    date: fault.createdAt ?? Date(),
                    level: (urgency == "high" || urgency == "critical") ? .danger : .info
                )
            )
        }

        for vehicle in fleetViewModel.vehicles {
            guard let expiry = vehicle.licenceExpiry else {
                continue
            }

            let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
            guard days >= 0 && days <= 30 else {
                continue
            }

            let registration = vehicle.registration?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanRegistration = (registration?.isEmpty == false) ? registration! : "Vehicle"

            items.append(
                ManagerNotificationItem(
                    id: "licence-\(vehicle.id?.uuidString ?? UUID().uuidString)",
                    title: "Licence expiry: \(cleanRegistration)",
                    subtitle: "Revenue licence expires in \(days) day(s).",
                    date: expiry,
                    level: days <= 7 ? .danger : .warning
                )
            )
        }

        let readIds = readNotificationIDs
        notifications = items
            .sorted { $0.date > $1.date }
            .map { item in
                var mutable = item
                mutable.isRead = readIds.contains(item.id)
                return mutable
            }

        latestCriticalMessage = notifications
            .first(where: { !$0.isRead })?.subtitle
            ?? notifications.first?.subtitle
            ?? "No critical alerts right now."
    }

    private func registrationForFault(_ fault: FaultReportEntity) -> String {
        guard let vehicleId = fault.vehicleId,
              let vehicle = fleetViewModel.vehicles.first(where: { $0.id == vehicleId }),
              let registration = vehicle.registration?.trimmingCharacters(in: .whitespacesAndNewlines),
              !registration.isEmpty else {
            return "Vehicle"
        }

        return registration
    }

    private var managerNotificationsView: some View {
        List {
            if notifications.isEmpty {
                ContentUnavailableView(
                    "No Notifications",
                    systemImage: "bell.slash",
                    description: Text("New fault reports and expiring licence alerts will appear here.")
                )
            } else {
                ForEach(notifications) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            if !item.isRead {
                                Text("NEW")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.level.color)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        HStack {
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(item.level.color)

                            Spacer()

                            if !item.isRead {
                                Button("Mark as read") {
                                    markAsRead(item.id)
                                }
                                .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                    .padding(10)
                    .background(item.level.background.opacity(item.isRead ? 0.35 : 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all") {
                    markAllAsRead()
                }
                .disabled(notifications.allSatisfy { $0.isRead })
            }
        }
    }

    private var readNotificationIDs: Set<String> {
        Set(
            readNotificationIdsRaw
                .split(separator: "|")
                .map(String.init)
        )
    }

    private func markAsRead(_ id: String) {
        var ids = readNotificationIDs
        ids.insert(id)
        readNotificationIdsRaw = ids.sorted().joined(separator: "|")

        notifications = notifications.map { item in
            var mutable = item
            if item.id == id {
                mutable.isRead = true
            }
            return mutable
        }

        latestCriticalMessage = notifications
            .first(where: { !$0.isRead })?.subtitle
            ?? notifications.first?.subtitle
            ?? "No critical alerts right now."
    }

    private func markAllAsRead() {
        let ids = Set(notifications.map(\.id))
        readNotificationIdsRaw = ids.sorted().joined(separator: "|")
        notifications = notifications.map { item in
            var mutable = item
            mutable.isRead = true
            return mutable
        }
        latestCriticalMessage = notifications.first?.subtitle ?? "No critical alerts right now."
    }
}

private struct ManagerNotificationItem: Identifiable {
    enum Level {
        case info
        case warning
        case danger

        var color: Color {
            switch self {
            case .info:
                return .navyPrimary
            case .warning:
                return .statusDueSoon
            case .danger:
                return .statusOverdue
            }
        }

        var background: Color {
            switch self {
            case .info:
                return Color(hex: "E8F0FB")
            case .warning:
                return Color(hex: "FFF8E1")
            case .danger:
                return Color(hex: "FFEAEA")
            }
        }

        var icon: String {
            switch self {
            case .info:
                return "info.circle.fill"
            case .warning:
                return "exclamationmark.circle.fill"
            case .danger:
                return "exclamationmark.triangle.fill"
            }
        }
    }

    let id: String
    let title: String
    let subtitle: String
    let date: Date
    let level: Level
    var isRead: Bool = false
}

#Preview {
    ManagerHomeView()
        .environmentObject(AuthViewModel())
        .environmentObject(FleetViewModel())
}
