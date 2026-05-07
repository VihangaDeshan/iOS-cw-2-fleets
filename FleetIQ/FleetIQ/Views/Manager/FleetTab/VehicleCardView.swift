//
//  VehicleCardView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Vehicle Card View
struct VehicleCardView: View {
    // MARK: - Stored Properties
    let vehicle: VehicleEntity
    let drivers: [FleetDriverUser]
    @EnvironmentObject var fleetViewModel: FleetViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    // MARK: - Computed Properties
    var status: String {
        fleetViewModel.vehicleStatus(vehicle)
    }

    var days: Int {
        fleetViewModel.daysUntilService(vehicle)
    }

    var daysText: String {
        if days < 0 {
            return "\(abs(days)) days overdue"
        } else if days == 0 {
            return "Due today"
        } else {
            return "Service in \(days) days"
        }
    }

    var daysColour: Color {
        switch status {
        case "Overdue":
            return .statusOverdue
        case "Due Soon":
            return .statusDueSoon
        default:
            return Color.secondary
        }
    }

    var progressValue: Double {
        let interval = fleetViewModel.predictedNextServiceMileage(vehicle) - (vehicle.currentMileage - 5000)
        guard interval > 0 else {
            return 1.0
        }

        let used = 5000.0 - Double(days) * 15.0
        return min(max(used / interval, 0), 1.0)
    }

    var progressBarColour: Color {
        switch status {
        case "Overdue":
            return .statusOverdue
        case "Due Soon":
            return .statusDueSoon
        default:
            return .statusActive
        }
    }

    var assignedDriverDisplayName: String {
        let raw = (vehicle.assignedDriverId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty else {
            return "Unassigned"
        }

        // 1. Try direct userId match (UUID or Firebase Auth UID).
        if let matched = drivers.first(where: { $0.userId == raw }),
           !matched.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return matched.name
        }

        // 2. Try vehicle-assignment-based match.
        if let vehicleId = vehicle.id?.uuidString,
           let matched = drivers.first(where: { $0.assignedVehicleId == vehicleId }),
           !matched.name.isEmpty {
            return matched.name
        }

        // 3. Hide raw IDs from the user.
        if raw.count > 12 && !raw.contains(" ") {
            return "Assigned Driver"
        }

        // 4. Legacy plain-name string.
        return raw
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(vehicle.registration ?? "Unknown")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(.primary)

                Spacer()

                VehicleStatusChip(status: status)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(vehicle.make ?? "") \(vehicle.model ?? "") · \(vehicle.year)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(daysText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(daysColour)
            }
            .padding(.top, 3)

            HStack {
                Circle()
                    .fill(Color.navyPrimary)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(initials(assignedDriverDisplayName))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    )

                Text(assignedDriverDisplayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                NavigationLink {
                    VehicleDetailView(vehicle: vehicle)
                        .environmentObject(authViewModel)
                        .environmentObject(fleetViewModel)
                } label: {
                    Text("Details ›")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.navyPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "E8F0FB"))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .accessibilityLabel("View details for \(vehicle.registration ?? "")")
            }
            .padding(.top, 6)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)

                    Capsule()
                        .fill(progressBarColour)
                        .frame(width: geo.size.width * progressValue, height: 4)
                }
            }
            .frame(height: 4)
            .padding(.top, 7)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(vehicle.registration ?? ""), status \(status), \(daysText)")
    }

    // MARK: - Helpers
    /// Returns two-letter initials from a name string.
    /// - Parameter name: Name string to shorten.
    /// - Returns: Two-letter uppercase initials.
    func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")

        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }

        return String(name.prefix(2)).uppercased()
    }
}

#Preview {
    let context = PersistenceController.preview.viewContext
    let sample = VehicleEntity(context: context)
    sample.id = UUID()
    sample.registration = "CAB-1234"
    sample.make = "Toyota"
    sample.model = "KDH"
    sample.year = 2018
    sample.currentMileage = 120000
    sample.fuelType = "Diesel"
    sample.createdAt = Date()
    sample.assignedDriverId = "Kamal Silva"

    return NavigationStack {
        VehicleCardView(vehicle: sample, drivers: [])
            .environmentObject(AuthViewModel())
            .environmentObject(FleetViewModel())
            .padding()
            .background(Color.systemGroupedBg)
    }
}
