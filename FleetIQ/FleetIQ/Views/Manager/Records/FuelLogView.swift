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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundColor(.statusOverdue)
                        .padding(.horizontal, 16)
                }

                if logs.isEmpty {
                    ContentUnavailableView(
                        "No Fuel Logs",
                        systemImage: "fuelpump.fill",
                        description: Text("Tap the + button to add your first fuel entry.")
                    )
                    .padding(.top, 60)
                } else {
                    heroSection

                    VStack(alignment: .leading, spacing: 12) {
                        Text("FUEL LOG — \(currentMonthName())")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)
                            .padding(.horizontal, 4)

                        LazyVStack(spacing: 12) {
                            ForEach(logs, id: \.id) { log in
                                row(for: log)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.systemGroupedBg)
        .navigationTitle("Fuel Log")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.navyPrimary)
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

    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FUEL EFFICIENCY")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white.opacity(0.8))
                        .tracking(1.5)

                    Text(vehicle.registration ?? "UNKNOWN")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "fuelpump.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", averageEfficiency))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("KM/L AVERAGE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedCostThisMonth)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("SPENT THIS MONTH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                }
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

    private var averageEfficiency: Double {
        let validLogs = logs.filter { $0.kmPerLitre > 0 }
        guard !validLogs.isEmpty else { return 0 }
        let total = validLogs.reduce(0) { $0 + $1.kmPerLitre }
        return total / Double(validLogs.count)
    }

    private var costThisMonth: Double {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        
        let monthLogs = logs.filter {
            guard let d = $0.date else { return false }
            return calendar.component(.month, from: d) == currentMonth &&
                   calendar.component(.year, from: d) == currentYear
        }
        return monthLogs.reduce(0) { $0 + $1.totalCostLKR }
    }
    
    private var formattedCostThisMonth: String {
        if costThisMonth >= 1000 {
            return String(format: "%.0fK", costThisMonth / 1000)
        } else {
            return String(format: "%.0f", costThisMonth)
        }
    }
    
    private func currentMonthName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date()).uppercased()
    }

    // MARK: - Row View
    
    private func row(for log: FuelLogEntity) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.navyPrimary.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "fuelpump.fill")
                    .foregroundColor(.navyPrimary)
                    .font(.system(size: 18))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(mediumDate(log.date ?? Date()))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("LKR \(String(format: "%.0f", log.totalCostLKR))")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.navyPrimary)
                }
                
                HStack(spacing: 6) {
                    Text("\(String(format: "%.1f", log.litres))L · \(String(format: "%.0f", log.mileage)) km")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if log.kmPerLitre > 0 {
                        efficiencyPill(for: log.kmPerLitre)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
    
    @ViewBuilder
    private func efficiencyPill(for eff: Double) -> some View {
        let isGood = eff >= averageEfficiency
        let color = isGood ? Color.statusActive : Color.statusDueSoon
        let icon = isGood ? "arrow.up" : "arrow.down"
        
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text("\(String(format: "%.1f", eff)) km/L")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
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
                return 
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
    @State private var manualEfficiency = ""

    private let firestoreService = FirestoreService.shared

    private var enteredMileage: Double? {
        Double(mileage.replacingOccurrences(of: ",", with: ""))
    }

    private func updateEstimatedEfficiency() {
        guard previousMileage > 0,
              let m = enteredMileage, m > previousMileage,
              let l = Double(litres.replacingOccurrences(of: ",", with: "")), l > 0
        else { return }
        manualEfficiency = String(format: "%.2f", (m - previousMileage) / l)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LOG FUEL FILL-UP")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        
                        Text(vehicle.registration ?? "Unknown Vehicle")
                            .font(.title2.weight(.bold))
                    }
                    .padding(.horizontal, 4)

                    // Form Container
                    VStack(spacing: 20) {
                        // Date Picker
                        HStack {
                            Label("Date", systemImage: "calendar")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // Mileage Input
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Odometer (km)", systemImage: "gauge.with.needle")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                TextField("Current km", text: $mileage)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.subheadline.weight(.bold))
                            }

                            if previousMileage > 0 {
                                HStack {
                                    Text("Previous logged:")
                                    Spacer()
                                    Text("\(String(format: "%.0f", previousMileage)) km")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if let m = enteredMileage, m > 0, m < previousMileage {
                                Text("Odometer must be ≥ \(String(format: "%.0f", previousMileage)) km")
                                    .font(.caption)
                                    .foregroundStyle(Color.statusOverdue)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // Volume and Cost
                        VStack(spacing: 12) {
                            HStack {
                                Label("Litres", systemImage: "drop.fill")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                TextField("0.00", text: $litres)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.subheadline.weight(.bold))
                            }
                            
                            Divider()

                            HStack {
                                Label("Total Cost (LKR)", systemImage: "banknote.fill")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                TextField("0.00", text: $totalCost)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // Efficiency Result
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Efficiency (km/L)", systemImage: "leaf.fill")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                TextField("Calculated", text: $manualEfficiency)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.statusActive)
                            }
                        }
                        .padding()
                        .background(Color.statusActive.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .foregroundColor(.statusOverdue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 4)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save Fuel Log")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.navyPrimary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isSaving)
                }
                .padding(16)
            }
            .background(Color.systemGroupedBg)
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { prefillMileage() }
            .onChange(of: mileage) { _, _ in updateEstimatedEfficiency() }
            .onChange(of: litres) { _, _ in updateEstimatedEfficiency() }
        }
    }

    private func prefillMileage() {
        guard let vehicleId = vehicle.id else { return }
        
        let lastFuel = latestFuelLogMileage(for: vehicleId)
        previousMileage = lastFuel
        
        let current = vehicle.currentMileage
        if current > 0 {
            mileage = String(format: "%.0f", current)
        } else if lastFuel > 0 {
            mileage = String(format: "%.0f", lastFuel)
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
        var efficiency = distance > 0 ? distance / litresValue : 0
        
        if let manualEff = Double(manualEfficiency.replacingOccurrences(of: ",", with: "")), manualEff > 0 {
            efficiency = manualEff
        }
        
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
