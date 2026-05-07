//
//  FaultListView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import CoreData

// MARK: - Manager Fault List View
struct FaultListView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var fleetViewModel: FleetViewModel
    @StateObject private var faultViewModel = FaultViewModel()

    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var errorText: String = ""
    @State private var driverNameById: [String: String] = [:]

    private let firestoreService = FirestoreService.shared
    private let filters = ["All", "Open", "In Progress", "Resolved"]

    private var normalizedFleetId: String {
        authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredFaults: [FaultReportEntity] {
        let searched = searchText.isEmpty
            ? faultViewModel.faultReports
            : faultViewModel.faultReports.filter {
                ($0.descriptionText ?? "").localizedCaseInsensitiveContains(searchText) ||
                (shortVehicleLabel(for: $0)).localizedCaseInsensitiveContains(searchText)
            }

        if selectedFilter == "All" {
            return searched
        }

        return searched.filter {
            let cat = statusCategory(for: $0.status ?? "open")
            switch selectedFilter {
            case "Open": return cat == .open
            case "In Progress": return cat == .inProgress
            case "Resolved": return cat == .resolved
            default: return true
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
            ScrollView {
                VStack(spacing: 0) {
                    // Search Bar (Matching Fleet Layout)
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.subheadline)

                        TextField("Search faults…", text: $searchText)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Filter Pills (Matching Fleet Layout)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { filter in
                                FilterPill(
                                    title: filter,
                                    count: countForFilter(filter),
                                    isSelected: selectedFilter == filter
                                ) {
                                    selectedFilter = filter
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundStyle(Color.statusOverdue)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }

                    if normalizedFleetId.isEmpty {
                        ContentUnavailableView(
                            "Fleet Not Ready",
                            systemImage: "building.2.crop.circle",
                            description: Text("Manager account is missing fleet configuration.")
                        )
                        .padding(.top, 40)
                    } else if filteredFaults.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No Fault Reports" : "No Results",
                            systemImage: searchText.isEmpty ? "exclamationmark.triangle" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "Driver reported faults will appear here." : "Try a different search or filter")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(orderedGroups, id: \.self) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.headerTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                
                                LazyVStack(spacing: 10) {
                                    ForEach(groupedFaults[group] ?? [], id: \.id) { fault in
                                        NavigationLink {
                                            FaultDetailView(
                                                fault: fault,
                                                fleetId: normalizedFleetId,
                                                faultViewModel: faultViewModel
                                            )
                                        } label: {
                                            faultCard(for: fault)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .background(Color.systemGroupedBg)
            .navigationTitle("Fault Reports")
            .navigationBarTitleDisplayMode(.large)
            .task(id: normalizedFleetId) {
                guard !normalizedFleetId.isEmpty else {
                    return
                }

                errorText = ""
                faultViewModel.startFaultListener(fleetId: normalizedFleetId)
                await loadDriverNameMap()
            }
            .refreshable {
                guard !normalizedFleetId.isEmpty else {
                    return
                }

                errorText = ""
                faultViewModel.startFaultListener(fleetId: normalizedFleetId)
                await loadDriverNameMap()
            }
        }
    }

    private func faultCard(for fault: FaultReportEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // Registration as Title (Matching Fleet Card Layout)
                    Text(shortVehicleLabel(for: fault))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(.primary)

                    Text(fault.descriptionText ?? "Fault report")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

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

                Text(driverLabel(for: fault))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("\u{2022}")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formattedDate(fault.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                // Details Button (Matching Fleet Card Style)
                HStack(spacing: 4) {
                    Text("Details")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.navyPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.navyPrimary.opacity(0.1))
                .clipShape(Capsule())
            }
            
            // Bottom Accent Line (Matching Fleet Card Design)
            Capsule()
                .fill(urgencyColor(for: fault.urgency ?? "medium"))
                .frame(height: 3)
                .padding(.top, 4)
        }
        .padding(12)
        .background(Color.white) // Fault cards must be all white
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    private func countForFilter(_ filter: String) -> Int {
        switch filter {
        case "Open":
            return faultViewModel.faultReports.filter { statusCategory(for: $0.status ?? "open") == .open }.count
        case "In Progress":
            return faultViewModel.faultReports.filter { statusCategory(for: $0.status ?? "open") == .inProgress }.count
        case "Resolved":
            return faultViewModel.faultReports.filter { statusCategory(for: $0.status ?? "open") == .resolved }.count
        default:
            return faultViewModel.faultReports.count
        }
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
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
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

    private func shortVehicleLabel(for fault: FaultReportEntity) -> String {
        guard let vehicleId = fault.vehicleId else {
            return "Vehicle"
        }

        if let vehicle = fleetViewModel.vehicles.first(where: { $0.id == vehicleId }),
           let registration = vehicle.registration,
           !registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return registration
        }

        return "Vehicle"
    }

    private func driverLabel(for fault: FaultReportEntity) -> String {
        let driverId = (fault.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !driverId.isEmpty else {
            return "Driver"
        }

        if let name = driverNameById[driverId], !name.isEmpty {
            return name
        }

        return "Driver"
    }

    private func loadDriverNameMap() async {
        do {
            let drivers = try await firestoreService.fetchFleetDriverUsers(fleetId: normalizedFleetId)
            var map: [String: String] = [:]

            for driver in drivers {
                let trimmedName = driver.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty {
                    map[driver.userId] = trimmedName
                }
            }

            driverNameById = map
        } catch {
            driverNameById = [:]
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "Unknown time"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Filter Status Category
private enum FaultStatusCategory {
    case open
    case inProgress
    case resolved
}

// MARK: - Date Grouping
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
        .environmentObject(FleetViewModel())
}
