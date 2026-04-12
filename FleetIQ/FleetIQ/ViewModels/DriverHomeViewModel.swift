//
//  DriverHomeViewModel.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import Foundation
import Combine
import CoreData
import FirebaseFirestore

// MARK: - Driver Home View Model
@MainActor
final class DriverHomeViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var assignedVehicle: VehicleEntity?
    @Published var todayTrips: Int = 0
    @Published var todayFuelLogs: Int = 0
    @Published var openFaults: Int = 0
    @Published var todayKmDriven: Double = 0
    @Published var isLoadingVehicle: Bool = false

    // MARK: - Private Properties
    private let context = PersistenceController.shared.viewContext
    private let firestoreService = FirestoreService.shared
    private var vehicleListener: ListenerRegistration?

    // MARK: - Lifecycle
    deinit {
        vehicleListener?.remove()
    }

    // MARK: - Public API
    /// Starts loading driver home data and listens to the assigned vehicle document.
    func start(authViewModel: AuthViewModel) {
        let normalizedFleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVehicleId = authViewModel.assignedVehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDriverId = authViewModel.currentUID.trimmingCharacters(in: .whitespacesAndNewlines)

        loadAssignedVehicleFromCoreData(vehicleId: normalizedVehicleId)
        loadTodayStats(vehicleId: normalizedVehicleId, driverId: normalizedDriverId)
        startVehicleListener(
            fleetId: normalizedFleetId,
            vehicleId: normalizedVehicleId,
            driverId: normalizedDriverId
        )
    }

    /// Stops active listeners when driver screens are no longer visible.
    func stop() {
        vehicleListener?.remove()
        vehicleListener = nil
    }

    /// Predicts next service mileage from historical service intervals.
    func predictedNextServiceMileage(for vehicle: VehicleEntity) -> Double {
        guard let vehicleId = vehicle.id else {
            return vehicle.currentMileage + 5000
        }

        let request = NSFetchRequest<ServiceRecordEntity>(entityName: "ServiceRecordEntity")
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "mileageAtService", ascending: true)]

        do {
            let records = try context.fetch(request)
            guard records.count >= 2 else {
                return vehicle.currentMileage + 5000
            }

            var intervals: [Double] = []
            for index in 1..<records.count {
                let interval = records[index].mileageAtService - records[index - 1].mileageAtService
                if interval > 0 {
                    intervals.append(interval)
                }
            }

            guard !intervals.isEmpty else {
                return vehicle.currentMileage + 5000
            }

            let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
            let lastServiceMileage = records.last?.mileageAtService ?? vehicle.currentMileage
            return lastServiceMileage + averageInterval
        } catch {
            return vehicle.currentMileage + 5000
        }
    }

    /// Returns a service status label based on predicted service due date.
    func serviceStatus(for vehicle: VehicleEntity) -> String {
        let remainingMileage = predictedNextServiceMileage(for: vehicle) - vehicle.currentMileage
        let assumedDailyMileage = 15.0
        let days = Int((remainingMileage / assumedDailyMileage).rounded(.down))

        if days < 0 {
            return "Overdue"
        }

        if days <= 30 {
            return "Due Soon"
        }

        return "Active"
    }

    /// Returns a 0...1 progress value for service-cycle completion.
    func serviceProgress(for vehicle: VehicleEntity) -> Double {
        let nextServiceMileage = predictedNextServiceMileage(for: vehicle)
        let baseMileage = max(nextServiceMileage - 5000, 0)
        let denominator = max(nextServiceMileage - baseMileage, 1)
        let covered = vehicle.currentMileage - baseMileage
        return min(max(covered / denominator, 0), 1)
    }

    // MARK: - Private Helpers
    private func startVehicleListener(fleetId: String, vehicleId: String, driverId: String) {
        vehicleListener?.remove()
        vehicleListener = nil

        guard !fleetId.isEmpty, !vehicleId.isEmpty else {
            return
        }

        vehicleListener = firestoreService.listenToVehicle(
            fleetId: fleetId,
            vehicleId: vehicleId
        ) { [weak self] data in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.applyVehicleSnapshot(data: data, vehicleId: vehicleId)
                self.loadAssignedVehicleFromCoreData(vehicleId: vehicleId)
                self.loadTodayStats(vehicleId: vehicleId, driverId: driverId)
            }
        }
    }

    private func loadAssignedVehicleFromCoreData(vehicleId: String) {
        let normalizedVehicleId = vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: normalizedVehicleId) else {
            assignedVehicle = nil
            return
        }

        let request = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        assignedVehicle = try? context.fetch(request).first
    }

    private func loadTodayStats(vehicleId: String, driverId: String) {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()

        let vehicleUUID = UUID(uuidString: vehicleId)

        let tripRequest = NSFetchRequest<TripLogEntity>(entityName: "TripLogEntity")
        if let vehicleUUID {
            tripRequest.predicate = NSPredicate(
                format: "date >= %@ AND date < %@ AND vehicleId == %@",
                startOfDay as NSDate,
                endOfDay as NSDate,
                vehicleUUID as CVarArg
            )
        } else {
            tripRequest.predicate = NSPredicate(
                format: "date >= %@ AND date < %@",
                startOfDay as NSDate,
                endOfDay as NSDate
            )
        }

        let tripsToday = (try? context.fetch(tripRequest)) ?? []
        todayTrips = tripsToday.count
        todayKmDriven = tripsToday.reduce(0) { $0 + $1.distanceKm }

        let fuelRequest = NSFetchRequest<FuelLogEntity>(entityName: "FuelLogEntity")
        if let vehicleUUID {
            fuelRequest.predicate = NSPredicate(
                format: "date >= %@ AND date < %@ AND vehicleId == %@",
                startOfDay as NSDate,
                endOfDay as NSDate,
                vehicleUUID as CVarArg
            )
        } else {
            fuelRequest.predicate = NSPredicate(
                format: "date >= %@ AND date < %@",
                startOfDay as NSDate,
                endOfDay as NSDate
            )
        }

        todayFuelLogs = ((try? context.fetch(fuelRequest)) ?? []).count

        let faultRequest = NSFetchRequest<FaultReportEntity>(entityName: "FaultReportEntity")
        if let vehicleUUID {
            faultRequest.predicate = NSPredicate(
                format: "status != %@ AND (driverId == %@ OR vehicleId == %@)",
                "resolved",
                driverId,
                vehicleUUID as CVarArg
            )
        } else {
            faultRequest.predicate = NSPredicate(
                format: "status != %@ AND driverId == %@",
                "resolved",
                driverId
            )
        }

        openFaults = ((try? context.fetch(faultRequest)) ?? []).count
    }

    private func applyVehicleSnapshot(data: [String: Any], vehicleId: String) {
        guard !data.isEmpty,
              let uuid = UUID(uuidString: vehicleId) else {
            return
        }

        let request = NSFetchRequest<VehicleEntity>(entityName: "VehicleEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)

        let vehicle = (try? context.fetch(request).first) ?? VehicleEntity(context: context)
        vehicle.id = uuid
        vehicle.registration = (data["registration"] as? String ?? "").uppercased()
        vehicle.make = data["make"] as? String ?? ""
        vehicle.model = data["model"] as? String ?? ""
        vehicle.year = Int16(data["year"] as? Int ?? 0)
        vehicle.fuelType = data["fuelType"] as? String ?? ""
        vehicle.currentMileage = data["currentMileage"] as? Double ?? 0
        vehicle.assignedDriverId = data["assignedDriverId"] as? String
        vehicle.createdAt = parseDateValue(data["createdAt"]) ?? vehicle.createdAt ?? Date()
        vehicle.insuranceExpiry = parseDateValue(data["insuranceExpiry"])
        vehicle.licenceExpiry = parseDateValue(data["licenceExpiry"])

        try? context.save()
    }

    private func parseDateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }

        if let date = value as? Date {
            return date
        }

        return nil
    }
}
