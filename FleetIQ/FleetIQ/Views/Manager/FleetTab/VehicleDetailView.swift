//
//  VehicleDetailView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Vehicle Detail View
struct VehicleDetailView: View {

    // MARK: - Properties
    @StateObject private var viewModel: VehicleDetailViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var fleetViewModel: FleetViewModel

    @State private var showEdit = false
    @State private var showAddService = false
    @State private var showFuelLog = false
    @State private var showCostReport = false
    @State private var showDocumentVault = false
    @State private var showAssignDriver = false
    @State private var drivers: [FleetDriverUser] = []
    @State private var isLoadingDrivers = false
    @State private var isSavingDriverAssignment = false
    @State private var selectedDriverUserId = ""
    @State private var selectedDriverName = ""
    @State private var previousDriverUserId = ""
    @State private var driverAssignmentError = ""

    private let firestoreService = FirestoreService.shared

    // MARK: - Initializer

    /// Creates a vehicle detail screen for a selected vehicle.
    /// - Parameter vehicle: Vehicle entity passed from fleet list.
    init(vehicle: VehicleEntity) {
        _viewModel = StateObject(wrappedValue: VehicleDetailViewModel(vehicle: vehicle))
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroCard
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                sectionHeader("ASSIGNED DRIVER")
                driverRow
                    .padding(.horizontal, 12)

                sectionHeader("DOCUMENTS")
                documentsCard
                    .padding(.horizontal, 12)

                sectionHeader("ACTIONS")
                actionsCard
                    .padding(.horizontal, 12)

                Spacer(minLength: 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Vehicle Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showEdit = true
                }
                .accessibilityLabel("Edit vehicle details")
            }
        }
        .sheet(isPresented: $showEdit) {
            EditVehicleView(viewModel: viewModel)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showAddService) {
            AddServiceRecordView(vehicle: viewModel.vehicle)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showFuelLog) {
            NavigationStack {
                FuelLogView(vehicle: viewModel.vehicle)
            }
        }
        .sheet(isPresented: $showCostReport) {
            NavigationStack {
                CostReportView(vehicle: viewModel.vehicle)
            }
        }
        .sheet(isPresented: $showDocumentVault) {
            DocumentVaultView(vehicle: viewModel.vehicle)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showAssignDriver) {
            assignDriverSheet
        }
    }

    // MARK: - Hero Card

    /// Displays vehicle summary metrics and status.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.vehicle.registration ?? "Unknown")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(.white)

                    Text(vehicleSubtitle())
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                VehicleStatusChip(status: fleetViewModel.vehicleStatus(viewModel.vehicle))
            }

            HStack(spacing: 0) {
                statItem(
                    label: "MILEAGE",
                    value: String(format: "%.0f km", viewModel.vehicle.currentMileage)
                )

                Divider()
                    .background(.white.opacity(0.3))
                    .frame(height: 28)
                    .padding(.horizontal, 14)

                statItem(
                    label: "NEXT SERVICE",
                    value: String(format: "%.0f km", fleetViewModel.predictedNextServiceMileage(viewModel.vehicle))
                )

                Divider()
                    .background(.white.opacity(0.3))
                    .frame(height: 28)
                    .padding(.horizontal, 14)

                statItem(label: "DAYS LEFT", value: daysLeftText())
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [.navyPrimary, .navySecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Vehicle \(viewModel.vehicle.registration ?? ""), \(fleetViewModel.vehicleStatus(viewModel.vehicle))"
        )
    }

    /// Builds one metric block inside the hero card.
    /// - Parameters:
    ///   - label: Metric title.
    ///   - value: Metric value.
    /// - Returns: Metric item view.
    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
                .tracking(0.3)

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        }
    }

    /// Builds readable make/model/year/fuel subtitle text.
    /// - Returns: Joined subtitle string with separators.
    private func vehicleSubtitle() -> String {
        [
            viewModel.vehicle.make,
            viewModel.vehicle.model,
            viewModel.vehicle.year > 0 ? String(viewModel.vehicle.year) : nil,
            viewModel.vehicle.fuelType
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// Returns days-left label for next service metric.
    /// - Returns: Day text or overdue text.
    private func daysLeftText() -> String {
        let days = fleetViewModel.daysUntilService(viewModel.vehicle)
        if days < 0 {
            return "\(abs(days))d over"
        }

        return "\(days) days"
    }

    // MARK: - Driver Row

    /// Displays assigned driver summary row.
    private var driverRow: some View {
        Button {
            showAssignDriver = true
            Task {
                await loadDriversForAssignment()
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.navyPrimary)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(initials(viewModel.vehicle.assignedDriverId ?? "?"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.vehicle.assignedDriverId ?? "No driver assigned")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Text("Assigned Driver")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.systemGray3))
            }
            .padding(13)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Assigned driver: \(viewModel.vehicle.assignedDriverId ?? "none")")
        .accessibilityHint("Double tap to change driver")
    }

    /// Displays driver picker sheet for assigning current vehicle.
    private var assignDriverSheet: some View {
        NavigationStack {
            List {
                Section {
                    if isLoadingDrivers {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading drivers...")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        selectedDriverUserId = ""
                        selectedDriverName = ""
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No driver")
                                    .font(.subheadline.weight(.semibold))
                                Text("Clear assignment")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if selectedDriverUserId.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.statusActive)
                            }
                        }
                    }
                    .disabled(isLoadingDrivers || isSavingDriverAssignment)

                    ForEach(drivers, id: \.userId) { driver in
                        Button {
                            selectedDriverUserId = driver.userId
                            selectedDriverName = driver.name
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(driver.name.isEmpty ? "Unnamed Driver" : driver.name)
                                        .font(.subheadline.weight(.semibold))

                                    Text(driver.email.isEmpty ? "No email" : driver.email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedDriverUserId == driver.userId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.statusActive)
                                }
                            }
                        }
                        .disabled(isLoadingDrivers || isSavingDriverAssignment)
                    }
                }

                if !driverAssignmentError.isEmpty {
                    Section {
                        Text(driverAssignmentError)
                            .font(.subheadline)
                            .foregroundColor(.statusOverdue)
                    }
                }
            }
            .navigationTitle("Assign Driver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAssignDriver = false
                    }
                    .disabled(isSavingDriverAssignment)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveDriverAssignment()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(isLoadingDrivers || isSavingDriverAssignment)
                }
            }
        }
    }

    // MARK: - Documents Card

    /// Displays document expiry rows for licence and insurance.
    private var documentsCard: some View {
        VStack(spacing: 0) {
            documentRow(
                icon: "doc.text.fill",
                name: "Revenue Licence",
                date: viewModel.vehicle.licenceExpiry
            )

            Divider()
                .padding(.leading, 48)

            documentRow(
                icon: "lock.shield.fill",
                name: "Insurance Certificate",
                date: viewModel.vehicle.insuranceExpiry
            )
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    /// Builds one document row with expiry chip.
    /// - Parameters:
    ///   - icon: SF Symbol for document type.
    ///   - name: Document title.
    ///   - date: Expiry date.
    /// - Returns: Document row view.
    private func documentRow(icon: String, name: String, date: Date?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.navyPrimary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))

                if let date {
                    Text("Expires \(mediumDate(date))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Not set")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(viewModel.expiryChipText(for: date))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(viewModel.expiryColour(for: date))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(viewModel.expiryColour(for: date).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(13)
        .accessibilityLabel("\(name), \(viewModel.expiryChipText(for: date))")
    }

    // MARK: - Actions Card

    /// Displays vehicle action rows including add service and service history.
    private var actionsCard: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "wrench.and.screwdriver.fill",
                title: "Add Service Record"
            ) {
                showAddService = true
            }

            Divider()
                .padding(.leading, 48)

            actionRow(
                icon: "fuelpump.fill",
                title: "Log Fuel Fill-Up"
            ) {
                showFuelLog = true
            }

            Divider()
                .padding(.leading, 48)

            NavigationLink {
                ServiceHistoryView(vehicle: viewModel.vehicle)
                    .environmentObject(authViewModel)
            } label: {
                actionRowLabel(icon: "clock.fill", title: "View Service History")
            }

            Divider()
                .padding(.leading, 48)

            actionRow(
                icon: "dollarsign.circle.fill",
                title: "View Cost Report"
            ) {
                showCostReport = true
            }

            Divider()
                .padding(.leading, 48)

            actionRow(
                icon: "folder.fill",
                title: "Document Vault"
            ) {
                showDocumentVault = true
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        .padding(.bottom, 8)
    }

    /// Builds a tappable action row button.
    /// - Parameters:
    ///   - icon: Row icon symbol.
    ///   - title: Row title.
    ///   - action: Action callback.
    /// - Returns: Action button row.
    private func actionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionRowLabel(icon: icon, title: title)
                .padding(13)
        }
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to open")
    }

    /// Builds the label layout used by action rows.
    /// - Parameters:
    ///   - icon: Row icon symbol.
    ///   - title: Row title.
    /// - Returns: Action row content label.
    private func actionRowLabel(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.navyPrimary)
                .frame(width: 28)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Color(.systemGray3))
        }
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    /// Builds a section title for grouped cards.
    /// - Parameter text: Header text.
    /// - Returns: Section header view.
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    /// Creates initials from a person name.
    /// - Parameter name: Source full name.
    /// - Returns: Two-character uppercase initials.
    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }

        return String(name.prefix(2)).uppercased()
    }

    /// Formats a date with medium style for subtitle labels.
    /// - Parameter date: Date to format.
    /// - Returns: Medium style date string.
    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// Loads drivers for assignment and preselects the currently assigned driver when possible.
    private func loadDriversForAssignment() async {
        isLoadingDrivers = true
        driverAssignmentError = ""

        do {
            drivers = try await firestoreService.fetchFleetDriverUsers(fleetId: authViewModel.fleetId)
            let currentAssignedName = (viewModel.vehicle.assignedDriverId ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let currentVehicleId = viewModel.vehicle.id?.uuidString ?? ""

            if let assignedByVehicle = drivers.first(where: { $0.assignedVehicleId == currentVehicleId }) {
                selectedDriverUserId = assignedByVehicle.userId
                selectedDriverName = assignedByVehicle.name
                previousDriverUserId = assignedByVehicle.userId
                isLoadingDrivers = false
                return
            }

            if let match = drivers.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(currentAssignedName) == .orderedSame
            }) {
                selectedDriverUserId = match.userId
                selectedDriverName = match.name
                previousDriverUserId = match.userId
            } else {
                selectedDriverUserId = ""
                selectedDriverName = ""
                previousDriverUserId = ""
            }
        } catch {
            drivers = []
            selectedDriverUserId = ""
            selectedDriverName = ""
            previousDriverUserId = ""
            driverAssignmentError = "Could not fetch drivers for this fleet."
        }

        isLoadingDrivers = false
    }

    /// Saves selected driver assignment for the current vehicle.
    private func saveDriverAssignment() async {
        isSavingDriverAssignment = true
        driverAssignmentError = ""

        let didAssign = await viewModel.assignDriver(
            assignedDriverName: selectedDriverName.isEmpty ? nil : selectedDriverName,
            assignedDriverUserId: selectedDriverUserId.isEmpty ? nil : selectedDriverUserId,
            previousDriverUserId: previousDriverUserId.isEmpty ? nil : previousDriverUserId,
            fleetId: authViewModel.fleetId
        )

        isSavingDriverAssignment = false

        if didAssign {
            showAssignDriver = false
            return
        }

        driverAssignmentError = "Could not save assigned driver. Please try again."
    }
}
