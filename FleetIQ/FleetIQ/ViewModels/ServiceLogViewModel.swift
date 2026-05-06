//
//  ServiceLogViewModel.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import Combine
import CoreData
import FirebaseFirestore

// MARK: - Service Log View Model
@MainActor
final class ServiceLogViewModel: ObservableObject {

    // MARK: - Published
    @Published var records: [ServiceRecordEntity] = []
    @Published var isLoading = false
    @Published var errorMessage = ""

    // MARK: - Private Properties
    private let context = PersistenceController.shared.viewContext
    private let firestoreService = FirestoreService.shared

    // MARK: - Load

    /// Loads all service records for a vehicle from CoreData.
    /// - Parameter vehicleId: Vehicle UUID used for filtering records.
    func loadRecords(for vehicleId: UUID) {
        isLoading = true
        errorMessage = ""

        let request = ServiceRecordEntity.fetchRequest()
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            records = try context.fetch(request)
        } catch {
            errorMessage = "Could not load records."
        }

        isLoading = false
    }

    /// Fetches service records for a vehicle from Firestore and upserts into CoreData.
    /// Call this alongside loadRecords to restore data after a fresh install.
    func syncRecords(vehicleId: UUID, fleetId: String) async {
        let normalizedFleetId = fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else { return }

        guard let docs = try? await firestoreService.fetchServiceRecords(
            fleetId: normalizedFleetId,
            vehicleId: vehicleId.uuidString),
              !docs.isEmpty else { return }

        for doc in docs {
            let data = doc.data()
            guard let idStr = data["id"] as? String,
                  let recordUUID = UUID(uuidString: idStr) else { continue }

            let request = ServiceRecordEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", recordUUID as CVarArg)
            request.fetchLimit = 1

            let entity = (try? context.fetch(request).first)
                ?? ServiceRecordEntity(context: context)
            entity.id = recordUUID
            entity.vehicleId = vehicleId

            if let ts = data["date"] as? Timestamp {
                entity.date = ts.dateValue()
            }
            entity.mileageAtService = (data["mileageAtService"] as? Double) ?? 0
            entity.garageName = data["garageName"] as? String ?? ""
            entity.serviceType = data["serviceType"] as? String ?? ""
            entity.costLKR = (data["costLKR"] as? Double) ?? 0
            entity.notes = data["notes"] as? String ?? ""
        }

        try? context.save()
        loadRecords(for: vehicleId)
    }

    // MARK: - Add Record

    /// Saves a new service record to CoreData and Firestore.
    /// - Parameters:
    ///   - vehicleId: Vehicle UUID the record belongs to.
    ///   - date: Service date.
    ///   - mileage: Odometer reading at service time.
    ///   - garage: Garage or workshop name.
    ///   - serviceType: Service type text.
    ///   - cost: Service cost in LKR.
    ///   - notes: Optional notes.
    ///   - fleetId: Fleet identifier for cloud sync path.
    func addRecord(
        vehicleId: UUID,
        date: Date,
        mileage: Double,
        garage: String,
        serviceType: String,
        cost: Double,
        notes: String,
        fleetId: String
    ) async {
        errorMessage = ""

        let recordId = UUID()

        let data: [String: Any] = [
            "id": recordId.uuidString,
            "vehicleId": vehicleId.uuidString,
            "date": Timestamp(date: date),
            "mileageAtService": mileage,
            "garageName": garage,
            "serviceType": serviceType,
            "costLKR": cost,
            "notes": notes
        ]

        do {
            try await firestoreService.saveServiceRecord(
                data,
                fleetId: fleetId,
                recordId: recordId.uuidString
            )
        } catch {
            errorMessage = "Cloud sync failed. Record not saved locally."
            return
        }

        let record = ServiceRecordEntity(context: context)
        record.id = recordId
        record.vehicleId = vehicleId
        record.date = date
        record.mileageAtService = mileage
        record.garageName = garage
        record.serviceType = serviceType
        record.costLKR = cost
        record.notes = notes

        do {
            try context.save()
        } catch {
            errorMessage = "Failed to save locally."
            return
        }

        let avgInterval = averageServiceIntervalKm()
        let predictedDate = Calendar.current.date(
            byAdding: .day,
            value: Int(avgInterval / 80),
            to: Date()) ?? Date()
        NotificationService.shared.scheduleServiceDue(
            vehicleRegistration: vehicleRegistrationForId(vehicleId),
            predictedDate: predictedDate,
            vehicleId: vehicleId)

        loadRecords(for: vehicleId)
    }

    // MARK: - Delete

    /// Deletes a service record from CoreData and Firestore.
    /// - Parameters:
    ///   - record: Record object to remove.
    ///   - fleetId: Fleet identifier used for cloud delete.
    func deleteRecord(
        _ record: ServiceRecordEntity,
        fleetId: String
    ) async {
        errorMessage = ""

        let recordId = record.id?.uuidString ?? ""
        let vehicleId = record.vehicleId

        context.delete(record)

        do {
            try context.save()

            if !recordId.isEmpty {
                try await firestoreService.deleteServiceRecord(
                    fleetId: fleetId,
                    recordId: recordId
                )
            }
        } catch {
            errorMessage = "Delete failed."
        }

        if let vehicleId {
            loadRecords(for: vehicleId)
        }
    }

    // MARK: - Grouping

    /// Groups service records by year for sectioned list display.
    /// - Returns: Year-sorted tuples containing records per year.
    func recordsByYear() -> [(year: Int, records: [ServiceRecordEntity])] {
        let grouped = Dictionary(grouping: records) { record -> Int in
            Calendar.current.component(.year, from: record.date ?? Date())
        }

        return grouped.keys.sorted(by: >).map { year in
            (
                year: year,
                records: grouped[year]!.sorted {
                    ($0.date ?? Date()) > ($1.date ?? Date())
                }
            )
        }
    }

    // MARK: - Smart Scheduler

    /// Calculates average service interval in kilometers.
    /// - Returns: Average interval or 5000 when insufficient history exists.
    func averageServiceIntervalKm() -> Double {
        let sorted = records.sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }
        guard sorted.count >= 2 else {
            return 5000
        }

        var intervals: [Double] = []

        for index in 1..<sorted.count {
            let diff = sorted[index].mileageAtService - sorted[index - 1].mileageAtService
            if diff > 0 {
                intervals.append(diff)
            }
        }

        guard !intervals.isEmpty else {
            return 5000
        }

        return intervals.reduce(0, +) / Double(intervals.count)
    }

    /// Calculates total spent amount from all loaded records.
    var totalCostLKR: Double {
        records.reduce(0) { $0 + $1.costLKR }
    }

    private func vehicleRegistrationForId(_ id: UUID) -> String {
        let request = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first?.registration ?? "Vehicle"
    }
}
