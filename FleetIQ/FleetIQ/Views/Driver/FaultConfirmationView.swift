//
//  FaultConfirmationView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import CoreData
import CoreLocation

// MARK: - Fault Confirmation View
struct FaultConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @StateObject private var faultViewModel = FaultViewModel()
    @State private var assignedVehicle: VehicleEntity?
    @State private var deliveryDurationSeconds: Double = 0.2
    @State private var nearbyGarages: [NominatimResult] = []
    @State private var isLoadingGarages = false

    let faultId: UUID
    let submittedAt: Date
    let fleetId: String
    let driverId: String
    let vehicleId: String
    let onDone: () -> Void

    private var currentFault: FaultReportEntity? {
        faultViewModel.myFaults.first { $0.id == faultId }
    }

    private var registration: String {
        assignedVehicle?.registration ?? "Assigned Vehicle"
    }

    private var managerStatusText: String {
        let raw = (currentFault?.status ?? "open")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch raw {
        case "acknowledged":
            return "Acknowledged"
        case "workshop_booked":
            return "Workshop Booked"
        case "in_progress", "in progress":
            return "In Progress"
        case "resolved":
            return "Resolved"
        default:
            return "Open"
        }
    }

    private var managerStatusColor: Color {
        let normalized = managerStatusText.lowercased()
        switch normalized {
        case "resolved":
            return .statusActive
        case "workshop booked", "in progress":
            return .statusDueSoon
        case "acknowledged":
            return .driverGreen
        default:
            return .statusOverdue
        }
    }

    private var submittedCoordinate: CLLocationCoordinate2D? {
        guard let fault = currentFault else {
            return nil
        }

        let lat = fault.latitude
        let lon = fault.longitude
        guard !(lat == 0 && lon == 0) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                alarmHeader
                deliveredCard
                managerStatusCard
                garagesSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .safeAreaInset(edge: .bottom) {
            backToVehicleButton
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 94)
                .background(Color.clear)
        }
        .navigationTitle("Confirmation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    onDone()
                    dismiss()
                }
                .foregroundStyle(.white)
            }
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [Color(hex: "081428"), Color(hex: "112E55"), Color(hex: "1A3C6E")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .task {
            loadAssignedVehicle()
            deliveryDurationSeconds = max(0.2, Date().timeIntervalSince(submittedAt))

            let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDriverId = driverId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedFleetId.isEmpty, !normalizedDriverId.isEmpty else {
                return
            }

            faultViewModel.startMyFaultListener(
                fleetId: normalizedFleetId,
                driverId: normalizedDriverId
            )
        }
        .task(id: currentFault?.id) {
            await loadNearbyGarages()
        }
    }

    private var alarmHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.chipRedBg)
                    .frame(width: 84, height: 84)

                Image(systemName: "alarm.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.statusOverdue)
            }

            Text("Fault Report Sent")
                .font(.title2.weight(.bold))

            Text("Your report for \(registration) has been delivered and is now visible to your manager.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var deliveredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.statusActive)
                Text("Delivered to Manager")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.chipGreenText)
            }

            HStack {
                Text("Submitted")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(submittedAt.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            HStack {
                Text("Time taken")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f sec", deliveryDurationSeconds))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.chipGreenBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var managerStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manager Status")
                .font(.headline)
                .foregroundStyle(.white)

            HStack {
                Text(managerStatusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(managerStatusColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(managerStatusColor.opacity(0.16))
                    .clipShape(Capsule())

                Spacer()

                Text("Live")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
            }

            Text("This status updates in real time when your manager takes action.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.78))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var garagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEAREST GARAGES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .tracking(0.5)

            if isLoadingGarages {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Finding nearby garages…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.vertical, 4)
            } else if nearbyGarages.isEmpty {
                Text("Garage recommendations will appear here in Part 8 using your report location.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.82))

                Text("Map integration is coming next.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
            } else {
                ForEach(nearbyGarages) { garage in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(Color.white.opacity(0.9))

                            Text(garage.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(.white)

                            Spacer()
                        }

                        if let coordinate = submittedCoordinate {
                            Text(String(format: "%.1f km away",
                                        NominatimService.shared.distanceKm(
                                            from: coordinate,
                                            to: garage.coordinate)))
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.78))
                        }
                    }

                    if garage.id != nearbyGarages.last?.id {
                        Divider()
                            .overlay(Color.white.opacity(0.16))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var backToVehicleButton: some View {
        if let assignedVehicle {
            NavigationLink {
                MyVehicleDetailView(vehicle: assignedVehicle)
            } label: {
                Text("Back to My Vehicle")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                onDone()
                dismiss()
            } label: {
                Text("Back to My Vehicle")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func loadAssignedVehicle() {
        guard let vehicleUUID = UUID(uuidString: vehicleId) else {
            assignedVehicle = nil
            return
        }

        let request = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", vehicleUUID as CVarArg)

        assignedVehicle = try? context.fetch(request).first
    }

    private func loadNearbyGarages() async {
        guard let coordinate = submittedCoordinate else {
            nearbyGarages = []
            return
        }

        isLoadingGarages = true
        nearbyGarages = (try? await NominatimService.shared.findNearestGarages(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )) ?? []
        isLoadingGarages = false
    }
}

#Preview {
    NavigationStack {
        FaultConfirmationView(
            faultId: UUID(),
            submittedAt: Date(),
            fleetId: "fleet_demo",
            driverId: "driver_demo",
            vehicleId: UUID().uuidString,
            onDone: {}
        )
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
