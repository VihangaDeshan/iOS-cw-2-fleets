//
//  AddServiceRecordView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Add Service Record View
struct AddServiceRecordView: View {

    // MARK: - Inputs
    let vehicle: VehicleEntity

    // MARK: - Environment
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var serviceLogVM = ServiceLogViewModel()

    // MARK: - Mode
    @State private var selectedMode = 0

    // MARK: - Manual Form State
    @State private var serviceDate = Date()
    @State private var mileage = ""
    @State private var garage = ""
    @State private var selectedTypes = Set<String>()
    @State private var costLKR = ""
    @State private var notes = ""

    // MARK: - OCR State
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhoto: UIImage?
    @State private var isProcessingOCR = false
    @State private var ocrResult: OCRResult?
    @State private var ocrFieldsExtracted = false
    @State private var ocrMessage = ""

    // MARK: - Shared State
    @State private var isSaving = false
    @State private var errorText = ""

    // MARK: - Constants
    let serviceTypes = ["Oil Change", "Brake Service", "Full Service", "Tyre", "Battery", "Other"]

    // MARK: - Body
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Entry Mode", selection: $selectedMode) {
                        Text("Manual Entry").tag(0)
                        Text("Scan Invoice ★").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedMode == 1 {
                    ocrSection
                }

                formDetailsSection
                serviceTypesSection
                notesSection

                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .foregroundColor(.statusOverdue)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Add Service Record")
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
                    .disabled(isSaving || !isFormValid)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    await loadPickedPhoto(item)
                }
            }
            .disabled(isSaving)
        }
    }

    // MARK: - OCR Section

    /// Renders the OCR invoice upload section.
    private var ocrSection: some View {
        Section("VISION OCR SCANNER") {
            if selectedPhoto == nil {
                Button {
                    showPhotoPicker = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                            .foregroundColor(.navyPrimary)

                        Text("Select Invoice Photo")
                            .foregroundColor(.navyPrimary)
                            .fontWeight(.semibold)
                    }
                }
                .accessibilityLabel("Select invoice photo for OCR scanning")
                .accessibilityHint("Opens photo library. OCR runs on device.")

                Text("Vision · VNRecognizeTextRequest · On-device AI · No internet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                if let selectedPhoto {
                    Image(uiImage: selectedPhoto)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .cornerRadius(8)
                        .accessibilityLabel("Selected invoice photo")
                }

                if isProcessingOCR {
                    HStack {
                        ProgressView()
                        Text("Reading invoice...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if ocrFieldsExtracted {
                    Label(ocrMessage, systemImage: "checkmark.circle.fill")
                        .foregroundColor(.statusActive)
                        .font(.subheadline)
                }

                Button("Choose Different Photo") {
                    selectedPhoto = nil
                    selectedPhotoItem = nil
                    ocrFieldsExtracted = false
                    ocrResult = nil
                }
                .foregroundColor(.secondary)
                .font(.subheadline)
            }
        }
    }

    // MARK: - Form Sections

    /// Renders the service details section used in both entry modes.
    private var formDetailsSection: some View {
        Section("SERVICE DETAILS") {
            DatePicker("Service Date", selection: $serviceDate, displayedComponents: .date)

            HStack {
                Text("Mileage (km)")
                Spacer()
                TextField("e.g. 48,240", text: $mileage)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(ocrFieldsExtracted && selectedMode == 1 ? .statusActive : .primary)
            }

            HStack {
                Text("Garage Name")
                Spacer()
                TextField("e.g. Perera Motors", text: $garage)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(ocrFieldsExtracted && selectedMode == 1 ? .statusActive : .primary)
            }

            HStack {
                Text("Total Cost (LKR)")
                Spacer()
                TextField("e.g. 8500", text: $costLKR)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(ocrFieldsExtracted && selectedMode == 1 ? .statusActive : .primary)
            }
        }
    }

    /// Renders multi-select service type rows.
    private var serviceTypesSection: some View {
        Section("SERVICE TYPE") {
            ForEach(serviceTypes, id: \.self) { type in
                Button {
                    if selectedTypes.contains(type) {
                        selectedTypes.remove(type)
                    } else {
                        selectedTypes.insert(type)
                    }
                } label: {
                    HStack {
                        Text(type)
                            .foregroundColor(.primary)

                        Spacer()

                        if selectedTypes.contains(type) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.navyPrimary)
                        }
                    }
                }
                .accessibilityLabel(type)
                .accessibilityAddTraits(selectedTypes.contains(type) ? .isSelected : [])
            }
        }
    }

    /// Renders optional notes input section.
    private var notesSection: some View {
        Section("NOTES (OPTIONAL)") {
            TextField("Any additional notes...", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Validation

    /// Validates required form values.
    private var isFormValid: Bool {
        !mileage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !costLKR.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !selectedTypes.isEmpty
    }

    // MARK: - OCR Processing

    /// Loads the selected photo item and runs OCR extraction.
    /// - Parameter item: Selected photo picker item.
    @MainActor
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        selectedPhoto = image
        await runOCR(on: image)
    }

    /// Runs OCR on a selected invoice image and pre-fills fields.
    /// - Parameter image: Selected invoice image.
    @MainActor
    private func runOCR(on image: UIImage) async {
        isProcessingOCR = true
        ocrFieldsExtracted = false
        ocrMessage = ""

        do {
            let lines = try await OCRService.shared.recognizeText(in: image)
            let result = OCRService.shared.extractInvoiceFields(from: lines)
            let detectedTypes = OCRService.shared.extractServiceTypes(from: lines)
            ocrResult = result

            if let date = result.serviceDate {
                serviceDate = date
            }

            if let cost = result.costLKR {
                costLKR = String(format: "%.0f", cost)
            }

            if let garageName = result.garageName {
                garage = garageName
            }

            if !detectedTypes.isEmpty {
                selectedTypes = detectedTypes
            }

            var extractedCount = 0
            if result.serviceDate != nil { extractedCount += 1 }
            if result.costLKR != nil { extractedCount += 1 }
            if result.garageName != nil { extractedCount += 1 }

            let typeText: String
            if detectedTypes.isEmpty {
                typeText = "No service type detected"
            } else {
                typeText = "Auto-selected: \(detectedTypes.sorted().joined(separator: ", "))"
            }

            ocrMessage = "OCR extracted \(extractedCount) fields. \(typeText)."
            ocrFieldsExtracted = true
        } catch {
            ocrMessage = "Could not read invoice. Enter details manually."
        }

        isProcessingOCR = false
    }

    // MARK: - Save

    /// Persists a new service record using the service log view model.
    private func save() async {
        errorText = ""

        guard let mileageDouble = Double(mileage.replacingOccurrences(of: ",", with: "")),
              let costDouble = Double(costLKR.replacingOccurrences(of: ",", with: "")) else {
            errorText = "Please enter valid numbers for mileage and cost."
            return
        }

        guard let vehicleId = vehicle.id else {
            errorText = "Vehicle ID is missing."
            return
        }

        isSaving = true

        await serviceLogVM.addRecord(
            vehicleId: vehicleId,
            date: serviceDate,
            mileage: mileageDouble,
            garage: garage,
            serviceType: selectedTypes.sorted().joined(separator: ", "),
            cost: costDouble,
            notes: notes,
            fleetId: authViewModel.fleetId
        )

        isSaving = false

        if !serviceLogVM.errorMessage.isEmpty {
            errorText = serviceLogVM.errorMessage
            return
        }

        dismiss()
    }
}
