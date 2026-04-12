//
//  CostReportView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Cost Report View
struct CostReportView: View {
    let vehicle: VehicleEntity

    @Environment(\.managedObjectContext) private var context

    @State private var serviceRecords: [ServiceRecordEntity] = []
    @State private var fuelLogs: [FuelLogEntity] = []

    var body: some View {
        List {
            summarySection
            monthlyBreakdownSection
            recentExpensesSection
        }
        .navigationTitle("Cost Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadData)
    }

    private var summarySection: some View {
        Section("SUMMARY") {
            summaryRow(title: "Service Cost", value: totalServiceCost)
            summaryRow(title: "Fuel Cost", value: totalFuelCost)
            summaryRow(title: "Total Cost", value: totalServiceCost + totalFuelCost, emphasized: true)
        }
    }

    private var monthlyBreakdownSection: some View {
        Section("MONTHLY BREAKDOWN") {
            if monthlyTotals.isEmpty {
                Text("No monthly cost data yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(monthlyTotals, id: \.monthKey) { item in
                    HStack {
                        Text(item.monthKey)
                        Spacer()
                        Text("LKR \(String(format: "%.0f", item.total))")
                            .fontWeight(.semibold)
                            .foregroundColor(.navyPrimary)
                    }
                }
            }
        }
    }

    private var recentExpensesSection: some View {
        Section("RECENT ENTRIES") {
            if recentEntries.isEmpty {
                Text("No entries to show")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(recentEntries.enumerated()), id: \.offset) { _, entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text("LKR \(String(format: "%.0f", entry.amount))")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.navyPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var totalServiceCost: Double {
        serviceRecords.reduce(0) { $0 + $1.costLKR }
    }

    private var totalFuelCost: Double {
        fuelLogs.reduce(0) { $0 + $1.totalCostLKR }
    }

    private var monthlyTotals: [(monthKey: String, total: Double)] {
        var totals: [String: Double] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"

        for record in serviceRecords {
            let key = formatter.string(from: record.date ?? Date())
            totals[key, default: 0] += record.costLKR
        }

        for log in fuelLogs {
            let key = formatter.string(from: log.date ?? Date())
            totals[key, default: 0] += log.totalCostLKR
        }

        return totals
            .map { (monthKey: $0.key, total: $0.value) }
            .sorted { lhs, rhs in
                monthDate(lhs.monthKey) > monthDate(rhs.monthKey)
            }
    }

    private var recentEntries: [(title: String, subtitle: String, amount: Double, date: Date)] {
        var entries: [(title: String, subtitle: String, amount: Double, date: Date)] = []

        for record in serviceRecords {
            entries.append((
                title: record.serviceType ?? "Service",
                subtitle: mediumDate(record.date ?? Date()),
                amount: record.costLKR,
                date: record.date ?? Date()
            ))
        }

        for log in fuelLogs {
            entries.append((
                title: "Fuel Fill-Up",
                subtitle: mediumDate(log.date ?? Date()),
                amount: log.totalCostLKR,
                date: log.date ?? Date()
            ))
        }

        return entries
            .sorted { $0.date > $1.date }
            .prefix(12)
            .map { $0 }
    }

    private func summaryRow(title: String, value: Double, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .fontWeight(emphasized ? .semibold : .regular)
            Spacer()
            Text("LKR \(String(format: "%.0f", value))")
                .fontWeight(emphasized ? .bold : .semibold)
                .foregroundColor(emphasized ? .navyPrimary : .primary)
        }
    }

    private func loadData() {
        guard let vehicleId = vehicle.id else {
            serviceRecords = []
            fuelLogs = []
            return
        }

        let serviceRequest = ServiceRecordEntity.fetchRequest()
        serviceRequest.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        serviceRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        let fuelRequest = FuelLogEntity.fetchRequest()
        fuelRequest.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        fuelRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            serviceRecords = try context.fetch(serviceRequest)
            fuelLogs = try context.fetch(fuelRequest)
        } catch {
            serviceRecords = []
            fuelLogs = []
        }
    }

    private func monthDate(_ monthKey: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.date(from: monthKey) ?? .distantPast
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
