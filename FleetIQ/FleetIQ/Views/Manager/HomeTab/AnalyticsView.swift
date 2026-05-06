//
//  AnalyticsView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData
import Charts

// MARK: - Analytics View
struct AnalyticsView: View {
    @EnvironmentObject private var fleetViewModel: FleetViewModel
    @Environment(\.managedObjectContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var analyticsVM = AnalyticsViewModel()

    @State private var averageEfficiency: Double = 0
    @State private var bestVehicleRegistration = "-"
    @State private var openFaultCount = 0
    @State private var expiringInsuranceCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                monthNavigationCard
                summaryStatsRow
                monthlyCostCard
                spendingByCategoryCard
                efficiencyCard
                alertsCard
            }
            .padding(16)
        }
        .background(Color.systemGroupedBg)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            analyticsVM.loadData()
            loadMetrics()
        }
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
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("MONTHLY SPEND")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .tracking(1)
                    Text("LKR \(formatted(analyticsVM.totalSpentLKR))")
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

    private var monthNavigationCard: some View {
        HStack {
            Button {
                analyticsVM.previousMonth()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(.navyPrimary)
            }
            .accessibilityLabel("Previous month")
            .accessibilityHint("Moves analytics back one month")

            Spacer()

            Text(analyticsVM.monthDisplayString)
                .font(.headline)

            Spacer()

            Button {
                analyticsVM.nextMonth()
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.navyPrimary)
            }
            .accessibilityLabel("Next month")
            .accessibilityHint("Moves analytics forward one month")
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    private var summaryStatsRow: some View {
        HStack(spacing: 8) {
            statMiniCard(
                label: "LKR Spent",
                value: "LKR \(formatted(analyticsVM.totalSpentLKR))",
                valueColor: .statusOverdue)
            statMiniCard(
                label: "Services",
                value: "\(analyticsVM.totalServices)",
                valueColor: .primary)
            statMiniCard(
                label: "Open Faults",
                value: "\(analyticsVM.totalFaults)",
                valueColor: .statusDueSoon)
        }
    }

    private var monthlyCostCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MONTHLY COST PER VEHICLE")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if analyticsVM.vehicleCosts.isEmpty {
                Text("No records for \(analyticsVM.monthDisplayString)")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Chart(analyticsVM.vehicleCosts) { item in
                    BarMark(
                        x: .value("Vehicle", item.registration),
                        y: .value("LKR", item.totalCostLKR))
                    .foregroundStyle(Color.navyPrimary)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text("LKR \(formatted(item.totalCostLKR))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .animation(
                    reduceMotion ? .none : .easeInOut,
                    value: analyticsVM.vehicleCosts.count)
                .accessibilityLabel(
                    "Bar chart showing monthly cost per vehicle for \(analyticsVM.monthDisplayString)")
            }

            Text("Swift Charts · BarMark")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    private var spendingByCategoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FLEET SPENDING BY CATEGORY")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if analyticsVM.categoryCosts.isEmpty {
                Text("No category data this month")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Chart(analyticsVM.categoryCosts) { item in
                    BarMark(
                        x: .value("Month", "This Month"),
                        y: .value("LKR", item.costLKR))
                    .foregroundStyle(
                        by: .value("Category", item.category))
                    .cornerRadius(4)
                }
                .frame(height: 160)
                .chartForegroundStyleScale(range: categoryPalette)
                .animation(
                    reduceMotion ? .none : .easeInOut,
                    value: analyticsVM.categoryCosts.count)
                .accessibilityLabel(
                    "Stacked bar chart showing fleet spending by category")

                ForEach(Array(analyticsVM.categoryCosts.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(categoryColor(for: index))
                            .frame(width: 10, height: 10)
                        Text(item.category)
                            .font(.caption)
                        Spacer()
                        Text("LKR \(formatted(item.costLKR))")
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            Text("BarMark + foregroundStyle(by:.value)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
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
                        .font(.largeTitle.weight(.bold))
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

    private var categoryPalette: [Color] {
        [
            Color.navyPrimary,
            Color.navySecondary,
            Color.driverGreen,
            Color.statusDueSoon,
            Color.statusOverdue,
            Color(hex: "2E7D52")
        ]
    }

    private func categoryColor(for index: Int) -> Color {
        guard !categoryPalette.isEmpty else { return .navyPrimary }
        return categoryPalette[index % categoryPalette.count]
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func statMiniCard(
        label: String,
        value: String,
        valueColor: Color
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(valueColor)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.07), radius: 3)
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
