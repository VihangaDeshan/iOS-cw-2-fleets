//
//  FuelLogView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData
import FirebaseFirestore

// MARK: - Fuel Log View
struct FuelLogView: View {
    let vehicle: VehicleEntity

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var logs: [FuelLogEntity] = []
    @State private var showAddSheet = false
    @State private var errorText = ""
    @State private var fuelListener: ListenerRegistration?
    @State private var fuelLogsBackfilled = false

    private let firestoreService = FirestoreService.shared

    var body: some View {
        List {
            if !errorText.isEmpty {
                Section {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundColor(.statusOverdue)
                }
            }

            if logs.isEmpty {
                ContentUnavailableView(
                    "No Fuel Logs",
                    systemImage: "fuelpump",
                    description: Text("Tap + to add the first fuel fill-up")
                )
            } else {
                ForEach(logs, id: \.id) { log in
                    row(for: log)
                }
                .onDelete { offsets in
                    Task {
                        await deleteLogs(at: offsets)
                    }
                }
            }
        }
        .navigationTitle("Fuel Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add fuel log")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFuelLogSheet(vehicle: vehicle) {
                loadLogs()
            }
            .environmentObject(authViewModel)
            .environment(\.managedObjectContext, context)
        }
        .onAppear {
            loadLogs()
            startFuelListener()
        }
        .onDisappear {
            fuelListener?.remove()
            fuelListener = nil
        }
        .onChange(of: authViewModel.fleetId) { _, newFleetId in
            guard !newFleetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            fuelLogsBackfilled = false
            startFuelListener()
        }
    }

    private func row(for log: FuelLogEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mediumDate(log.date ?? Date()))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("LKR \(String(format: "%.0f", log.totalCostLKR))")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.navyPrimary)
            }

            Text(
                "\(String(format: "%.1f", log.litres)) L  ·  " +
                "\(String(format: "%.0f", log.mileage)) km  ·  " +
                "LKR \(String(format: "%.2f", log.costPerLitre))/L"
            )
            .font(.caption)
            .foregroundColor(.secondary)

            if log.kmPerLitre > 0 {
                Text("Efficiency: \(String(format: "%.2f", log.kmPerLitre)) km/L")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.statusActive)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadLogs() {
        guard let vehicleId = vehicle.id else {
            logs = []
            return
        }

        let request = FuelLogEntity.fetchRequest()
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        let all = (try? context.fetch(request)) ?? []

        // Deduplicate by UUID — CoreData can hold duplicates if sync and backfill race
        var seen = Set<UUID>()
        logs = all.filter { log in
            guard let id = log.id else { return false }
            return seen.insert(id).inserted
        }
    }

    private func deleteLogs(at offsets: IndexSet) async {
        errorText = ""
        var deletedIds: [String] = []

        for offset in offsets {
            if let id = logs[offset].id?.uuidString {
                deletedIds.append(id)
            }
            context.delete(logs[offset])
        }

        do {
            try context.save()
            loadLogs()
        } catch {
            errorText = "Could not delete fuel log locally."
            return
        }

        for id in deletedIds {
            do {
                try await firestoreService.deleteFuelLog(
                    fleetId: authViewModel.fleetId,
                    logId: id
                )
            } catch {
                errorText = "Deleted locally, but cloud delete failed."
            }
        }
    }

    private func startFuelListener() {
        fuelListener?.remove()
        fuelListener = nil

        guard let vehicleId = vehicle.id else {
            return
        }

        let normalizedFleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFleetId.isEmpty else {
            return
        }

        fuelListener = firestoreService.listenToFuelLogs(fleetId: normalizedFleetId) { docs in
            Task { @MainActor in
                syncFuelDocsIntoLocal(docs, vehicleId: vehicleId)
            }
        }
    }

    private func syncFuelDocsIntoLocal(_ docs: [QueryDocumentSnapshot], vehicleId: UUID) {
        let vehicleIdString = vehicleId.uuidString

        let matchingDocs = docs.filter { doc in
            let data = doc.data()
            return (data["vehicleId"] as? String ?? "") == vehicleIdString
        }

        let syncedIDs: Set<UUID> = Set(matchingDocs.compactMap { doc in
            let data = doc.data()
            let rawId = (data["id"] as? String) ?? doc.documentID
            return UUID(uuidString: rawId)
        })

        let request = NSFetchRequest<FuelLogEntity>(entityName: "FuelLogEntity")
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        let existing = (try? context.fetch(request)) ?? []

        // On first sync: upload any local-only records to Firestore before they get deleted
        if !fuelLogsBackfilled {
            fuelLogsBackfilled = true
            let fleetId = authViewModel.fleetId
            let localOnly = existing.filter { item in
                guard let id = item.id else { return false }
                return !syncedIDs.contains(id)
            }
            if !localOnly.isEmpty {
                Task {
                    for item in localOnly {
                        guard let logId = item.id?.uuidString else { continue }
                        let payload: [String: Any] = [
                            "id": logId,
                            "vehicleId": vehicleIdString,
                            "date": Timestamp(date: item.date ?? Date()),
                            "mileage": item.mileage,
                            "litres": item.litres,
                            "totalCostLKR": item.totalCostLKR,
                            "costPerLitre": item.costPerLitre,
                            "kmPerLitre": item.kmPerLitre
                        ]
                        try? await firestoreService.saveFuelLog(payload, fleetId: fleetId, logId: logId)
                    }
                }
                return // listener will fire again once uploads complete
            }
        }

        for item in existing {
            guard let id = item.id else {
                continue
            }

            if !syncedIDs.contains(id) {
                context.delete(item)
            }
        }

        for doc in matchingDocs {
            let data = doc.data()
            let rawId = (data["id"] as? String) ?? doc.documentID
            guard let logUUID = UUID(uuidString: rawId) else {
                continue
            }

            let log = upsertFuelLogEntity(with: logUUID)
            log.id = logUUID
            log.vehicleId = vehicleId
            log.date = parseDateValue(data["date"]) ?? Date()
            log.mileage = numericValue(from: data["mileage"])
            log.litres = numericValue(from: data["litres"])
            log.totalCostLKR = numericValue(from: data["totalCostLKR"])
            log.costPerLitre = numericValue(from: data["costPerLitre"])
            log.kmPerLitre = numericValue(from: data["kmPerLitre"])
        }

        try? context.save()
        loadLogs()
    }

    private func upsertFuelLogEntity(with id: UUID) -> FuelLogEntity {
        let request = NSFetchRequest<FuelLogEntity>(entityName: "FuelLogEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let created = FuelLogEntity(context: context)
        created.id = id
        return created
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

    private func numericValue(from value: Any?) -> Double {
        if let double = value as? Double {
            return double
        }

        if let int = value as? Int {
            return Double(int)
        }

        if let string = value as? String {
            return Double(string) ?? 0
        }

        return 0
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Add Fuel Log Sheet
private struct AddFuelLogSheet: View {
    let vehicle: VehicleEntity
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var date = Date()
    @State private var mileage = ""
    @State private var litres = ""
    @State private var totalCost = ""
    @State private var errorText = ""
    @State private var isSaving = false
    @State private var previousMileage: Double = 0

    private let firestoreService = FirestoreService.shared

    private var enteredMileage: Double? {
        Double(mileage.replacingOccurrences(of: ",", with: ""))
    }

    private var estimatedEfficiency: String? {
        guard previousMileage > 0,
              let m = enteredMileage, m > previousMileage,
              let l = Double(litres.replacingOccurrences(of: ",", with: "")), l > 0
        else { return nil }
        return String(format: "%.2f km/L", (m - previousMileage) / l)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("FILL-UP DETAILS") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Mileage (km)", text: $mileage)
                            .keyboardType(.decimalPad)

                        if previousMileage > 0 {
                            Text("Last logged: \(String(format: "%.0f", previousMileage)) km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let m = enteredMileage, m > 0, m < previousMileage {
                            Text("Must be ≥ last logged \(String(format: "%.0f", previousMileage)) km")
                                .font(.caption)
                                .foregroundStyle(Color.statusOverdue)
                        }
                    }

                    TextField("Litres", text: $litres)
                        .keyboardType(.decimalPad)

                    TextField("Total Cost (LKR)", text: $totalCost)
                        .keyboardType(.decimalPad)
                }

                if let eff = estimatedEfficiency {
                    Section("ESTIMATED EFFICIENCY") {
                        HStack {
                            Label("km / L", systemImage: "gauge.medium")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(eff)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.statusActive)
                        }
                    }
                }

                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .foregroundColor(.statusOverdue)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Add Fuel Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.bold)
                    .disabled(isSaving)
                }
            }
            .disabled(isSaving)
            .onAppear { prefillMileage() }
        }
    }

    private func prefillMileage() {
        guard let vehicleId = vehicle.id else { return }
        let last = latestFuelLogMileage(for: vehicleId)
        previousMileage = last
        if last > 0 {
            mileage = String(format: "%.0f", last)
        }
    }

    private func save() async {
        errorText = ""

        guard let vehicleId = vehicle.id else {
            errorText = "Vehicle ID is missing."
            return
        }

        let fleetId = authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fleetId.isEmpty else {
            errorText = "Fleet ID is missing — cannot save to cloud. Please sign out and back in."
            return
        }

        guard let mileageValue = Double(mileage.replacingOccurrences(of: ",", with: "")),
              let litresValue = Double(litres.replacingOccurrences(of: ",", with: "")),
              let totalValue = Double(totalCost.replacingOccurrences(of: ",", with: "")),
              litresValue > 0 else {
            errorText = "Please enter valid numeric values."
            return
        }

        if previousMileage > 0 && mileageValue < previousMileage {
            errorText = "Odometer reading cannot be less than the last logged \(String(format: "%.0f", previousMileage)) km. Please check your odometer."
            isSaving = false
            return
        }

        let distance = max(0, mileageValue - previousMileage)
        let efficiency = distance > 0 ? distance / litresValue : 0
        let logId = UUID()

        isSaving = true

        let costPerLitre = totalValue / litresValue

        // Sync to Firestore first
        do {
            let payload: [String: Any] = [
                "id": logId.uuidString,
                "vehicleId": vehicleId.uuidString,
                "date": Timestamp(date: date),
                "mileage": mileageValue,
                "litres": litresValue,
                "totalCostLKR": totalValue,
                "costPerLitre": costPerLitre,
                "kmPerLitre": efficiency
            ]

            try await firestoreService.saveFuelLog(
                payload,
                fleetId: fleetId,
                logId: logId.uuidString
            )
        } catch {
            errorText = "Firebase sync failed: \(error.localizedDescription). Please try again."
            isSaving = false
            return
        }

        // Save to CoreData — upsert to guard against listener race creating a duplicate
        let upsertReq = NSFetchRequest<FuelLogEntity>(entityName: "FuelLogEntity")
        upsertReq.fetchLimit = 1
        upsertReq.predicate = NSPredicate(format: "id == %@", logId as CVarArg)
        let log = (try? context.fetch(upsertReq).first) ?? FuelLogEntity(context: context)
        log.id = logId
        log.vehicleId = vehicleId
        log.date = date
        log.mileage = mileageValue
        log.litres = litresValue
        log.totalCostLKR = totalValue
        log.costPerLitre = costPerLitre
        log.kmPerLitre = efficiency

        vehicle.currentMileage = max(vehicle.currentMileage, mileageValue)

        do {
            try context.save()
        } catch {
            errorText = "Could not save fuel log locally."
            isSaving = false
            return
        }

        isSaving = false
        onSaved()
        dismiss()
    }

    private func latestFuelLogMileage(for vehicleId: UUID) -> Double {
        let request = FuelLogEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        return (try? context.fetch(request).first?.mileage) ?? vehicle.currentMileage
    }
}
