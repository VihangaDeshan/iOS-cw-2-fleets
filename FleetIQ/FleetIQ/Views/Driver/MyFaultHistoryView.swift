//
//  MyFaultHistoryView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - My Fault History View
struct MyFaultHistoryView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var faultViewModel = FaultViewModel()

    @State private var selectedFilter: FaultHistoryFilter = .all
    @State private var selectedFault: FaultSnapshot?

    private var normalizedFleetId: String {
        authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDriverId: String {
        authViewModel.currentUID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredFaults: [FaultReportEntity] {
        switch selectedFilter {
        case .all:
            return faultViewModel.myFaults
        case .open:
            return faultViewModel.myFaults.filter {
                normalizedStatusCategory(for: $0.status ?? "open") == .open
            }
        case .inProgress:
            return faultViewModel.myFaults.filter {
                normalizedStatusCategory(for: $0.status ?? "open") == .inProgress
            }
        case .resolved:
            return faultViewModel.myFaults.filter {
                normalizedStatusCategory(for: $0.status ?? "open") == .resolved
            }
        }
    }

    var body: some View {
        List {
            if normalizedFleetId.isEmpty || normalizedDriverId.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Missing Driver Session",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Please sign in again to load your fault history.")
                    )
                    .frame(maxWidth: .infinity)
                }
            } else if filteredFaults.isEmpty {
                Section {
                    ContentUnavailableView(
                        selectedFilter.emptyTitle,
                        systemImage: "clock.badge.exclamationmark",
                        description: Text(selectedFilter.emptySubtitle)
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    ForEach(filteredFaults, id: \.id) { fault in
                        Button {
                            selectedFault = FaultSnapshot(from: fault)
                        } label: {
                            faultRow(fault)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(filteredFaults.count) report(s)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Faults")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ReportFaultView()
                } label: {
                    Text("Create")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.statusOverdue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .safeAreaInset(edge: .top) {
            filterPicker
        }
        .task(id: "\(normalizedFleetId)|\(normalizedDriverId)") {
            guard !normalizedFleetId.isEmpty, !normalizedDriverId.isEmpty else {
                return
            }

            faultViewModel.startMyFaultListener(
                fleetId: normalizedFleetId,
                driverId: normalizedDriverId
            )
        }
        .refreshable {
            guard !normalizedFleetId.isEmpty, !normalizedDriverId.isEmpty else {
                return
            }

            faultViewModel.startMyFaultListener(
                fleetId: normalizedFleetId,
                driverId: normalizedDriverId
            )
        }
        .sheet(item: $selectedFault) { snapshot in
            FaultDetailSheet(snapshot: snapshot)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var filterPicker: some View {
        HStack {
            Picker("Status", selection: $selectedFilter) {
                ForEach(FaultHistoryFilter.allCases, id: \.self) { filter in
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

    private func faultRow(_ fault: FaultReportEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                urgencyIcon(for: fault.urgency ?? "medium")

                Text(fault.descriptionText ?? "Fault report")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 8)

                statusChip(for: fault.status ?? "open")
            }

            HStack(spacing: 8) {
                Text(formattedDate(fault.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Manager Response: \(managerResponseText(for: fault.status ?? "open"))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(managerResponseColor(for: fault.status ?? "open"))

            if let photoURL = fault.photoURL,
               photoURL.hasPrefix("http"),
               let url = URL(string: photoURL) {
                HStack(spacing: 10) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_):
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 54, height: 54)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text("Photo attached")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if (fault.photoURL ?? "").hasPrefix("storage_path:") {
                Text("Photo uploaded (URL syncing)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.chipOrangeText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.chipOrangeBg)
                    .clipShape(Capsule())
            } else if (fault.photoURL ?? "") == "upload_failed" {
                Text("Photo upload failed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.chipOrangeText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.chipOrangeBg)
                    .clipShape(Capsule())
            } else {
                Text("No photo attached")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
            }

            if fault.latitude != 0 || fault.longitude != 0 {
                Text(String(format: "GPS %.4f, %.4f", fault.latitude, fault.longitude))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func urgencyIcon(for urgency: String) -> some View {
        let normalized = urgency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let tuple: (String, Color)
        switch normalized {
        case "critical", "high":
            tuple = ("exclamationmark.triangle.fill", .statusOverdue)
        case "low":
            tuple = ("circle.fill", .statusActive)
        default:
            tuple = ("circle.fill", .statusDueSoon)
        }

        return Image(systemName: tuple.0)
            .font(.subheadline)
            .foregroundStyle(tuple.1)
            .frame(width: 18, height: 18)
    }

    private func statusChip(for status: String) -> some View {
        let category = normalizedStatusCategory(for: status)

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

    private func managerResponseText(for status: String) -> String {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "acknowledged":
            return "Acknowledged"
        case "workshop_booked", "workshop booked":
            return "Workshop Booked"
        case "in_progress", "in progress":
            return "In Progress"
        case "resolved":
            return "Resolved"
        default:
            return "Pending Manager Review"
        }
    }

    private func managerResponseColor(for status: String) -> Color {
        switch normalizedStatusCategory(for: status) {
        case .resolved:
            return .statusActive
        case .inProgress:
            return .statusDueSoon
        case .open:
            return .statusOverdue
        }
    }

    private func normalizedStatusCategory(for status: String) -> FaultStatusCategory {
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

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "Unknown time"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Filter
private enum FaultHistoryFilter: String, CaseIterable {
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
            return "Reports you submit will appear here."
        case .open:
            return "Great news. You have no pending issues right now."
        case .inProgress:
            return "Manager actions and workshop bookings will show here."
        case .resolved:
            return "Resolved reports will appear here once managers close them."
        }
    }
}

private enum FaultStatusCategory {
    case open
    case inProgress
    case resolved
}

private struct FaultSnapshot: Identifiable, Hashable {
    let id: UUID
    let descriptionText: String
    let urgency: String
    let status: String
    let createdAt: Date?
    let photoURL: String?
    let latitude: Double
    let longitude: Double

    init(from fault: FaultReportEntity) {
        self.id = fault.id ?? UUID()
        self.descriptionText = fault.descriptionText ?? "Fault report"
        self.urgency = fault.urgency ?? "medium"
        self.status = fault.status ?? "open"
        self.createdAt = fault.createdAt
        self.photoURL = fault.photoURL
        self.latitude = fault.latitude
        self.longitude = fault.longitude
    }
}

private struct FaultDetailSheet: View {
    let snapshot: FaultSnapshot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: urgencyIcon)
                            .foregroundStyle(urgencyColor)

                        Text(urgencyLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(urgencyColor)

                        Spacer()

                        Text(statusLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(statusColor.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Text(snapshot.descriptionText)
                        .font(.body)

                    if let createdAt = snapshot.createdAt {
                        Text("Reported on \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let photoURL = snapshot.photoURL,
                       photoURL.hasPrefix("http"),
                       let url = URL(string: photoURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 180)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            case .failure(_):
                                Text("Could not load photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }

                    if snapshot.latitude != 0 || snapshot.longitude != 0 {
                        Text(String(format: "GPS: %.4f, %.4f", snapshot.latitude, snapshot.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Fault Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusLabel: String {
        let normalized = snapshot.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "acknowledged":
            return "Acknowledged"
        case "workshop_booked", "workshop booked":
            return "Workshop Booked"
        case "in_progress", "in progress":
            return "In Progress"
        case "resolved":
            return "Resolved"
        default:
            return "Open"
        }
    }

    private var statusColor: Color {
        let normalized = snapshot.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "resolved":
            return .statusActive
        case "acknowledged", "workshop_booked", "workshop booked", "in_progress", "in progress":
            return .statusDueSoon
        default:
            return .statusOverdue
        }
    }

    private var urgencyLabel: String {
        let normalized = snapshot.urgency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "critical", "high":
            return "Critical"
        case "low":
            return "Low"
        default:
            return "Medium"
        }
    }

    private var urgencyColor: Color {
        let normalized = snapshot.urgency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "critical", "high":
            return .statusOverdue
        case "low":
            return .statusActive
        default:
            return .statusDueSoon
        }
    }

    private var urgencyIcon: String {
        let normalized = snapshot.urgency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "critical", "high":
            return "exclamationmark.triangle.fill"
        default:
            return "circle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        MyFaultHistoryView()
            .environmentObject(AuthViewModel())
    }
}