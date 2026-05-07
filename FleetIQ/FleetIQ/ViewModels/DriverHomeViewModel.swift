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
    @Published var todayActivityItems: [DriverActivityItem] = []
    
    @Published var expiredDocsSummary: [String] = []
    @Published var showExpiredDocsAlert: Bool = false
    private var hasCheckedExpiredDocs = false

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

    /// Predicts next full service mileage from historical service intervals.
    func predictedNextServiceMileage(for vehicle: VehicleEntity) -> Double {
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
    
    /// Calculates average daily kilometers based on vehicle history.
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

    /// Returns days remaining until predicted service based on the dynamic true daily km.
    func daysUntilService(for vehicle: VehicleEntity) -> Int {
        let remainingMileage = predictedNextServiceMileage(for: vehicle) - vehicle.currentMileage
        let dailyKm = averageDailyKm(for: vehicle)
        return Int((remainingMileage / max(1, dailyKm)).rounded(.down))
    }

    /// Returns a service status label based on predicted service due date.
    func serviceStatus(for vehicle: VehicleEntity) -> String {
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
                self.triggerNotifications()
                self.checkAndAlertExpiredDocuments()
            }
        }
    }

    private func triggerNotifications() {
        guard let vehicle = assignedVehicle else { return }
        let reg = vehicle.registration ?? "Your Vehicle"
        
        if let ins = vehicle.insuranceExpiry {
            NotificationService.shared.rescheduleExpiryIfNeeded(
                vehicleRegistration: reg,
                documentType: "Insurance",
                expiryDate: ins,
                vehicleId: vehicle.id ?? UUID()
            )
        }
        
        if let lic = vehicle.licenceExpiry {
            NotificationService.shared.rescheduleExpiryIfNeeded(
                vehicleRegistration: reg,
                documentType: "Revenue Licence",
                expiryDate: lic,
                vehicleId: vehicle.id ?? UUID()
            )
        }
    }

    private func checkAndAlertExpiredDocuments() {
        guard let vehicle = assignedVehicle, !hasCheckedExpiredDocs else { return }
        hasCheckedExpiredDocs = true
        var summary: [String] = []
        
        if let ins = vehicle.insuranceExpiry {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: ins)).day ?? 0
            if days <= 30 {
                summary.append("Insurance (\(days < 0 ? "Expired" : "Expires in \(days) days"))")
            }
        }
        
        if let lic = vehicle.licenceExpiry {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: lic)).day ?? 0
            if days <= 30 {
                summary.append("Revenue Licence (\(days < 0 ? "Expired" : "Expires in \(days) days"))")
            }
        }
        
        if !summary.isEmpty {
            self.expiredDocsSummary = summary
            self.showExpiredDocsAlert = true
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

        let tripsToday: [TripLogEntity]
        let fuelToday: [FuelLogEntity]

        if let vehicleUUID {
            let tripRequest = NSFetchRequest<TripLogEntity>(entityName: "TripLogEntity")
            tripRequest.predicate = NSPredicate(
                format: "date >= %@ AND date < %@ AND vehicleId == %@",
                startOfDay as NSDate,
                endOfDay as NSDate,
                vehicleUUID as CVarArg
            )
            tripsToday = (try? context.fetch(tripRequest)) ?? []

            let fuelRequest = NSFetchRequest<FuelLogEntity>(entityName: "FuelLogEntity")
            fuelRequest.predicate = NSPredicate(
                format: "date >= %@ AND date < %@ AND vehicleId == %@",
                startOfDay as NSDate,
                endOfDay as NSDate,
                vehicleUUID as CVarArg
            )
            fuelToday = (try? context.fetch(fuelRequest)) ?? []
        } else {
            tripsToday = []
            fuelToday = []
        }

        todayTrips = tripsToday.count
        todayKmDriven = tripsToday.reduce(0) { $0 + $1.distanceKm }

        var seenFuelIds = Set<UUID>()
        let uniqueFuelToday = fuelToday.filter { log in
            guard let id = log.id else { return false }
            return seenFuelIds.insert(id).inserted
        }
        todayFuelLogs = uniqueFuelToday.count

        buildTodayActivityItems(trips: tripsToday, fuelLogs: uniqueFuelToday)

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

    private func buildTodayActivityItems(trips: [TripLogEntity], fuelLogs: [FuelLogEntity]) {
        let tripItems: [DriverActivityItem] = trips.map { trip in
            DriverActivityItem(
                kind: .trip,
                title: trip.purpose?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (trip.purpose ?? "Trip")
                    : "Trip Logged",
                subtitle: "\(String(format: "%.1f", trip.distanceKm)) km  •  \(trip.destination ?? "-")",
                timestamp: trip.date ?? .distantPast
            )
        }

        let fuelItems: [DriverActivityItem] = fuelLogs.map { fuel in
            DriverActivityItem(
                kind: .fuel,
                title: "Fuel Logged",
                subtitle: "\(String(format: "%.1f", fuel.litres)) L  •  LKR \(String(format: "%.0f", fuel.totalCostLKR))",
                timestamp: fuel.date ?? .distantPast
            )
        }

        todayActivityItems = (tripItems + fuelItems)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(6)
            .map { $0 }
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

struct DriverActivityItem: Identifiable {
    enum ActivityKind {
        case trip
        case fuel
    }

    let id = UUID()
    let kind: ActivityKind
    let title: String
    let subtitle: String
    let timestamp: Date
}
