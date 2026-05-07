//
//  FaultDetailView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import CoreData
import MapKit

// MARK: - Manager Fault Detail View
struct FaultDetailView: View {
    @Environment(\.managedObjectContext) private var context

    let fault: FaultReportEntity
    let fleetId: String

    @ObservedObject var faultViewModel: FaultViewModel

    @State private var selectedStatus: ManagerFaultStatus = .acknowledged
    @State private var isHydratingSelection = true
    @State private var isUpdatingStatus = false
    @State private var isResolving = false
    @State private var selectedPhotoIndex = 0
    @State private var nearbyGarages: [NominatimResult] = []
    @State private var isLoadingGarages = false

    @State private var vehicleRegistration = "Unknown Vehicle"
    @State private var driverDisplayName = "Driver"

    @State private var errorText = ""

    private let nominatimService = NominatimService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                dangerBanner
                descriptionCard
                photoCard
                mapSection
                statusCard

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Color.statusOverdue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }
            }
            .padding(16)
        }
        .background(Color.systemGroupedBg)
        .navigationTitle("Fault Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await resolveFaultNow()
                    }
                } label: {
                    if isResolving {
                        ProgressView()
                    } else {
                        Text("Resolve")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .disabled(isResolving || selectedStatus == .resolved || normalizedFleetId.isEmpty)
                .accessibilityLabel("Resolve this fault")
                .accessibilityHint("Marks fault as resolved")
            }
        }
        .task {
            hydrateInitialState()
            await loadMetaDetails()
            await loadNearbyGarages()
        }
        .onChange(of: photoReferences.count) { _, newCount in
            if newCount == 0 {
                selectedPhotoIndex = 0
            } else if selectedPhotoIndex >= newCount {
                selectedPhotoIndex = max(0, newCount - 1)
            }
        }
        .onChange(of: selectedStatus) { _, newStatus in
            guard !isHydratingSelection else {
                return
            }

            Task {
                await writeStatus(newStatus)
            }
        }
    }

    private var normalizedFleetId: String {
        fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var photoReferences: [String] {
        faultViewModel.photoReferences(for: fault)
    }

    private var dangerBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.statusOverdue.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.statusOverdue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Active Fault Incident")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.chipRedText)

                Text(vehicleRegistration)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(driverDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formattedDate(fault.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.chipRedBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FAULT DESCRIPTION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Text(fault.descriptionText ?? "No description")
                .font(.body)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text(formattedUrgency(fault.urgency ?? "medium"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(urgencyColor(for: fault.urgency ?? "medium"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(urgencyColor(for: fault.urgency ?? "medium").opacity(0.14))
                    .clipShape(Capsule())

                Text(humanStatusText(from: fault.status ?? "open"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHOTO EVIDENCE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            if photoReferences.isEmpty {
                photoPlaceholder(message: "No photo attached.")
            } else {
                Text("\(photoReferences.count) image(s) attached")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if photoReferences.count == 1 {
                    photoPreview(for: photoReferences[0])
                } else {
                    TabView(selection: $selectedPhotoIndex) {
                        ForEach(Array(photoReferences.enumerated()), id: \.offset) { index, reference in
                            photoPreview(for: reference)
                                .tag(index)
                                .padding(.horizontal, 1)
                        }
                    }
                    .frame(height: 220)
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }

                if photoReferences.contains(where: { $0.hasPrefix("storage_path:") }) {
                    Text("Some images are still syncing from Firebase Storage.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DRIVER LOCATION & NEAREST GARAGES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            let lat = fault.latitude
            let lon = fault.longitude
            let hasLocation = !(lat == 0 && lon == 0)

            if !hasLocation {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.navyPrimary)

                    Text("Driver location was not captured for this fault.")
                        .font(.subheadline)
                        .foregroundStyle(Color.navyPrimary)

                    Spacer()
                }
                .padding(12)
                .background(Color(hex: "E8F0FB"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if isLoadingGarages {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Finding nearest garages…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                FaultMapView(
                    driverCoordinate: CLLocationCoordinate2D(
                        latitude: lat,
                        longitude: lon
                    ),
                    garages: nearbyGarages
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("UPDATE STATUS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                if isUpdatingStatus {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            Picker("Status", selection: $selectedStatus) {
                ForEach(ManagerFaultStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
            .pickerStyle(.segmented)

            Text("Changes sync to Firestore immediately. Drivers receive updates in real time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func photoPreview(for reference: String) -> some View {
        if reference.hasPrefix("http://") || reference.hasPrefix("https://"),
           let url = URL(string: reference) {
            return AnyView(
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.systemGray6))
                            ProgressView()
                        }
                        .frame(height: 210)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure(_):
                        photoPlaceholder(message: "Could not load one of the fault photos.", height: 210)
                    @unknown default:
                        photoPlaceholder(message: "Photo preview unavailable.", height: 210)
                    }
                }
            )
        }

        if reference.hasPrefix("storage_path:") {
            return AnyView(photoPlaceholder(message: "Photo uploaded. Preview URL is still syncing.", height: 210))
        }

        if reference == "upload_failed" {
            return AnyView(photoPlaceholder(message: "Photo upload failed for this report.", height: 210))
        }

        return AnyView(photoPlaceholder(message: "Photo preview unavailable.", height: 210))
    }

    private func photoPlaceholder(message: String, height: CGFloat = 148) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.systemGray6))
            .frame(height: height)
            .overlay {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
    }

    private func hydrateInitialState() {
        selectedStatus = ManagerFaultStatus.fromStoredStatus(fault.status ?? "open")
        DispatchQueue.main.async {
            isHydratingSelection = false
        }
    }

    private func loadMetaDetails() async {
        vehicleRegistration = loadVehicleRegistration()
        driverDisplayName = await loadDriverName()
    }

    private func loadNearbyGarages() async {
        let lat = fault.latitude
        let lon = fault.longitude
        guard !(lat == 0 && lon == 0) else { return }

        isLoadingGarages = true
        nearbyGarages = (try? await nominatimService.findNearestGarages(latitude: lat, longitude: lon)) ?? []
        isLoadingGarages = false
    }

    private func loadVehicleRegistration() -> String {
        guard let vehicleId = fault.vehicleId else {
            return "Unknown Vehicle"
        }

        let request = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", vehicleId as CVarArg)

        if let vehicle = try? context.fetch(request).first,
           let registration = vehicle.registration,
           !registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return registration
        }

        return "Unknown Vehicle"
    }

    private func loadDriverName() async -> String {
        let driverId = (fault.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty, !driverId.isEmpty else {
            return "Driver"
        }

        do {
            let drivers = try await FirestoreService.shared.fetchFleetDriverUsers(fleetId: normalizedFleetId)
            if let matched = drivers.first(where: { $0.userId == driverId }),
               !matched.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return matched.name
            }
        } catch {
            // Fallback to ID snippet for display-only metadata.
        }

        return "Unknown Driver"
    }

    private func writeStatus(_ status: ManagerFaultStatus) async {
        guard !normalizedFleetId.isEmpty else {
            errorText = "Fleet ID is missing."
            return
        }

        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            try await faultViewModel.updateStatus(
                fault: fault,
                status: status.firestoreValue,
                fleetId: normalizedFleetId
            )
            errorText = ""
        } catch {
            errorText = "Failed to update status."
        }
    }

    private func resolveFaultNow() async {
        selectedStatus = .resolved
        isResolving = true
        defer { isResolving = false }

        await writeStatus(.resolved)
    }

    private func humanStatusText(from status: String) -> String {
        ManagerFaultStatus.fromStoredStatus(status).title
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

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private enum ManagerFaultStatus: String, CaseIterable, Identifiable {
    case acknowledged
    case workshopBooked
    case resolved

    var id: String { firestoreValue }

    var firestoreValue: String {
        switch self {
        case .acknowledged:
            return "acknowledged"
        case .workshopBooked:
            return "workshop_booked"
        case .resolved:
            return "resolved"
        }
    }

    var title: String {
        switch self {
        case .acknowledged:
            return "Acknowledged"
        case .workshopBooked:
            return "Workshop Booked"
        case .resolved:
            return "Resolved"
        }
    }

    static func fromStoredStatus(_ status: String) -> ManagerFaultStatus {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "resolved":
            return .resolved
        case "workshop_booked", "workshop booked", "in_progress", "in progress":
            return .workshopBooked
        default:
            return .acknowledged
        }
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
