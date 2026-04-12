//
//  FuelLogView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Fuel Log View
struct FuelLogView: View {
    let vehicle: VehicleEntity

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var logs: [FuelLogEntity] = []
    @State private var showAddSheet = false
    @State private var errorText = ""

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
        .onAppear(perform: loadLogs)
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

        do {
            logs = try context.fetch(request)
        } catch {
            logs = []
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

    private let firestoreService = FirestoreService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("FILL-UP DETAILS") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    TextField("Mileage (km)", text: $mileage)
                        .keyboardType(.decimalPad)

                    TextField("Litres", text: $litres)
                        .keyboardType(.decimalPad)

                    TextField("Total Cost (LKR)", text: $totalCost)
                        .keyboardType(.decimalPad)
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
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(isSaving)
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        errorText = ""

        guard let vehicleId = vehicle.id else {
            errorText = "Vehicle ID is missing."
            return
        }

        guard let mileageValue = Double(mileage.replacingOccurrences(of: ",", with: "")),
              let litresValue = Double(litres.replacingOccurrences(of: ",", with: "")),
              let totalValue = Double(totalCost.replacingOccurrences(of: ",", with: "")),
              litresValue > 0 else {
            errorText = "Please enter valid numeric values."
            return
        }

        let previousMileage = latestFuelLogMileage(for: vehicleId)
        let distance = max(0, mileageValue - previousMileage)
        let efficiency = distance > 0 ? distance / litresValue : 0
        let logId = UUID()

        isSaving = true

        do {
            let payload: [String: Any] = [
                "id": logId.uuidString,
                "vehicleId": vehicleId.uuidString,
                "date": date,
                "mileage": mileageValue,
                "litres": litresValue,
                "totalCostLKR": totalValue,
                "costPerLitre": totalValue / litresValue,
                "kmPerLitre": efficiency
            ]

            try await firestoreService.saveFuelLog(
                payload,
                fleetId: authViewModel.fleetId,
                logId: logId.uuidString
            )
        } catch {
            errorText = "Cloud sync failed for fuel log."
            isSaving = false
            return
        }

        let log = FuelLogEntity(context: context)
        log.id = logId
        log.vehicleId = vehicleId
        log.date = date
        log.mileage = mileageValue
        log.litres = litresValue
        log.totalCostLKR = totalValue
        log.costPerLitre = totalValue / litresValue
        log.kmPerLitre = efficiency

        vehicle.currentMileage = max(vehicle.currentMileage, mileageValue)

        do {
            try context.save()
            onSaved()
            isSaving = false
            dismiss()
        } catch {
            errorText = "Could not save fuel log."
            isSaving = false
        }
    }

    private func latestFuelLogMileage(for vehicleId: UUID) -> Double {
        let request = FuelLogEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        return (try? context.fetch(request).first?.mileage) ?? vehicle.currentMileage
    }
}
