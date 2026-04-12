//
//  AddVehicleView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import PhotosUI

// MARK: - Add Vehicle View
struct AddVehicleView: View {
    // MARK: - OCR Scan Type
    private enum ScanType {
        case registration
        case insurance
        case licence
        case emission
    }

    // MARK: - Environment
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var fleetViewModel: FleetViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    // MARK: - Mode
    @State private var selectedMode = 0

    // MARK: - Form State
    @State private var registration = ""
    @State private var make = ""
    @State private var model = ""
    @State private var year: Int16 = 2020
    @State private var fuelType = "Diesel"
    @State private var currentMileage = ""
    @State private var insuranceExpiry = Date()
    @State private var licenceExpiry = Date()
    @State private var emissionExpiry = Date()
    @State private var hasInsuranceDate = false
    @State private var hasLicenceDate = false
    @State private var hasEmissionDate = false
    @State private var isSaving = false

    // MARK: - Validation State
    @State private var registrationError = ""
    @State private var makeError = ""
    @State private var modelError = ""
    @State private var mileageError = ""
    @State private var emissionError = ""

    // MARK: - OCR State
    @State private var registrationItem: PhotosPickerItem?
    @State private var insuranceItem: PhotosPickerItem?
    @State private var licenceItem: PhotosPickerItem?
    @State private var emissionItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var scanMessage = ""
    @State private var registrationVerified = false
    @State private var insuranceVerified = false
    @State private var licenceVerified = false
    @State private var emissionVerified = false

    // MARK: - Constants
    let fuelTypes = ["Diesel", "Petrol", "Hybrid", "Electric", "CNG"]
    let years = Array(2000...2026).reversed()

    // MARK: - Computed

