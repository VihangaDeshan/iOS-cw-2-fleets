//
//  FaultDetailView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import CoreData

// MARK: - Manager Fault Detail View
struct FaultDetailView: View {
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

#Preview {
    NavigationStack {
        FaultDetailView(
            fault: FaultReportEntity(),
            fleetId: "fleet_demo",
            faultViewModel: FaultViewModel()
        )
    }
}
