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
            VStack(spacing: 20) {
                heroCard
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("DOCUMENTS")
                    documentsCard
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("LAST SERVICE")
                    lastServiceCard
                }

                managerOnlyCard
                
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 14)
        }
        .background(Color.systemGroupedBg)
        .navigationTitle("My Vehicle")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero
    private var heroCard: some View {
        let status = serviceStatus(for: vehicle)

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.registration ?? "UNKNOWN")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text(vehicleSubtitle())
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                VehicleStatusChip(status: status)
            }

            HStack(spacing: 12) {
                statItem(label: "ODOMETER", value: String(format: "%.0f km", vehicle.currentMileage))
                statItem(label: "NEXT SERVICE", value: String(format: "%.0f km", predictedNextServiceMileage(for: vehicle)))
                statItem(label: "EST. DAYS", value: daysLeftText(for: vehicle))
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.navyPrimary, Color(hex: "2E5BA8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.navyPrimary.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
                .tracking(0.5)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func vehicleSubtitle() -> String {
        [
            vehicle.make,
            vehicle.model,
            vehicle.year > 0 ? String(vehicle.year) : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    // MARK: - Documents
    private var documentsCard: some View {
        VStack(spacing: 0) {
            documentRow(icon: "doc.text.fill", name: "Revenue Licence", date: vehicle.licenceExpiry)

            Divider()
                .padding(.leading, 50)

            documentRow(icon: "shield.lefthalf.filled", name: "Insurance Certificate", date: vehicle.insuranceExpiry)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    private func documentRow(icon: String, name: String, date: Date?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.navyPrimary)
                .frame(width: 36, height: 36)
                .background(Color.navyPrimary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
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
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(expiryColor(for: date))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(expiryColor(for: date).opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(14)
    }

    // MARK: - Last Service
    private var lastServiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let record = fetchLastServiceRecord() {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.serviceType?.uppercased() ?? "SERVICE")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        
                        Text(mediumDate(record.date ?? Date()))
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    Text("LKR \(String(format: "%.0f", record.costLKR))")
                        .font(.headline)
                        .foregroundColor(.navyPrimary)
                }
                
                Divider()
                
                HStack {
                    Label("\(String(format: "%.0f km", record.mileageAtService))", systemImage: "gauge.with.needle")
                        .font(.subheadline.weight(.medium))
                    
                    Spacer()
                    
                    Text("Service completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "No Records",
                    systemImage: "wrench.adjust.fill",
                    description: Text("No service records found for this vehicle.")
                )
                .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    // MARK: - Manager Controls
    private var managerOnlyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(Color(.systemGray6))
                .clipShape(Circle())

            Text("Vehicle details, driver assignment, and cost reports are managed by your fleet manager.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 4)
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
