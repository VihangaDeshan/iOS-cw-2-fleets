//
//  FaultsTabView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI

// MARK: - Faults Tab View
struct FaultsTabView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var faultViewModel = FaultViewModel()

    @State private var errorText = ""

    private var normalizedFleetId: String {
        authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundColor(.statusOverdue)
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
                } else if faultViewModel.faultReports.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Fault Reports",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Driver reported faults will appear here.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Section {
                        ForEach(faultViewModel.faultReports, id: \.id) { fault in
                            NavigationLink {
                                ManagerFaultDetailView(
                                    fault: fault,
                                    fleetId: normalizedFleetId,
                                    faultViewModel: faultViewModel
                                )
                            } label: {
                                faultRow(for: fault)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if isResolved(fault.status ?? "") {
                                    Button("Reopen") {
                                        Task {
                                            await updateStatus(for: fault, status: "open")
                                        }
                                    }
                                    .tint(.statusDueSoon)
                                } else {
                                    Button("Resolve") {
                                        Task {
                                            await updateStatus(for: fault, status: "resolved")
                                        }
                                    }
                                    .tint(.statusActive)
                                }
                            }
                        }
                    } header: {
                        Text("\(faultViewModel.faultReports.count) report(s)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Faults")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Open: \(faultViewModel.openFaultCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.statusOverdue)
                        .clipShape(Capsule())
                }
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

    private func faultRow(for fault: FaultReportEntity) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Text(fault.descriptionText ?? "Fault")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 8)

                statusChip(status: fault.status ?? "open")
            }

            Text(
                "Urgency: \((fault.urgency ?? "medium").capitalized)  ·  \(mediumDate(fault.createdAt))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let photoURL = fault.photoURL,
               photoURL.hasPrefix("http") {
                Text("Photo attached")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.statusActive)
            } else if (fault.photoURL ?? "").hasPrefix("storage_path:") {
                Text("Photo uploaded (URL syncing)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.chipOrangeText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.chipOrangeBg)
                    .clipShape(Capsule())
            } else if (fault.photoURL ?? "") == "upload_failed" {
                Text("Photo upload failed")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.chipOrangeText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.chipOrangeBg)
                    .clipShape(Capsule())
            } else {
                Text("No photo attached")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func statusChip(status: String) -> some View {
        let resolved = isResolved(status)
        let color: Color = resolved ? .statusActive : .statusOverdue

        return Text(resolved ? "Resolved" : "Open")
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func isResolved(_ status: String) -> Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "resolved"
    }

    private func updateStatus(for fault: FaultReportEntity, status: String) async {
        guard !normalizedFleetId.isEmpty else {
            errorText = "Fleet ID is missing."
            return
        }

        do {
            try await faultViewModel.updateStatus(
                fault: fault,
                status: status,
                fleetId: normalizedFleetId
            )
            errorText = ""
        } catch {
            errorText = "Could not update fault status in cloud."
        }
    }

    private func mediumDate(_ date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Manager Fault Detail
private struct ManagerFaultDetailView: View {
    let fault: FaultReportEntity
    let fleetId: String

    @ObservedObject var faultViewModel: FaultViewModel

    @State private var isUpdating = false
    @State private var errorText = ""

    var body: some View {
        List {
            Section("Summary") {
                detailRow("Status", value: (fault.status ?? "open").capitalized)
                detailRow("Urgency", value: (fault.urgency ?? "medium").capitalized)
                detailRow("Reported", value: formattedDate(fault.createdAt))
                detailRow("Driver ID", value: fault.driverId ?? "-")
                detailRow("Vehicle ID", value: fault.vehicleId?.uuidString ?? "-")
            }

            Section("Description") {
                Text(fault.descriptionText ?? "No description")
                    .font(.body)
            }

                if let photoURL = fault.photoURL,
                    photoURL.hasPrefix("http"),
                    let url = URL(string: photoURL) {
                Section("Photo") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        case .failure(_):
                            Text("Could not load photo preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .empty:
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            } else if (fault.photoURL ?? "").hasPrefix("storage_path:") {
                Section("Photo") {
                    Text("Photo uploaded. Preview URL is still syncing.")
                        .font(.subheadline)
                        .foregroundStyle(Color.chipOrangeText)
                }
            } else if (fault.photoURL ?? "") == "upload_failed" {
                Section("Photo") {
                    Text("Photo upload failed for this report.")
                        .font(.subheadline)
                        .foregroundStyle(Color.chipOrangeText)
                }
            } else {
                Section("Photo") {
                    Text("No photo attached.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Location") {
                Text(String(format: "%.6f, %.6f", fault.latitude, fault.longitude))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !errorText.isEmpty {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundColor(.statusOverdue)
                }
            }

            Section {
                Button {
                    Task {
                        await toggleStatus()
                    }
                } label: {
                    HStack {
                        if isUpdating {
                            ProgressView()
                        }

                        Text((fault.status ?? "open").lowercased() == "resolved" ? "Reopen Fault" : "Mark Resolved")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isUpdating)
            }
        }
        .navigationTitle("Fault Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func toggleStatus() async {
        isUpdating = true
        defer { isUpdating = false }

        let nextStatus = (fault.status ?? "open").lowercased() == "resolved" ? "open" : "resolved"

        do {
            try await faultViewModel.updateStatus(
                fault: fault,
                status: nextStatus,
                fleetId: fleetId
            )
            errorText = ""
        } catch {
            errorText = "Failed to update status."
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
