//
//  EditVehicleView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Edit Vehicle View
struct EditVehicleView: View {
    // MARK: - Environment
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: VehicleDetailViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    // MARK: - Form State
    @State private var registration: String
    @State private var make: String
    @State private var model: String
    @State private var year: Int16
    @State private var fuelType: String
    @State private var currentMileage: String
    @State private var insuranceExpiry: Date
    @State private var licenceExpiry: Date
    @State private var hasInsuranceDate: Bool
    @State private var hasLicenceDate: Bool
    @State private var isSaving = false
    @State private var errorText = ""

    // MARK: - Constants
    let fuelTypes = ["Diesel", "Petrol", "Hybrid", "Electric", "CNG"]
    let years = Array(2000...2026).map { Int16($0) }.reversed()

    // MARK: - Initializer

    /// Builds prefilled form state from the selected vehicle.
    /// - Parameter viewModel: Vehicle detail view model with current vehicle values.
    init(viewModel: VehicleDetailViewModel) {
        self.viewModel = viewModel

        let vehicle = viewModel.vehicle
        _registration = State(initialValue: vehicle.registration ?? "")
        _make = State(initialValue: vehicle.make ?? "")
        _model = State(initialValue: vehicle.model ?? "")
        _year = State(initialValue: vehicle.year)
        _fuelType = State(initialValue: vehicle.fuelType ?? "Diesel")
        _currentMileage = State(initialValue: String(format: "%.0f", vehicle.currentMileage))
        _insuranceExpiry = State(initialValue: vehicle.insuranceExpiry ?? Date())
        _licenceExpiry = State(initialValue: vehicle.licenceExpiry ?? Date())
        _hasInsuranceDate = State(initialValue: vehicle.insuranceExpiry != nil)
        _hasLicenceDate = State(initialValue: vehicle.licenceExpiry != nil)
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                Section("VEHICLE DETAILS") {
                    TextField("Registration Plate", text: $registration)
                        .textInputAutocapitalization(.characters)

                    TextField("Make", text: $make)

                    TextField("Model", text: $model)

                    Picker("Year", selection: $year) {
                        ForEach(years, id: \.self) { item in
                            Text(String(item)).tag(item)
                        }
                    }

                    Picker("Fuel Type", selection: $fuelType) {
                        ForEach(fuelTypes, id: \.self) { item in
                            Text(item).tag(item)
                        }
                    }

                    TextField("Current Mileage (km)", text: $currentMileage)
                        .keyboardType(.decimalPad)
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

                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .foregroundColor(.statusOverdue)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Edit Vehicle")
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

    // MARK: - Save

    /// Validates and saves edited vehicle values via view model update API.
    private func save() async {
        errorText = ""

        let normalizedRegistration = registration
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let normalizedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMileage = currentMileage.replacingOccurrences(of: ",", with: "")

        guard !normalizedRegistration.isEmpty else {
            errorText = "Registration is required."
            return
        }

        guard !normalizedMake.isEmpty else {
            errorText = "Make is required."
            return
        }

        guard !normalizedModel.isEmpty else {
            errorText = "Model is required."
            return
        }

        guard let mileageValue = Double(normalizedMileage) else {
            errorText = "Current mileage must be a valid number."
            return
        }

        isSaving = true

        await viewModel.updateVehicle(
            registration: normalizedRegistration,
            make: normalizedMake,
            model: normalizedModel,
            year: year,
            fuelType: fuelType,
            currentMileage: mileageValue,
            insuranceExpiry: hasInsuranceDate ? insuranceExpiry : nil,
            licenceExpiry: hasLicenceDate ? licenceExpiry : nil,
            fleetId: authViewModel.fleetId
        )

        isSaving = false
        dismiss()
    }
}
