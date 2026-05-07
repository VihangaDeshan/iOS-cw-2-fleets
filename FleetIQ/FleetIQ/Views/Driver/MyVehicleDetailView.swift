//
//  MyVehicleDetailView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData
import FirebaseFirestore

// MARK: - My Vehicle Detail View
struct MyVehicleDetailView: View {
    let vehicle: VehicleEntity

    private let context = PersistenceController.shared.viewContext

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroCard
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                sectionHeader("DOCUMENTS")
                documentsCard
                    .padding(.horizontal, 12)

                sectionHeader("LAST SERVICE")
                lastServiceCard
                    .padding(.horizontal, 12)

                sectionHeader("MANAGER CONTROLS")
                managerOnlyCard
                    .padding(.horizontal, 12)

                Spacer(minLength: 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My Vehicle")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero
    private var heroCard: some View {
        let status = serviceStatus(for: vehicle)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vehicle.registration ?? "Unknown")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(.white)

                    Text(vehicleSubtitle())
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }

                Spacer()

                VehicleStatusChip(status: status)
            }

            HStack(spacing: 0) {
                statItem(label: "MILEAGE", value: String(format: "%.0f km", vehicle.currentMileage))

                Divider()
                    .background(.white.opacity(0.3))
                    .frame(height: 28)
                    .padding(.horizontal, 14)

                statItem(
                    label: "NEXT SERVICE",
                    value: String(format: "%.0f km", predictedNextServiceMileage(for: vehicle))
                )

                Divider()
                    .background(.white.opacity(0.3))
                    .frame(height: 28)
                    .padding(.horizontal, 14)

                statItem(label: "DAYS LEFT", value: daysLeftText(for: vehicle))
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [.navyPrimary, .navySecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .tracking(0.3)

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func vehicleSubtitle() -> String {
        [
            vehicle.make,
            vehicle.model,
            vehicle.year > 0 ? String(vehicle.year) : nil,
            vehicle.fuelType
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    // MARK: - Documents
    private var documentsCard: some View {
        VStack(spacing: 0) {
            documentRow(icon: "doc.text.fill", name: "Revenue Licence", date: vehicle.licenceExpiry)

            Divider()
                .padding(.leading, 48)

            documentRow(icon: "lock.shield.fill", name: "Insurance Certificate", date: vehicle.insuranceExpiry)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    private func documentRow(icon: String, name: String, date: Date?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.navyPrimary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))

                if let date {
                    Text("Expires \(mediumDate(date))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Not set")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(expiryChipText(for: date))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(expiryColor(for: date))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(expiryColor(for: date).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(13)
    }

    // MARK: - Last Service
    private var lastServiceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let record = fetchLastServiceRecord() {
                Text(record.serviceType ?? "Service")
                    .font(.headline)

                Text("Date: \(mediumDate(record.date ?? Date()))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Mileage: \(String(format: "%.0f km", record.mileageAtService))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Cost: LKR \(String(format: "%.0f", record.costLKR))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.navyPrimary)
            } else {
                Text("No service records found for this vehicle.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    // MARK: - Manager Controls
    private var managerOnlyCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundColor(.secondary)

            Text("Vehicle edits, driver assignment, and cost reports are managed by your fleet manager.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(13)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    // MARK: - Helpers
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }

    private func predictedNextServiceMileage(for vehicle: VehicleEntity) -> Double {
        guard let vehicleId = vehicle.id else {
            return vehicle.currentMileage + 5000
        }

        let request = NSFetchRequest<ServiceRecordEntity>(entityName: "ServiceRecordEntity")
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            let records = try context.fetch(request)
            let lastFullService = records.first { ($0.serviceType ?? "").localizedCaseInsensitiveContains("Full Service") }
            let lastMileage = lastFullService?.mileageAtService ?? (records.first?.mileageAtService ?? vehicle.currentMileage)
            return lastMileage + 5000
        } catch {
            return vehicle.currentMileage + 5000
        }
    }
    
    private func averageDailyKm(for vehicle: VehicleEntity) -> Double {
        guard let vehicleId = vehicle.id else {
            return 80
        }
        
        let request = NSFetchRequest<ServiceRecordEntity>(entityName: "ServiceRecordEntity")
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        
        do {
            let records = try context.fetch(request)
            guard let first = records.first, let last = records.last, first.id != last.id,
                  let firstDate = first.date, let lastDate = last.date else {
                return 80 // fallback
            }
            
            let days = Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0
            let kmDiff = last.mileageAtService - first.mileageAtService
            
            if days > 0 && kmDiff > 0 {
                return kmDiff / Double(days)
            }
        } catch {}
        
        return 80
    }

    private func daysLeftText(for vehicle: VehicleEntity) -> String {
        let remainingMileage = predictedNextServiceMileage(for: vehicle) - vehicle.currentMileage
        let dailyKm = averageDailyKm(for: vehicle)
        let days = Int((remainingMileage / max(1, dailyKm)).rounded(.down))

        if days < 0 {
            return "\(abs(days))d over"
        }

        return "\(days) days"
    }

    private func serviceStatus(for vehicle: VehicleEntity) -> String {
        let remainingMileage = predictedNextServiceMileage(for: vehicle) - vehicle.currentMileage
        let dailyKm = averageDailyKm(for: vehicle)
        let days = Int((remainingMileage / max(1, dailyKm)).rounded(.down))

        if days < 0 {
            return "Overdue"
        }

        if days <= 30 {
            return "Due Soon"
        }

        return "Active"
    }

    private func fetchLastServiceRecord() -> ServiceRecordEntity? {
        guard let vehicleId = vehicle.id else {
            return nil
        }

        let request = NSFetchRequest<ServiceRecordEntity>(entityName: "ServiceRecordEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try? context.fetch(request).first
    }

    private func expiryChipText(for date: Date?) -> String {
        guard let date else {
            return "Not set"
        }

        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 {
            return "Expired"
        }

        if days == 0 {
            return "Expires today"
        }

        return "\(days) days"
    }

    private func expiryColor(for date: Date?) -> Color {
        guard let date else {
            return .secondary
        }

        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days > 30 {
            return .statusActive
        }

        if days > 7 {
            return .statusDueSoon
        }

        return .statusOverdue
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        MyVehicleDetailView(vehicle: VehicleEntity())
    }
}