    /// Returns true when selected fuel type requires an emission test.
    private var requiresEmissionTest: Bool {
        let normalized = fuelType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized != "hybrid" && normalized != "electric"
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Entry Mode", selection: $selectedMode) {
                        Text("Manual Filling").tag(0)
                        Text("Auto filling").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedMode == 1 {
                    Section("VERIFIED STEPS") {
                        verifiedStepRow(
                            title: "Registration Details",
                            subtitle: registrationVerified ? "Verified via OCR" : "Pending scan",
                            isVerified: registrationVerified,
                            tint: .statusActive
                        ) {
                            PhotosPicker(selection: $registrationItem, matching: .images) {
                                stepActionLabel(registrationVerified ? "Rescan" : "Scan")
                            }
                        }

                        verifiedStepRow(
                            title: "Revenue Licence",
                            subtitle: licenceVerified ? licenceExpiryText() : "Pending scan",
                            isVerified: licenceVerified,
                            tint: .statusDueSoon
                        ) {
                            PhotosPicker(selection: $licenceItem, matching: .images) {
                                stepActionLabel(licenceVerified ? "Rescan" : "Scan")
                            }
                        }

                        verifiedStepRow(
                            title: "Insurance Details",
                            subtitle: insuranceVerified ? insuranceExpiryText() : "Pending scan",
                            isVerified: insuranceVerified,
                            tint: .statusActive
                        ) {
                            PhotosPicker(selection: $insuranceItem, matching: .images) {
                                stepActionLabel(insuranceVerified ? "Rescan" : "Scan")
                            }
                        }

                        if requiresEmissionTest {
                            verifiedStepRow(
                                title: "Emission Test",
                                subtitle: emissionVerified ? emissionExpiryText() : "Pending scan",
                                isVerified: emissionVerified,
                                tint: .statusDueSoon
                            ) {
                                PhotosPicker(selection: $emissionItem, matching: .images) {
                                    stepActionLabel(emissionVerified ? "Rescan" : "Scan")
                                }
                            }
                        }

                        if isScanning {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Extracting details from image...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if !scanMessage.isEmpty {
                            Text(scanMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("VEHICLE DETAILS") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Registration Plate *", text: $registration)
                            .textInputAutocapitalization(.characters)
                            .accessibilityLabel("Registration plate number")

                        if !registrationError.isEmpty {
                            Text(registrationError)
                                .font(.caption)
                                .foregroundColor(.statusOverdue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Make *", text: $make)
                            .accessibilityLabel("Vehicle make")

                        if !makeError.isEmpty {
                            Text(makeError)
                                .font(.caption)
                                .foregroundColor(.statusOverdue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Model *", text: $model)
                            .accessibilityLabel("Vehicle model")

                        if !modelError.isEmpty {
                            Text(modelError)
                                .font(.caption)
                                .foregroundColor(.statusOverdue)
                        }
                    }

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

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Current Mileage (km) *", text: $currentMileage)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Current mileage in kilometres")

                        if !mileageError.isEmpty {
                            Text(mileageError)
                                .font(.caption)
                                .foregroundColor(.statusOverdue)
                        }
                    }
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

                    if requiresEmissionTest {
                        Toggle("Emission Test", isOn: $hasEmissionDate)

                        if hasEmissionDate {
                            DatePicker(
                                "Emission Expiry",
                                selection: $emissionExpiry,
                                displayedComponents: .date
                            )
                        }

                        if !emissionError.isEmpty {
                            Text(emissionError)
                                .font(.caption)
                                .foregroundColor(.statusOverdue)
                        }
                    }
                }
            }
            .navigationTitle("Add Vehicle Details")
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
                    .disabled(isSaving)
                    .fontWeight(.bold)
                }
            }
            .onChange(of: registrationItem) { _, item in
                Task {
                    await process(item: item, as: .registration)
                }
            }
            .onChange(of: insuranceItem) { _, item in
                Task {
                    await process(item: item, as: .insurance)
                }
            }
            .onChange(of: licenceItem) { _, item in
                Task {
                    await process(item: item, as: .licence)
                }
            }
            .onChange(of: emissionItem) { _, item in
                Task {
                    await process(item: item, as: .emission)
                }
            }
            .onChange(of: fuelType) { _, _ in
                if !requiresEmissionTest {
                    hasEmissionDate = false
                    emissionVerified = false
                    emissionError = ""
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

    // MARK: - OCR Helpers

    /// Processes a selected photo item for a specific OCR document type.
    /// - Parameters:
    ///   - item: Picked photo item from user selection.
    ///   - type: Vehicle document scan type.
    @MainActor
    private func process(item: PhotosPickerItem?, as type: ScanType) async {
        guard let item else {
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            scanMessage = "Could not load selected image."
            return
        }

        isScanning = true
        scanMessage = ""

        do {
            let ocrType = mapToVehicleOCRType(type)
            let lines = try await VehicleOCRService.shared.recognizeText(in: image)
            let result = VehicleOCRService.shared.extractVehicleData(from: lines, type: ocrType)
            applyOCR(result: result, for: type)
            scanMessage = "OCR extracted \(result.lineCount) text lines. Review fields before saving."
        } catch {
            scanMessage = "OCR failed for this image. Try a clearer photo."
        }

        isScanning = false
    }

    /// Maps internal UI scan type to service document type.
    /// - Parameter type: View scan type.
    /// - Returns: OCR service document type.
    private func mapToVehicleOCRType(_ type: ScanType) -> VehicleOCRDocumentType {
        switch type {
        case .registration:
            return .registration
        case .insurance:
            return .insurance
        case .licence:
            return .licence
        case .emission:
            return .emission
        }
    }

    /// Applies OCR extraction results to view state.
    /// - Parameters:
    ///   - result: Extracted OCR values.
    ///   - type: Scan type that produced this result.
    @MainActor
    private func applyOCR(result: VehicleOCRResult, for type: ScanType) {
        switch type {
        case .registration:
            if let value = result.registration, !value.isEmpty {
                registration = value
                registrationVerified = true
            }
            if let value = result.make, !value.isEmpty {
                make = value
            }
            if let value = result.model, !value.isEmpty {
                model = value
            }
            if let value = result.year {
                year = value
            }
        case .insurance:
            if let expiry = result.insuranceExpiry {
                insuranceExpiry = expiry
                hasInsuranceDate = true
                insuranceVerified = true
            }
        case .licence:
            if let expiry = result.licenceExpiry {
                licenceExpiry = expiry
                hasLicenceDate = true
                licenceVerified = true
            }
        case .emission:
            if let expiry = result.emissionExpiry {
                emissionExpiry = expiry
                hasEmissionDate = true
                emissionVerified = true
            }
        }
    }

    /// Returns formatted insurance expiry subtitle text.
    /// - Returns: User-friendly insurance expiry string.
    private func insuranceExpiryText() -> String {
        "Expires: \(dateString(from: insuranceExpiry))"
    }

    /// Returns formatted licence expiry subtitle text.
    /// - Returns: User-friendly licence expiry string.
    private func licenceExpiryText() -> String {
        "Expires: \(dateString(from: licenceExpiry))"
    }

    /// Returns formatted emission expiry subtitle text.
    /// - Returns: User-friendly emission expiry string.
    private func emissionExpiryText() -> String {
        "Expires: \(dateString(from: emissionExpiry))"
    }

    /// Formats a date using medium style.
    /// - Parameter date: Date value to format.
    /// - Returns: Formatted date string.
    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Validation

    /// Validates required form fields and updates inline field errors.
    /// - Returns: True when all required values are valid.
    private func validateForm() -> Bool {
        registrationError = ""
        makeError = ""
        modelError = ""
        mileageError = ""
        emissionError = ""

        let normalizedRegistration = registration.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedRegistration.isEmpty {
            registrationError = "Registration is required."
        }

        if normalizedMake.isEmpty {
            makeError = "Make is required."
        }

        if normalizedModel.isEmpty {
            modelError = "Model is required."
        }

        let normalizedMileage = currentMileage.replacingOccurrences(of: ",", with: "")
        if Double(normalizedMileage) == nil {
            mileageError = "Enter a valid mileage value."
        }

        if requiresEmissionTest && !hasEmissionDate {
            emissionError = "Emission test expiry is required for non-hybrid/electric vehicles."
        }

        return registrationError.isEmpty &&
            makeError.isEmpty &&
            modelError.isEmpty &&
            mileageError.isEmpty &&
            emissionError.isEmpty
    }

    // MARK: - Save Action

    /// Validates form and calls FleetViewModel to save a vehicle.
    private func save() async {
        guard validateForm() else {
            return
        }

        let normalizedRegistration = registration.uppercased().trimmingCharacters(in: .whitespaces)
        let normalizedMileageText = currentMileage.replacingOccurrences(of: ",", with: "")
        guard let mileageValue = Double(normalizedMileageText) else {
            mileageError = "Enter a valid mileage value."
            return
        }

        isSaving = true

        await fleetViewModel.addVehicle(
            registration: normalizedRegistration,
            make: make,
            model: model,
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

    // MARK: - Reusable Rows

    /// Builds a verified-step row that mirrors OCR checklist status.
    /// - Parameters:
    ///   - title: Step title text.
    ///   - subtitle: Step subtitle text.
    ///   - isVerified: Whether this step is currently verified.
    ///   - tint: Accent color for verified subtitle.
    ///   - action: Scan action button content.
    /// - Returns: Styled step row view.
    private func verifiedStepRow<ActionLabel: View>(
        title: String,
        subtitle: String,
        isVerified: Bool,
        tint: Color,
        @ViewBuilder action: () -> ActionLabel
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isVerified ? "checkmark.circle.fill" : "clock.fill")
                .foregroundColor(isVerified ? .statusActive : .secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(isVerified ? tint : .secondary)
            }

            Spacer()

            action()
        }
        .padding(.vertical, 4)
    }

    /// Builds the scan or rescan action capsule for checklist rows.
    /// - Parameter text: Button label text.
    /// - Returns: Styled action label view.
    private func stepActionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.navyPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "E8F0FB"))
            .clipShape(Capsule())
    }
}

#Preview {
    AddVehicleView()
        .environmentObject(FleetViewModel())
        .environmentObject(AuthViewModel())
}
