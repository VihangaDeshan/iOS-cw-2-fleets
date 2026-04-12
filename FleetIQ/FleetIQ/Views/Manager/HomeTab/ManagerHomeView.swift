//
//  ManagerHomeView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Manager Home View
struct ManagerHomeView: View {
    // MARK: - Stored Properties
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var fleetViewModel: FleetViewModel

    @State private var showAddVehicle = false
    @State private var showAddDriver = false
    @State private var showRecords = false
    @State private var showFaults = false

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
                    fleetHeroCard
                        .padding(.top, 8)

                    urgentAlertsSection

                    quickActionsSection

                    todayActivitySection

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 12)
            }
            .background(Color.systemGroupedBg)
            .navigationTitle("\(greeting) 👋")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Circle()
                        .fill(Color.navyPrimary)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(managerInitials)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .accessibilityLabel("Manager profile")
                }
            }
            .sheet(isPresented: $showAddVehicle) {
                AddVehicleView()
                    .environmentObject(fleetViewModel)
                    .environmentObject(authViewModel)
            }
            .sheet(isPresented: $showAddDriver) {
                AddDriverView()
                    .environmentObject(fleetViewModel)
            }
            .sheet(isPresented: $showRecords) {
                RecordsTabView()
                    .environmentObject(fleetViewModel)
            }
            .sheet(isPresented: $showFaults) {
                FaultsTabView()
            }
        }
    }

    // MARK: - Fleet Hero Card
    var fleetHeroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FLEET STATUS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .tracking(0.5)

                    Text("\(fleetViewModel.vehicles.count) Vehicles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    Text(todayDateString)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()
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
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.65))
        }
    }

    // MARK: - Urgent Alerts
    var urgentAlertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Urgent Alerts")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Text("See All")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            .padding(.top, 14)

            let overdue = fleetViewModel.vehicles.filter {
                fleetViewModel.vehicleStatus($0) == "Overdue"
            }

            let expiring = fleetViewModel.vehicles.filter {
                isLicenceExpiringSoon($0)
            }

            if overdue.isEmpty && expiring.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.statusActive)

                    Text("No urgent alerts today")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
            } else {
                ForEach(overdue.prefix(2), id: \.id) { vehicle in
                    alertRow(
                        icon: "exclamationmark.triangle.fill",
                        iconBg: Color.chipRedBg,
                        iconColour: Color.chipRedText,
                        title: "Service Overdue - \(vehicle.registration ?? "")",
                        subtitle: "\(abs(fleetViewModel.daysUntilService(vehicle))) days past due"
                    )
                }

                ForEach(expiring.prefix(2), id: \.id) { vehicle in
                    alertRow(
                        icon: "doc.fill",
                        iconBg: Color.chipOrangeBg,
                        iconColour: Color.chipOrangeText,
                        title: "Licence Expiring - \(vehicle.registration ?? "")",
                        subtitle: licenceDaysText(vehicle)
                    )
                }
            }
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
                .font(.system(size: 16))
                .foregroundColor(iconColour)
                .frame(width: 34, height: 34)
                .background(iconBg)
                .cornerRadius(9)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
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
                .font(.system(size: 12, weight: .semibold))
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
                    icon: "person.fill.badge.plus",
                    iconBg: Color(hex: "E4F5EA"),
                    title: "Add Driver",
                    subtitle: "Onboard and assign"
                ) {
                    showAddDriver = true
                }

                quickActionCell(
                    icon: "wrench.and.screwdriver.fill",
                    iconBg: Color(hex: "FFF3E0"),
                    title: "Log Service",
                    subtitle: "Add or scan invoice"
                ) {
                    showRecords = true
                }

                quickActionCell(
                    icon: "exclamationmark.triangle.fill",
                    iconBg: Color(hex: "FFEAEA"),
                    title: "View Faults",
                    subtitle: "0 open"
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
                    .font(.system(size: 18))
                    .foregroundColor(.navyPrimary)
                    .frame(width: 36, height: 36)
                    .background(iconBg)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(12)
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
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Text("All Records")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            .padding(.top, 14)

            Text("No activity logged today")
                .font(.system(size: 13))
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
}

#Preview {
    ManagerHomeView()
        .environmentObject(AuthViewModel())
        .environmentObject(FleetViewModel())
}
