//
//  AnalyticsViewModel.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-05-04.
//

import Foundation
import CoreData
import Combine

struct VehicleCostData: Identifiable {
    let id: UUID = UUID()
    let registration: String
    let totalCostLKR: Double
}

struct CategoryCostData: Identifiable {
    let id: UUID = UUID()
    let category: String
    let costLKR: Double
}

@MainActor
final class AnalyticsViewModel: ObservableObject {
    @Published var selectedMonth: Date = Date()
    @Published var vehicleCosts: [VehicleCostData] = []
    @Published var categoryCosts: [CategoryCostData] = []
    @Published var totalSpentLKR: Double = 0
    @Published var totalServices: Int = 0
    @Published var totalFaults: Int = 0

    private let context = PersistenceController.shared.viewContext

    /// Loads analytics data from CoreData for selectedMonth.
    func loadData() {
        let calendar = Calendar.current
        guard
            let startOfMonth = calendar.date(
                from: calendar.dateComponents(
                    [.year, .month], from: selectedMonth)),
            let nextMonth = calendar.date(
                byAdding: .month, value: 1, to: startOfMonth)
        else { return }

        let serviceReq = ServiceRecordEntity.fetchRequest()
        serviceReq.predicate = NSPredicate(
            format: "date >= %@ AND date < %@",
            startOfMonth as CVarArg,
            nextMonth as CVarArg)
        let serviceRecords = (try? context.fetch(serviceReq)) ?? []

        let fuelReq = FuelLogEntity.fetchRequest()
        fuelReq.predicate = NSPredicate(
            format: "date >= %@ AND date < %@",
            startOfMonth as CVarArg,
            nextMonth as CVarArg)
        let fuelLogs = (try? context.fetch(fuelReq)) ?? []

        var vehicleMap: [UUID: Double] = [:]
        for record in serviceRecords {
            guard let vehicleId = record.vehicleId else { continue }
            vehicleMap[vehicleId, default: 0] += record.costLKR
        }
        for log in fuelLogs {
            guard let vehicleId = log.vehicleId else { continue }
            vehicleMap[vehicleId, default: 0] += log.totalCostLKR
        }

        let allVehicles = (try? context.fetch(VehicleEntity.fetchRequest())) ?? []
        let regMap = Dictionary(uniqueKeysWithValues: allVehicles.compactMap { vehicle -> (UUID, String)? in
            guard let id = vehicle.id else { return nil }
            return (id, vehicle.registration ?? id.uuidString)
        })

        vehicleCosts = vehicleMap
            .sorted { $0.value > $1.value }
            .map { vehicleId, cost in
                VehicleCostData(
                    registration: regMap[vehicleId] ?? vehicleId.uuidString,
                    totalCostLKR: cost)
            }

        var categoryMap: [String: Double] = [:]
        for record in serviceRecords {
            let category = record.serviceType ?? "Other"
            categoryMap[category, default: 0] += record.costLKR
        }

        let totalFuel = fuelLogs.reduce(0) { $0 + $1.totalCostLKR }
        if totalFuel > 0 {
            categoryMap["Fuel"] = totalFuel
        }

        categoryCosts = categoryMap
            .sorted { $0.value > $1.value }
            .map { CategoryCostData(category: $0.key, costLKR: $0.value) }

        totalSpentLKR = vehicleMap.values.reduce(0, +)
        totalServices = serviceRecords.count

        let faultReq = FaultReportEntity.fetchRequest()
        faultReq.predicate = NSPredicate(format: "status != %@", "resolved")
        totalFaults = (try? context.count(for: faultReq)) ?? 0
    }

    /// Moves selectedMonth back one month and reloads.
    func previousMonth() {
        guard let newDate = Calendar.current.date(
            byAdding: .month, value: -1, to: selectedMonth)
        else { return }
        selectedMonth = newDate
        loadData()
    }

    /// Moves selectedMonth forward one month and reloads.
    func nextMonth() {
        guard let newDate = Calendar.current.date(
            byAdding: .month, value: 1, to: selectedMonth)
        else { return }
        selectedMonth = newDate
        loadData()
    }

    /// e.g. "March 2026"
    var monthDisplayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }
}
