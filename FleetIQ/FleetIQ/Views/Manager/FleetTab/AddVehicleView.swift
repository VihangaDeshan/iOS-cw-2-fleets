//
//  AddVehicleView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Add Vehicle View
struct AddVehicleView: View {
    // MARK: - Environment
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var fleetViewModel: FleetViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    // MARK: - Form State
    @State private var registration = ""
    @State private var make = ""
    @State private var model = ""
    @State private var year: Int16 = 2020
    @State private var fuelType = "Diesel"
    @State private var currentMileage = ""
    @State private var insuranceExpiry = Date()
    @State private var licenceExpiry = Date()
    @State private var hasInsuranceDate = false
    @State private var hasLicenceDate = false
    @State private var isSaving = false

    // MARK: - Constants
    let fuelTypes = ["Diesel", "Petrol", "Hybrid", "Electric", "CNG"]
    let years = Array(2000...2026).reversed()

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                Section("VEHICLE DETAILS") {
                    TextField("Registration Plate *", text: $registration)
                        .textInputAutocapitalization(.characters)
                        .accessibilityLabel("Registration plate number")

                    TextField("Make *  e.g. Toyota", text: $make)
                        .accessibilityLabel("Vehicle make")

                    TextField("Model *  e.g. KDH Van", text: $model)
                        .accessibilityLabel("Vehicle model")

                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { y in
                            Text(String(y)).tag(Int16(y))
                        }
                    }

                    Picker("Fuel Type", selection: $fuelType) {
                        ForEach(fuelTypes, id: \.self) { t in
                            Text(t).tag(t)
                        }
                    }

                    TextField("Current Mileage (km) *", text: $currentMileage)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Current mileage in kilometres")
                }

                Section("DOCUMENT EXPIRY DATES") {
                    Toggle("Insurance Certificate", isOn: $hasInsuranceDate)

                    if hasInsuranceDate {
                        DatePicker(
                            "Insurance Expiry",
                            selection: $insuranceExpiry,
                            displayedComponents: .date
                        )
                    }

                    Toggle("Revenue Licence", isOn: $hasLicenceDate)

                    if hasLicenceDate {
                        DatePicker(
                            "Licence Expiry",
                            selection: $licenceExpiry,
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle("Add Vehicle")
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
                    .disabled(
                        isSaving ||
                        registration.isEmpty ||
                        make.isEmpty ||
                        model.isEmpty ||
                        currentMileage.isEmpty
                    )
                    .fontWeight(.bold)
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView("Saving...")
                        .padding()
                        .background(Material.regular)
                        .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - Save Action

    /// Validates form and calls FleetViewModel to save a vehicle.
    private func save() async {
        isSaving = true

        await fleetViewModel.addVehicle(
            registration: registration.uppercased(),
            make: make,
            model: model,
            year: year,
            fuelType: fuelType,
            currentMileage: Double(currentMileage) ?? 0,
            insuranceExpiry: hasInsuranceDate ? insuranceExpiry : nil,
            licenceExpiry: hasLicenceDate ? licenceExpiry : nil,
            fleetId: authViewModel.fleetId
        )

        isSaving = false
        dismiss()
    }
}

#Preview {
    AddVehicleView()
        .environmentObject(FleetViewModel())
        .environmentObject(AuthViewModel())
}
