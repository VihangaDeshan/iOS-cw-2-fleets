//
//  AnalyticsView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Analytics View
struct AnalyticsView: View {
    @EnvironmentObject private var fleetViewModel: FleetViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var monthlySpend: Double = 0
    @State private var averageEfficiency: Double = 0
    @State private var bestVehicleRegistration = "-"
    @State private var openFaultCount = 0
    @State private var expiringInsuranceCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                efficiencyCard
                alertsCard
            }
            .padding(16)
        }
        .background(Color.systemGroupedBg)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadMetrics)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FLEET STATUS")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .tracking(1)

                    Text("\(fleetViewModel.vehicles.count) Vehicles")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("MONTHLY SPEND")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .tracking(1)
                    Text("LKR \(String(format: "%.0f", monthlySpend))")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                }
            }

            HStack(spacing: 16) {
                dotLegend(color: .statusActive, text: "\(fleetViewModel.activeCount) Active")
                dotLegend(color: .statusDueSoon, text: "\(fleetViewModel.dueSoonCount) Due")
                dotLegend(color: .statusOverdue, text: "\(fleetViewModel.overdueCount) Overdue")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.navyPrimary, Color.navySecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
    }

    private var efficiencyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EFFICIENCY")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(1)

                    Text("\(String(format: "%.1f", averageEfficiency)) km/L")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("BEST VEHICLE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(1)

                    Text(bestVehicleRegistration)
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.3 + Double(index) * 0.08))
                        .frame(width: 40, height: CGFloat(25 + index * 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: "60C98D"), Color(hex: "2F74C6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("→  \(openFaultCount) VEHICLE FAULT")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            Text("→  \(expiringInsuranceCount) INSURANCE WILL EXPIRE SOON")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: "FF3B30"), Color(hex: "A9487B")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
    }

    private func dotLegend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func loadMetrics() {
        let serviceRequest = ServiceRecordEntity.fetchRequest()
        let fuelRequest = FuelLogEntity.fetchRequest()

        do {
            let serviceRecords = try context.fetch(serviceRequest)
            let fuelLogs = try context.fetch(fuelRequest)

            let calendar = Calendar.current
            let currentMonth = calendar.component(.month, from: Date())
            let currentYear = calendar.component(.year, from: Date())

            let monthlyService = serviceRecords.filter {
                guard let date = $0.date else { return false }
                return calendar.component(.month, from: date) == currentMonth &&
                    calendar.component(.year, from: date) == currentYear
            }
            .reduce(0) { $0 + $1.costLKR }

            let monthlyFuel = fuelLogs.filter {
                guard let date = $0.date else { return false }
                return calendar.component(.month, from: date) == currentMonth &&
                    calendar.component(.year, from: date) == currentYear
            }
            .reduce(0) { $0 + $1.totalCostLKR }

            monthlySpend = monthlyService + monthlyFuel

            let validEfficiencies = fuelLogs.filter { $0.kmPerLitre > 0 }
            averageEfficiency = validEfficiencies.isEmpty
                ? 0
                : validEfficiencies.reduce(0) { $0 + $1.kmPerLitre } / Double(validEfficiencies.count)

            if let bestFuel = validEfficiencies.max(by: { $0.kmPerLitre < $1.kmPerLitre }),
               let id = bestFuel.vehicleId,
               let vehicle = fleetViewModel.vehicles.first(where: { $0.id == id }) {
                bestVehicleRegistration = vehicle.registration ?? "-"
            } else {
                bestVehicleRegistration = "-"
            }
        } catch {
            monthlySpend = 0
            averageEfficiency = 0
            bestVehicleRegistration = "-"
        }

        let faultRequest = FaultReportEntity.fetchRequest()
        faultRequest.predicate = NSPredicate(format: "status != %@", "resolved")
        openFaultCount = (try? context.count(for: faultRequest)) ?? 0

        let insuranceSoon = fleetViewModel.vehicles.filter { vehicle in
            guard let expiry = vehicle.insuranceExpiry else {
                return false
            }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
            return days >= 0 && days <= 30
        }
        expiringInsuranceCount = insuranceSoon.count
    }
}
