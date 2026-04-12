//
//  MyFaultHistoryView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI

// MARK: - My Fault History View
struct MyFaultHistoryView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var faultViewModel = FaultViewModel()

    @State private var selectedFilter: FaultHistoryFilter = .all

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
            return faultViewModel.myFaults.filter { ($0.status ?? "open").lowercased() != "resolved" }
        case .resolved:
            return faultViewModel.myFaults.filter { ($0.status ?? "open").lowercased() == "resolved" }
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
                        faultRow(fault)
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
            HStack(alignment: .top, spacing: 8) {
                Text(fault.descriptionText ?? "Fault report")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 8)

                statusChip(for: fault.status ?? "open")
            }

            HStack(spacing: 8) {
                urgencyChip(for: fault.urgency ?? "medium")

                Text(formattedDate(fault.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    private func statusChip(for status: String) -> some View {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isResolved = normalized == "resolved"
        let textColor: Color = isResolved ? .chipGreenText : .chipRedText
        let bgColor: Color = isResolved ? .chipGreenBg : .chipRedBg

        return Text(isResolved ? "Resolved" : "Open")
            .font(.caption2.weight(.bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(bgColor)
            .clipShape(Capsule())
    }

    private func urgencyChip(for urgency: String) -> some View {
        let normalized = urgency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let tuple: (String, Color, Color)
        switch normalized {
        case "high":
            tuple = ("High", .chipRedText, .chipRedBg)
        case "low":
            tuple = ("Low", .chipGreenText, .chipGreenBg)
        default:
            tuple = ("Medium", .chipOrangeText, .chipOrangeBg)
        }

        return Text(tuple.0)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tuple.1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tuple.2)
            .clipShape(Capsule())
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
    case resolved

    var title: String {
        switch self {
        case .all:
            return "All"
        case .open:
            return "Open"
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
        case .resolved:
            return "Resolved reports will appear here once managers close them."
        }
    }
}

#Preview {
    NavigationStack {
        MyFaultHistoryView()
            .environmentObject(AuthViewModel())
    }
}