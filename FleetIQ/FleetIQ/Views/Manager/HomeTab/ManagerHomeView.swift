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
    @Environment(\.scenePhase) private var scenePhase

    @State private var showAddVehicle = false
    @State private var showManageDrivers = false
    @State private var showRecords = false
    @State private var showFaults = false
    @State private var showAnalytics = false
    @State private var showUserProfile = false
    @State private var showNotifications = false
    @State private var selectedAlertVehicle: VehicleEntity? = nil
    @State private var hasShownWelcome = false
    @State private var showExpiredDocsAlert = false
    @State private var expiredDocsSummary: [String] = []
    @State private var hasCheckedExpiredDocs = false

    @State private var heroPage = 0
    @State private var monthlySpend: Double = 0
    @State private var averageEfficiency: Double = 0
    @State private var bestVehicleRegistration = "-"
    @State private var openFaultCount = 0
    @State private var expiringInsuranceCount = 0
    @State private var latestCriticalMessage = "No critical alerts right now."
    @State private var notifications: [ManagerNotificationItem] = []
    @AppStorage("managerReadNotificationIDs") private var readNotificationIdsRaw: String = ""

    // Bug 2: Today's Activity State
    @State private var todayServiceRecords: [ServiceRecordEntity] = []
    @State private var todayFuelLogs: [FuelLogEntity] = []
    @State private var todayFaultReports: [FaultReportEntity] = []
    @State private var todayTripLogs: [TripLogEntity] = []

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
        let name = authViewModel.currentUserName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "M" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
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
                if !hasShownWelcome {
                    hasShownWelcome = true
                    NotificationService.shared.sendManagerWelcome(name: authViewModel.currentUserName)
                }
            }
            .alert("Expired Documents ⚠️", isPresented: $showExpiredDocsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The following documents require immediate renewal:\n\n\(expiredDocsSummary.joined(separator: "\n"))")
            }
            .onChange(of: fleetViewModel.vehicles.count) { _, _ in
                loadHomeMetrics()
            }
            .onChange(of: fleetViewModel.vehicles) { _, _ in
                loadHomeMetrics()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
                loadHomeMetrics()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    loadHomeMetrics()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .appSessionDidActivate)) { _ in
                loadHomeMetrics()
                NotificationService.shared.sendManagerWelcome(name: authViewModel.currentUserName)
            }
        }
    }

    // MARK: - Home Header
    var homeHeader: some View {
        HStack {
            Text({
                let name = authViewModel.currentUserName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let first = name.split(separator: " ").first.map(String.init) ?? ""
                return "Hi \(first.isEmpty ? "Manager" : first)"
            }())
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                ForEach(last7MonthsSpend().indices, id: \ .self) { index in
                    let values = last7MonthsSpend()
                    let maxVal = values.max() ?? 1
                    let barHeight = maxVal > 0
                        ? CGFloat(22) + CGFloat(48) * CGFloat(values[index]) / CGFloat(maxVal)
                        : 22
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(index == values.count - 1 ? 0.9 : 0.35))
                        .frame(width: 26, height: barHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    /// Returns total spending for each of the last 7 months, oldest first.
    private func last7MonthsSpend() -> [Double] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { monthsAgo -> Double in
            guard let targetDate = calendar.date(
                byAdding: .month, value: -monthsAgo, to: Date()),
                  let startOfMonth = calendar.date(
                    from: calendar.dateComponents([.year, .month], from: targetDate)),
                  let endOfMonth = calendar.date(
                    byAdding: .month, value: 1, to: startOfMonth)
            else { return 0 }

            let servicePredicate = NSPredicate(
                format: "date >= %@ AND date < %@",
                startOfMonth as NSDate, endOfMonth as NSDate)
            let fuelPredicate = NSPredicate(
                format: "date >= %@ AND date < %@",
                startOfMonth as NSDate, endOfMonth as NSDate)

            let serviceReq = ServiceRecordEntity.fetchRequest()
            serviceReq.predicate = servicePredicate
            let fuelReq = FuelLogEntity.fetchRequest()
            fuelReq.predicate = fuelPredicate

            let serviceTotal = (try? context.fetch(serviceReq))?.reduce(0) { $0 + $1.costLKR } ?? 0
            let fuelTotal = (try? context.fetch(fuelReq))?.reduce(0) { $0 + $1.totalCostLKR } ?? 0
            return serviceTotal + fuelTotal
        }
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

            // Deduplicate by registration to handle CoreData duplicates
            let overdue: [VehicleEntity] = {
                var seen = Set<String>()
                return fleetViewModel.vehicles.filter { v in
                    fleetViewModel.vehicleStatus(v) == "Overdue"
                        && seen.insert(v.registration ?? "").inserted
                }
            }()

            // Fault-only unread notifications (expiry items shown separately below)
            let priorityNotifications = Array(
                notifications
                    .filter {
                        !$0.isRead
                            && !$0.id.hasPrefix("licence-")
                            && !$0.id.hasPrefix("insurance-")
                            && !$0.id.hasPrefix("doc-")
                    }
                    .sorted { $0.date > $1.date }
            )

            // All expiry alerts (licence + insurance + docs), deduplicated by title
            // so duplicate CoreData records for the same vehicle collapse to one row.
            let expiryAlerts: [ManagerNotificationItem] = {
                var seenTitles = Set<String>()
                return notifications
                    .filter {
                        $0.id.hasPrefix("licence-")
                            || $0.id.hasPrefix("insurance-")
                            || $0.id.hasPrefix("doc-")
                    }
                    .sorted { $0.date > $1.date }
                    .filter { seenTitles.insert($0.title).inserted }
            }()

            if overdue.isEmpty && priorityNotifications.isEmpty && expiryAlerts.isEmpty {
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
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
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
                        ForEach(overdue, id: \.id) { vehicle in
                            NavigationLink(destination: VehicleDetailView(vehicle: vehicle)
                                            .environmentObject(authViewModel)
                                            .environmentObject(fleetViewModel)) {
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

                        // All expiry alerts (licence, insurance, emission) — deduplicated
                        ForEach(expiryAlerts) { item in
                            expiryAlertRow(item)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: 210)
            }
        }
    }

    /// Renders one expiry alert row, navigating to vehicle detail when possible.
    @ViewBuilder
    private func expiryAlertRow(_ item: ManagerNotificationItem) -> some View {
        let vehicleIdStr: String? = {
            if item.id.hasPrefix("licence-") {
                return String(item.id.dropFirst("licence-".count))
            } else if item.id.hasPrefix("insurance-") {
                return String(item.id.dropFirst("insurance-".count))
            }
            return nil
        }()
        let vehicle = vehicleIdStr.flatMap { uid in
            fleetViewModel.vehicles.first { $0.id?.uuidString == uid }
        }
        if let vehicle {
            NavigationLink(destination: VehicleDetailView(vehicle: vehicle)
                            .environmentObject(authViewModel)
                            .environmentObject(fleetViewModel)) {
                alertRow(
                    icon: "doc.fill",
                    iconBg: item.level.background,
                    iconColour: item.level.color,
                    title: item.title,
                    subtitle: item.subtitle
                )
            }
            .buttonStyle(.plain)
        } else {
            alertRow(
                icon: "doc.fill",
                iconBg: item.level.background,
                iconColour: item.level.color,
                title: item.title,
                subtitle: item.subtitle
            )
        }
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

                Button("All Records") {
                    showRecords = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.top, 14)

            let totalToday = todayServiceRecords.count
                + todayFuelLogs.count
                + todayFaultReports.count
                + todayTripLogs.count

            if totalToday == 0 {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .foregroundColor(.secondary)
                    Text("No activity logged today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(todayFaultReports.prefix(2)), id: \.id) { fault in
                        activityRow(
                            icon: "exclamationmark.triangle.fill",
                            iconColor: .statusOverdue,
                            title: "Fault reported",
                            detail: fault.descriptionText ?? "Fault submitted",
                            time: fault.createdAt
                        )
                        Divider().padding(.leading, 46)
                    }
                    ForEach(Array(todayServiceRecords.prefix(2)), id: \.id) { record in
                        activityRow(
                            icon: "wrench.and.screwdriver.fill",
                            iconColor: .navyPrimary,
                            title: record.serviceType ?? "Service logged",
                            detail: record.garageName ?? "Service record saved",
                            time: record.date
                        )
                        Divider().padding(.leading, 46)
                    }
                    ForEach(Array(todayFuelLogs.prefix(2)), id: \.id) { log in
                        activityRow(
                            icon: "fuelpump.fill",
                            iconColor: .statusDueSoon,
                            title: "Fuel fill-up logged",
                            detail: String(format: "%.1f L · LKR %.0f",
                                          log.litres, log.totalCostLKR),
                            time: log.date
                        )
                        Divider().padding(.leading, 46)
                    }
                    ForEach(Array(todayTripLogs.prefix(2)), id: \.id) { trip in
                        activityRow(
                            icon: "road.lanes",
                            iconColor: .driverGreen,
                            title: trip.purpose?.isEmpty == false
                                ? trip.purpose! : "Trip logged",
                            detail: String(format: "%.1f km · %@",
                                          trip.distanceKm,
                                          trip.destination ?? "-"),
                            time: trip.date
                        )
                    }
                }
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
            }
        }
    }

    private func activityRow(
        icon: String,
        iconColor: Color,
        title: String,
        detail: String,
        time: Date?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(iconColor)
                .frame(width: 26, height: 26)
                .background(iconColor.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let time {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

        // Reschedule or fire expiry push notifications for all vehicle documents.
        // Deduplicate by registration first so CoreData duplicate records for the
        // same physical vehicle don't fire two separate push notifications.
        var seenInsurance = Set<String>()
        var seenLicence = Set<String>()
        for vehicle in fleetViewModel.vehicles {
            guard let vehicleId = vehicle.id else { continue }
            let reg = vehicle.registration ?? "Vehicle"
            
            if let insuranceExpiry = vehicle.insuranceExpiry, !seenInsurance.contains(reg) {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: insuranceExpiry).day ?? Int.min
                if days <= 30 {
                    seenInsurance.insert(reg)
                }
                NotificationService.shared.rescheduleExpiryIfNeeded(
                    vehicleRegistration: reg,
                    documentType: "Insurance",
                    expiryDate: insuranceExpiry,
                    vehicleId: vehicleId)
            }
            if let licenceExpiry = vehicle.licenceExpiry, !seenLicence.contains(reg) {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: licenceExpiry).day ?? Int.min
                if days <= 30 {
                    seenLicence.insert(reg)
                }
                NotificationService.shared.rescheduleExpiryIfNeeded(
                    vehicleRegistration: reg,
                    documentType: "Revenue Licence",
                    expiryDate: licenceExpiry,
                    vehicleId: vehicleId)
            }
        }

        // Also scan DocumentEntity so all document types (emission, insurance, licence)
        // fire push notifications on app open even if VehicleEntity expiry fields are nil.
        var seenDocs = Set<String>()
        let allDocReq = DocumentEntity.fetchRequest()
        if let allDocs = try? context.fetch(allDocReq) {
            for doc in allDocs {
                guard let type = doc.type,
                      let expiry = doc.expiryDate,
                      let vehicleId = doc.vehicleId,
                      let matchedVehicle = fleetViewModel.vehicles.first(where: { $0.id == vehicleId })
                else { continue }
                
                let reg = matchedVehicle.registration ?? "Vehicle"
                let key = "\(reg)-\(type.capitalized)"
                
                if !seenDocs.contains(key) {
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? Int.min
                    if days <= 30 {
                        seenDocs.insert(key)
                    }
                    NotificationService.shared.rescheduleExpiryIfNeeded(
                        vehicleRegistration: reg,
                        documentType: type.capitalized,
                        expiryDate: expiry,
                        vehicleId: vehicleId)
                }
            }
        }

        rebuildNotifications(from: activeFaults)
        loadTodayActivity()
        checkAndAlertExpiredDocuments()
    }

    /// Checks vehicles' insurance and licence expiry dates and shows an in-app alert
    /// once per session when any have already expired.
    private func checkAndAlertExpiredDocuments() {
        guard !hasCheckedExpiredDocs, !fleetViewModel.vehicles.isEmpty else { return }
        hasCheckedExpiredDocs = true

        var expired: [String] = []
        let today = Calendar.current.startOfDay(for: Date())

        for vehicle in fleetViewModel.vehicles {
            let reg = vehicle.registration ?? "Vehicle"
            if let expiry = vehicle.insuranceExpiry,
               let days = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: expiry)).day,
               days < 0 {
                expired.append("\(reg) — Insurance (expired \(abs(days))d ago)")
            }
            if let expiry = vehicle.licenceExpiry,
               let days = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: expiry)).day,
               days < 0 {
                expired.append("\(reg) — Revenue Licence (expired \(abs(days))d ago)")
            }
        }

        // Also check DocumentEntity records in CoreData for emission and any other types.
        let docRequest = DocumentEntity.fetchRequest()
        if let docs = try? context.fetch(docRequest) {
            for doc in docs {
                guard let type = doc.type,
                      let expiry = doc.expiryDate,
                      let vehicleId = doc.vehicleId,
                      let vehicle = fleetViewModel.vehicles.first(where: { $0.id == vehicleId }),
                      let days = Calendar.current.dateComponents(
                          [.day], from: today,
                          to: Calendar.current.startOfDay(for: expiry)).day,
                      days < 0 else { continue }

                // Only add emission here (insurance/licence already covered from VehicleEntity above).
                let typeLC = type.lowercased()
                guard typeLC != "insurance" && typeLC != "licence" else { continue }
                let reg = vehicle.registration ?? "Vehicle"
                expired.append("\(reg) — \(type.capitalized) (expired \(abs(days))d ago)")
            }
        }

        if !expired.isEmpty {
            expiredDocsSummary = expired
            showExpiredDocsAlert = true
        }
    }

    // Bug 2: Load today's activity
    private func loadTodayActivity() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(
            byAdding: .day, value: 1, to: startOfDay) else { return }

        let dateRange = NSPredicate(
            format: "date >= %@ AND date < %@",
            startOfDay as NSDate,
            endOfDay as NSDate)

        let serviceReq = ServiceRecordEntity.fetchRequest()
        serviceReq.predicate = dateRange
        serviceReq.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false)]
        todayServiceRecords = (try? context.fetch(serviceReq)) ?? []

        let fuelReq = FuelLogEntity.fetchRequest()
        fuelReq.predicate = dateRange
        fuelReq.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false)]
        let allFuelToday = (try? context.fetch(fuelReq)) ?? []
        var seenFuelIds = Set<UUID>()
        todayFuelLogs = allFuelToday.filter { log in
            guard let id = log.id else { return false }
            return seenFuelIds.insert(id).inserted
        }

        let faultReq = FaultReportEntity.fetchRequest()
        faultReq.predicate = NSPredicate(
            format: "createdAt >= %@ AND createdAt < %@",
            startOfDay as NSDate,
            endOfDay as NSDate)
        faultReq.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)]
        todayFaultReports = (try? context.fetch(faultReq)) ?? []

        let tripReq = TripLogEntity.fetchRequest()
        tripReq.predicate = dateRange
        tripReq.sortDescriptors = [
            NSSortDescriptor(key: "date", ascending: false)]
        todayTripLogs = (try? context.fetch(tripReq)) ?? []
    }

    private func rebuildNotifications(from activeFaults: [FaultReportEntity]) {
        var items: [ManagerNotificationItem] = []
        let readIds = readNotificationIDs

        let sortedFaults = activeFaults.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }

        for fault in sortedFaults.prefix(10) {
            let registration = registrationForFault(fault)
            let message = (fault.descriptionText ?? "Fault reported")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let urgency = (fault.urgency ?? "medium").lowercased()
            let titlePrefix = (urgency == "high" || urgency == "critical") ? "Critical fault" : "Fault report"
            let faultIdStr = fault.id?.uuidString ?? UUID().uuidString

            items.append(
                ManagerNotificationItem(
                    id: faultIdStr,
                    title: "\(titlePrefix): \(registration)",
                    subtitle: message.isEmpty ? "Driver submitted a fault report." : message,
                    date: fault.createdAt ?? Date(),
                    level: (urgency == "high" || urgency == "critical") ? .danger : .info
                )
            )
            
            if let fId = fault.id, !readIds.contains(fId.uuidString) {
                NotificationService.shared.fireManagerFaultIfNeeded(
                    vehicleReg: registration,
                    description: message,
                    urgency: urgency,
                    faultId: fId
                )
            }
        }

        // Check insurance AND licence expiry for every vehicle (expired + upcoming 30 days).
        for vehicle in fleetViewModel.vehicles {
            let reg = vehicle.registration?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanReg = reg?.isEmpty == false ? reg! : "Vehicle"
            let vid = vehicle.id?.uuidString ?? UUID().uuidString

            if let expiry = vehicle.licenceExpiry {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                if days <= 30 {
                    items.append(expiryNotificationItem(
                        id: "licence-\(vid)",
                        reg: cleanReg,
                        type: "Revenue Licence",
                        days: days,
                        expiry: expiry))
                }
            }

            if let expiry = vehicle.insuranceExpiry {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                if days <= 30 {
                    items.append(expiryNotificationItem(
                        id: "insurance-\(vid)",
                        reg: cleanReg,
                        type: "Insurance",
                        days: days,
                        expiry: expiry))
                }
            }
        }

        // Check DocumentEntity (e.g. emission test) expiry.
        let docRequest = DocumentEntity.fetchRequest()
        if let docs = try? context.fetch(docRequest) {
            for doc in docs {
                guard let type = doc.type,
                      let expiry = doc.expiryDate,
                      let vehicleId = doc.vehicleId,
                      let matchedVehicle = fleetViewModel.vehicles.first(where: { $0.id == vehicleId })
                else { continue }

                let typeLC = type.lowercased()
                guard typeLC != "insurance" && typeLC != "licence" else { continue }

                let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                guard days <= 30 else { continue }

                let reg = matchedVehicle.registration ?? "Vehicle"
                let docId = doc.id?.uuidString ?? UUID().uuidString
                items.append(expiryNotificationItem(
                    id: "doc-\(docId)",
                    reg: reg,
                    type: type.capitalized,
                    days: days,
                    expiry: expiry))
            }
        }

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

    private func expiryNotificationItem(
        id: String,
        reg: String,
        type: String,
        days: Int,
        expiry: Date
    ) -> ManagerNotificationItem {
        let title: String
        let subtitle: String
        let level: ManagerNotificationItem.Level
        let notifDate: Date

        if days < 0 {
            title = "EXPIRED: \(type) — \(reg)"
            subtitle = "\(reg) \(type) EXPIRED \(abs(days)) day(s) ago! Renew immediately."
            level = .danger
            notifDate = Date()
        } else if days == 0 {
            title = "Expires TODAY: \(type) — \(reg)"
            subtitle = "\(reg) \(type) expires TODAY. Renew immediately."
            level = .danger
            notifDate = expiry
        } else if days <= 7 {
            title = "URGENT: \(type) expiring — \(reg)"
            subtitle = "\(reg) \(type) expires in \(days) day(s)."
            level = .danger
            notifDate = expiry
        } else {
            title = "\(type) expiry: \(reg)"
            subtitle = "\(reg) \(type) expires in \(days) day(s). Renew to avoid fines."
            level = .warning
            notifDate = expiry
        }

        return ManagerNotificationItem(id: id, title: title, subtitle: subtitle, date: notifDate, level: level)
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
