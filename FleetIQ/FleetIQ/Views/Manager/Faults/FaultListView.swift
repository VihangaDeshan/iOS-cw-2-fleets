//
//  FaultListView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI

// MARK: - Manager Fault List View
struct FaultListView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var faultViewModel = FaultViewModel()

    @State private var selectedFilter: FaultListFilter = .all
    @State private var errorText: String = ""

    private var normalizedFleetId: String {
        authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredFaults: [FaultReportEntity] {
        switch selectedFilter {
        case .all:
            return faultViewModel.faultReports
        case .open:
            return faultViewModel.faultReports.filter {
                statusCategory(for: $0.status ?? "open") == .open
            }
        case .inProgress:
            return faultViewModel.faultReports.filter {
                statusCategory(for: $0.status ?? "open") == .inProgress
            }
        case .resolved:
            return faultViewModel.faultReports.filter {
                statusCategory(for: $0.status ?? "open") == .resolved
            }
        }
    }

    private var groupedFaults: [FaultDateGroup: [FaultReportEntity]] {
        Dictionary(grouping: filteredFaults) { fault in
            let createdAt = fault.createdAt ?? .distantPast
            return FaultDateGroup(date: createdAt)
        }
    }

    private var orderedGroups: [FaultDateGroup] {
        groupedFaults.keys.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerCard
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
                .listRowBackground(Color.clear)

                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundStyle(Color.statusOverdue)
                    }
                }

                if normalizedFleetId.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Fleet Not Ready",
                            systemImage: "building.2.crop.circle",
                            description: Text("Manager account is missing fleet configuration.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                } else if filteredFaults.isEmpty {
                    Section {
                        ContentUnavailableView(
                            selectedFilter.emptyTitle,
                            systemImage: "exclamationmark.triangle",
                            description: Text(selectedFilter.emptySubtitle)
                        )
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(orderedGroups, id: \.self) { group in
                        Section(group.headerTitle) {
                            ForEach(groupedFaults[group] ?? [], id: \.id) { fault in
                                NavigationLink {
                                    FaultDetailView(
                                        fault: fault,
                                        fleetId: normalizedFleetId,
                                        faultViewModel: faultViewModel
                                    )
                                } label: {
                                    faultRow(for: fault)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(isCritical(fault) ? Color.chipRedBg.opacity(0.58) : Color.clear)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Fault Reports")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .top) {
                filterPicker
            }
            .task(id: normalizedFleetId) {
                guard !normalizedFleetId.isEmpty else {
                    return
                }

                errorText = ""
                faultViewModel.startFaultListener(fleetId: normalizedFleetId)
            }
            .refreshable {
                guard !normalizedFleetId.isEmpty else {
                    return
                }

                errorText = ""
                faultViewModel.startFaultListener(fleetId: normalizedFleetId)
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fault Reports")
                    .font(.headline.weight(.semibold))
                Text("Live driver-reported incidents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Open \(faultViewModel.openFaultCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.chipRedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.chipRedBg)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var filterPicker: some View {
        HStack {
            Picker("Status", selection: $selectedFilter) {
                ForEach(FaultListFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground))
    }

    private func faultRow(for fault: FaultReportEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fault.descriptionText ?? "Fault report")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text("\(formattedUrgency(fault.urgency ?? "medium")) urgency")
                        .font(.caption)
                        .foregroundStyle(urgencyColor(for: fault.urgency ?? "medium"))
                }

                Spacer(minLength: 8)

                statusChip(for: fault.status ?? "open")
            }

            HStack(spacing: 8) {
                if hasPhotoReference(fault) {
                    photoIndicator
                }

                Text(formattedDate(fault.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(shortVehicleLabel(for: fault))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var photoIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.caption)
            Text("Photo")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }

    private func statusChip(for status: String) -> some View {
        let category = statusCategory(for: status)

        let label: String
        let textColor: Color
        let bgColor: Color

        switch category {
        case .resolved:
            label = "Resolved"
            textColor = .chipGreenText
            bgColor = .chipGreenBg
        case .inProgress:
            label = "In Progress"
            textColor = .chipOrangeText
            bgColor = .chipOrangeBg
        case .open:
            label = "Open"
            textColor = .chipRedText
            bgColor = .chipRedBg
        }

        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(bgColor)
            .clipShape(Capsule())
    }

    private func statusCategory(for status: String) -> FaultStatusCategory {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "resolved":
            return .resolved
        case "acknowledged", "workshop_booked", "workshop booked", "in_progress", "in progress":
            return .inProgress
        default:
            return .open
        }
    }

    private func urgencyColor(for urgency: String) -> Color {
        let normalized = urgency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "critical", "high":
            return .statusOverdue
        case "low":
            return .statusActive
        default:
            return .statusDueSoon
        }
    }

    private func formattedUrgency(_ urgency: String) -> String {
        let normalized = urgency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "critical", "high":
            return "Critical"
        case "low":
            return "Low"
        default:
            return "Medium"
        }
    }

    private func hasPhotoReference(_ fault: FaultReportEntity) -> Bool {
        guard let photoURL = fault.photoURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !photoURL.isEmpty else {
            return false
        }

        return photoURL.hasPrefix("http")
            || photoURL.hasPrefix("storage_path:")
            || photoURL == "upload_failed"
    }

    private func isCritical(_ fault: FaultReportEntity) -> Bool {
        let normalized = (fault.urgency ?? "medium")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "critical" || normalized == "high"
    }

    private func shortVehicleLabel(for fault: FaultReportEntity) -> String {
        let id = fault.vehicleId?.uuidString ?? ""
        guard !id.isEmpty else {
            return "Vehicle -"
        }

        return "Vehicle \(id.prefix(6))"
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "Unknown time"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Filter
private enum FaultListFilter: String, CaseIterable {
    case all
    case open
    case inProgress
    case resolved

    var title: String {
        switch self {
        case .all:
            return "All"
        case .open:
            return "Open"
        case .inProgress:
            return "In Progress"
        case .resolved:
            return "Resolved"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "No Fault Reports"
        case .open:
            return "No Open Faults"
        case .inProgress:
            return "No In-Progress Faults"
        case .resolved:
            return "No Resolved Faults"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .all:
            return "Driver reported faults will appear here."
        case .open:
            return "New issues waiting for action will appear here."
        case .inProgress:
            return "Acknowledged and workshop-booked issues appear here."
        case .resolved:
            return "Resolved issues appear here after closure."
        }
    }
}

private enum FaultStatusCategory {
    case open
    case inProgress
    case resolved
}

private enum FaultDateGroup: Hashable, Comparable {
    case today
    case yesterday
    case earlier(Date)

    init(date: Date) {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else {
            self = .earlier(date)
        }
    }

    var headerTitle: String {
        switch self {
        case .today:
            return "TODAY"
        case .yesterday:
            return "YESTERDAY"
        case .earlier:
            return "EARLIER"
        }
    }

    private var sortRank: Int {
        switch self {
        case .today:
            return 3
        case .yesterday:
            return 2
        case .earlier:
            return 1
        }
    }

    static func < (lhs: FaultDateGroup, rhs: FaultDateGroup) -> Bool {
        lhs.sortRank < rhs.sortRank
    }
}

#Preview {
    FaultListView()
        .environmentObject(AuthViewModel())
}
