//
//  FaultsTabView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI
import CoreData
import FirebaseFirestore

// MARK: - Faults Tab View
struct FaultsTabView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var faults: [FaultReportEntity] = []
    @State private var errorText = ""

    private let firestoreService = FirestoreService.shared

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

                if faults.isEmpty {
                    ContentUnavailableView(
                        "No Fault Reports",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Driver reported faults will appear here")
                    )
                } else {
                    ForEach(faults, id: \.id) { fault in
                        row(for: fault)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if (fault.status ?? "").lowercased() == "resolved" {
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
                }
            }
            .navigationTitle("Faults")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadFaults)
        }
    }

    private func row(for fault: FaultReportEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(fault.descriptionText ?? "Fault")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer()

                statusChip(status: fault.status ?? "open")
            }

            Text(
                "Urgency: \((fault.urgency ?? "medium").capitalized)  ·  " +
                mediumDate(fault.createdAt ?? Date())
            )
            .font(.caption)
            .foregroundColor(.secondary)

            if let photoURL = fault.photoURL, !photoURL.isEmpty {
                Text("Photo attached")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.statusActive)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusChip(status: String) -> some View {
        let lower = status.lowercased()
        let color: Color = lower == "resolved" ? .statusActive : .statusOverdue

        return Text(status.capitalized)
            .font(.caption2.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func loadFaults() {
        errorText = ""

        let request = FaultReportEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            faults = try context.fetch(request)
        } catch {
            faults = []
        }
    }

    private func updateStatus(for fault: FaultReportEntity, status: String) async {
        errorText = ""
        guard let faultId = fault.id?.uuidString else {
            errorText = "Fault ID is missing."
            return
        }

        let previous = fault.status
        fault.status = status

        do {
            try context.save()
            try await firestoreService.updateFaultReport(
                fleetId: authViewModel.fleetId,
                faultId: faultId,
                data: [
                    "status": status,
                    "updatedAt": Timestamp(date: Date())
                ]
            )
            loadFaults()
        } catch {
            fault.status = previous
            errorText = "Could not update fault status in cloud."
        }
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
