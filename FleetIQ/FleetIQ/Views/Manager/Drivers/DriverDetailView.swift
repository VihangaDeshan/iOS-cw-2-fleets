//
//  DriverDetailView.swift
//  FleetIQ
//

import SwiftUI
import CoreData

struct DriverDetailView: View {
    let driver: FleetDriverUser
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var fleetViewModel: FleetViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.managedObjectContext) private var context
    
    @State private var selectedVehicleId: UUID?
    @State private var isSaving = false
    @State private var errorText = ""
    @State private var successText = ""
    private let firestoreService = FirestoreService.shared
    
    var body: some View {
        Form {
            Section("DRIVER INFO") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(driver.name)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Email")
                    Spacer()
                    Text(driver.email)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Phone")
                    Spacer()
                    Text(driver.phone)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("ASSIGNED VEHICLE") {
                Picker("Vehicle", selection: $selectedVehicleId) {
                    Text("Unassigned").tag(Optional<UUID>.none)
                    
                    ForEach(fleetViewModel.vehicles, id: \.id) { vehicle in
                        Text(vehicle.registration ?? "Unknown")
                            .tag(vehicle.id)
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
            
            if !successText.isEmpty {
                Section {
                    Text(successText)
                        .foregroundColor(.statusActive)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle(driver.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let uuid = UUID(uuidString: driver.assignedVehicleId) {
                selectedVehicleId = uuid
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await saveAssignment()
                    }
                }
                .disabled(isSaving)
            }
        }
    }
    
    @MainActor
    private func saveAssignment() async {
        isSaving = true
        errorText = ""
        successText = ""
        
        do {
            let newVehicleId = selectedVehicleId?.uuidString ?? ""
            let oldVehicleId = driver.assignedVehicleId
            
            // 1. Update user document
            try await firestoreService.updateDriverUserAssignment(
                userId: driver.userId,
                vehicleId: newVehicleId
            )
            
            // 2. Update driver document in fleet
            try await firestoreService.updateDriver(
                fleetId: authViewModel.fleetId,
                driverId: driver.userId,
                data: ["assignedVehicleId": newVehicleId]
            )
            
            // 3. Unassign from old vehicle
            if !oldVehicleId.isEmpty && oldVehicleId != newVehicleId {
                try await firestoreService.updateVehicle(
                    fleetId: authViewModel.fleetId,
                    vehicleId: oldVehicleId,
                    data: ["assignedDriverId": ""]
                )
                if let oldVehicle = fleetViewModel.vehicles.first(where: { $0.id?.uuidString == oldVehicleId }) {
                    oldVehicle.assignedDriverId = nil
                }
            }
            
            // 4. Assign to new vehicle
            if !newVehicleId.isEmpty && oldVehicleId != newVehicleId {
                try await firestoreService.updateVehicle(
                    fleetId: authViewModel.fleetId,
                    vehicleId: newVehicleId,
                    data: ["assignedDriverId": driver.userId]
                )
                if let newVehicle = fleetViewModel.vehicles.first(where: { $0.id?.uuidString == newVehicleId }) {
                    newVehicle.assignedDriverId = driver.userId
                }
            }
            
            // 5. Update CoreData
            let request = DriverEntity.fetchRequest()
            request.predicate = NSPredicate(format: "firestoreId == %@", driver.userId)
            if let driverEntity = try? context.fetch(request).first {
                driverEntity.assignedVehicleId = selectedVehicleId
                try? context.save()
            }
            
            successText = "Assignment updated successfully."
            isSaving = false
            
            // Optional delay before dismiss, or just keep it there
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        } catch {
            errorText = "Failed to update assignment."
            isSaving = false
        }
    }
}
