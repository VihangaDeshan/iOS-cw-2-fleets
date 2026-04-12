//
//  AddDriverView.swift
//  FleetIQ
//
//  Created by GitHub Copilot on 2026-04-12.
//

import SwiftUI
import CoreData

// MARK: - Add Driver View
struct AddDriverView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var fleetViewModel: FleetViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var selectedVehicleId: UUID?
    @State private var errorText = ""
    @State private var isSaving = false

    private let firestoreService = FirestoreService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("DRIVER DETAILS") {
                    TextField("Full Name", text: $name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section("ASSIGN VEHICLE (OPTIONAL)") {
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
                            .font(.subheadline)
                            .foregroundColor(.statusOverdue)
                    }
                }
            }
            .navigationTitle("Add Driver")
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

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedName.isEmpty else {
            errorText = "Driver name is required."
            return
        }

        guard !normalizedEmail.isEmpty else {
            errorText = "Driver email is required."
            return
        }

        let driverId = UUID()
        isSaving = true

        do {
            let payload: [String: Any] = [
                "id": driverId.uuidString,
                "name": normalizedName,
                "email": normalizedEmail,
                "phone": normalizedPhone,
                "assignedVehicleId": selectedVehicleId?.uuidString ?? ""
            ]

            try await firestoreService.saveDriver(
                payload,
                fleetId: authViewModel.fleetId,
                driverId: driverId.uuidString
            )

            if let selectedVehicleId,
               let vehicle = fleetViewModel.vehicles.first(where: { $0.id == selectedVehicleId }) {
                try await firestoreService.updateVehicle(
                    fleetId: authViewModel.fleetId,
                    vehicleId: selectedVehicleId.uuidString,
                    data: ["assignedDriverId": normalizedName]
                )
                vehicle.assignedDriverId = normalizedName
            }

            let driver = DriverEntity(context: context)
            driver.id = driverId
            driver.firestoreId = driverId.uuidString
            driver.name = normalizedName
            driver.email = normalizedEmail
            driver.phone = normalizedPhone
            driver.assignedVehicleId = selectedVehicleId

            try context.save()
            isSaving = false
            dismiss()
        } catch {
            errorText = "Could not sync driver to cloud."
            isSaving = false
        }
    }
}
