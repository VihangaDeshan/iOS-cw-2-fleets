//
//  ServiceHistoryView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Service History View
struct ServiceHistoryView: View {

    // MARK: - Inputs
    let vehicle: VehicleEntity

    // MARK: - Environment
    @EnvironmentObject var authViewModel: AuthViewModel

    // MARK: - State
    @StateObject private var viewModel = ServiceLogViewModel()
    @State private var selectedFilter = "All"
    @State private var showAddRecord = false

    // MARK: - Constants
    let filters = ["All", "Oil Change", "Brake Service", "Full Service", "Tyre", "Battery"]

    // MARK: - Filtered Records
    var filteredRecords: [(year: Int, records: [ServiceRecordEntity])] {
        if selectedFilter == "All" {
            return viewModel.recordsByYear()
        }

        let filtered = viewModel.records.filter {
            ($0.serviceType ?? "").localizedCaseInsensitiveContains(selectedFilter)
        }

        let grouped = Dictionary(grouping: filtered) { record in
            Calendar.current.component(.year, from: record.date ?? Date())
        }

        return grouped.keys.sorted(by: >).map { year in
            (
                year: year,
                records: grouped[year]!.sorted {
                    ($0.date ?? Date()) > ($1.date ?? Date())
                }
            )
        }
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.records.isEmpty {
                schedulerBanner
            }

            filterStrip

            if viewModel.isLoading {
                ProgressView()
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
            } else if viewModel.records.isEmpty {
                ContentUnavailableView(
                    "No Service Records",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Tap + to add the first service record")
                )
                .padding(.top, 20)
            } else {
                List {
                    ForEach(filteredRecords, id: \.year) { group in
                        Section(String(group.year)) {
                            ForEach(group.records, id: \.id) { record in
                                serviceRecordRow(record)
                            }
                            .onDelete { indices in
                                Task {
                                    for index in indices {
                                        await viewModel.deleteRecord(
                                            group.records[index],
                                            fleetId: authViewModel.fleetId
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            if !viewModel.records.isEmpty {
                totalFooter
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Service History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddRecord = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add service record")
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddServiceRecordView(vehicle: vehicle)
                .environmentObject(authViewModel)
        }
        .onAppear {
            if let id = vehicle.id {
                viewModel.loadRecords(for: id)
                Task {
                    await viewModel.syncRecords(
                        vehicleId: id,
                        fleetId: authViewModel.fleetId)
                }
            }
        }
    }

    // MARK: - Banner

    /// Displays smart next-service prediction based on historical interval.
    private var schedulerBanner: some View {
        let isOverdue = viewModel.isFullServiceOverdue
        let nextKm = viewModel.nextFullServiceMileage
        let nextDate = viewModel.nextFullServiceDate

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundColor(isOverdue ? .statusOverdue : .statusActive)

                Text(isOverdue ? "Full Service Overdue (> 3 months)" : "Full Service Up To Date")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(isOverdue ? .statusOverdue : .statusActive)
                
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Predicted Next Full Service:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(String(format: "%.0f km", nextKm)) (approx. \(mediumDate(nextDate)))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color(hex: "1A3C6E"))
            }
            .padding(.leading, 30)
        }
        .padding(14)
        .background(isOverdue ? Color.statusOverdue.opacity(0.1) : Color(hex: "E8F0FB"))
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .accessibilityLabel(isOverdue ? "Warning: Full service overdue. Next predicted at \(String(format: "%.0f", nextKm)) kilometers." : "Next service predicted at \(String(format: "%.0f", nextKm)) kilometers.")
    }

    // MARK: - Filter Strip

    /// Displays horizontal service-type filter chips.
    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { item in
                    Button {
                        selectedFilter = item
                    } label: {
                        Text(item)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(selectedFilter == item ? Color.navyPrimary : Color(.systemGray5))
                            .foregroundColor(selectedFilter == item ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel("\(item) filter")
                    .accessibilityAddTraits(selectedFilter == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Total Footer

    /// Displays total service spending below the history list.
    private var totalFooter: some View {
        HStack {
            Text("Total spent:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("LKR \(String(format: "%.0f", viewModel.totalCostLKR))")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.navyPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
    }

    // MARK: - Row Helpers

    /// Builds one service record row.
    /// - Parameter record: Record object to display.
    /// - Returns: Styled row view.
    private func serviceRecordRow(_ record: ServiceRecordEntity) -> some View {
        let dateText = mediumDate(record.date ?? Date())

        return HStack(spacing: 10) {
            Image(systemName: iconForType(record.serviceType ?? ""))
                .font(.system(size: 16))
                .foregroundColor(.navyPrimary)
                .frame(width: 36, height: 36)
                .background(Color(hex: "E8F0FB"))
                .cornerRadius(9)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.serviceType ?? "Service")
                    .font(.system(size: 13, weight: .semibold))

                Text(
                    "\(dateText)  ·  " +
                    String(format: "%.0f km", record.mileageAtService) +
                    "  ·  " +
                    (record.garageName ?? "")
                )
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

                Text("Completed")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.chipGreenText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.chipGreenBg)
                    .clipShape(Capsule())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("LKR \(String(format: "%.0f", record.costLKR))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.navyPrimary)
                
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteRecord(record, fleetId: authViewModel.fleetId)
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(record.serviceType ?? "Service"), \(dateText), LKR \(String(format: "%.0f", record.costLKR))"
        )
    }

    /// Maps service type names to icon symbols.
    /// - Parameter type: Service type string.
    /// - Returns: SF Symbol name.
    private func iconForType(_ type: String) -> String {
        let lower = type.lowercased()

        if lower.contains("oil") {
            return "drop.fill"
        }

        if lower.contains("brake") {
            return "circle.circle.fill"
        }

        if lower.contains("tyre") || lower.contains("tire") {
            return "circle.fill"
        }

        if lower.contains("battery") {
            return "battery.100"
        }

        return "wrench.and.screwdriver.fill"
    }

    /// Formats date labels using medium style.
    /// - Parameter date: Input date value.
    /// - Returns: Formatted date string.
    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
