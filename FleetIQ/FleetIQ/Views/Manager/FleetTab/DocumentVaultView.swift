//
//  DocumentVaultView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import CoreData
import PhotosUI
import UIKit
import FirebaseFirestore

// MARK: - Document Wallet View
struct DocumentVaultView: View {
    let vehicle: VehicleEntity

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var documentsByType: [String: DocumentEntity] = [:]

    @State private var activeDocType: String?
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var pendingExpiryDate = Date()
    @State private var showConfirmSheet = false

    @State private var isSaving = false
    @State private var infoMessage = ""

    private let firestoreService = FirestoreService.shared

    private let documentTypes: [(key: String, title: String, icon: String)] = [
        ("insurance", "Insurance Certificate", "lock.shield.fill"),
        ("licence", "Revenue Licence", "doc.text.fill"),
        ("emission", "Emission Test", "leaf.fill")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("DOCUMENTS") {
                    ForEach(documentTypes, id: \.key) { item in
                        documentRow(type: item.key, title: item.title, icon: item.icon)
                    }
                }

                if !infoMessage.isEmpty {
                    Section {
                        Text(infoMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Document Wallet")
            .navigationBarTitleDisplayMode(.inline)
            // Use a dedicated Bool flag — avoids conflicts with showConfirmSheet.
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .onChange(of: selectedPhotoItem) { _, item in
                // Dismiss picker immediately before processing.
                showPhotosPicker = false
                guard let item else { return }
                Task {
                    await processPickedPhoto(item)
                }
            }
            .sheet(isPresented: $showConfirmSheet) {
                confirmSheet
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadDocuments)
            .disabled(isSaving)
        }
    }

    private func documentRow(type: String, title: String, icon: String) -> some View {
        let document = documentsByType[type]

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.navyPrimary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    if let expiry = document?.expiryDate {
                        Text("Expiry: \(mediumDate(expiry))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No document uploaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if document?.photoURL?.isEmpty == false {
                    Text("Uploaded")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.statusActive)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.statusActive.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 12) {
                Button {
                    activeDocType = type
                    infoMessage = ""
                    showPhotosPicker = true
                } label: {
                    Text(document == nil ? "Scan & Upload" : "Replace Document")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.navyPrimary)
                }

                // If a document exists, expose a Remove action.
                if document != nil {
                    Button {
                        Task {
                            await removeDocument(ofType: type)
                        }
                    } label: {
                        Text("Remove")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                    }
                }
            }

            // If the document will expire soon, show a renewal prompt.
            if let expiry = document?.expiryDate {
                let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 9999
                if daysUntil <= 30 {
                    HStack {
                        Text("Expires soon — renew to avoid downtime")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Renew") {
                            activeDocType = type
                            infoMessage = ""
                            showPhotosPicker = true
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.navyPrimary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var confirmSheet: some View {
        NavigationStack {
            Form {
                if let pendingImage {
                    Section("PREVIEW") {
                        Image(uiImage: pendingImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Section("EXPIRY DATE") {
                    DatePicker("Expiry", selection: $pendingExpiryDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Confirm Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetPendingState()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveDocument()
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(isSaving)
                }
            }
        }
    }

    @MainActor
    private func processPickedPhoto(_ item: PhotosPickerItem) async {
        // Load raw data on background thread to avoid blocking the main actor.
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            activeDocType = nil
            selectedPhotoItem = nil
            return
        }

        pendingImage = image
        pendingExpiryDate = Date()

        // Run Vision OCR off the main thread — handler.perform() is synchronous
        // and would freeze the UI if called on MainActor.
        let recognizedLines: [String] = await Task.detached(priority: .userInitiated) {
            (try? await OCRService.shared.recognizeText(in: image)) ?? []
        }.value

        if let detected = OCRService.shared.extractExpiryDate(from: recognizedLines) {
            pendingExpiryDate = detected
        }

        // Small delay ensures the photo picker has fully dismissed before
        // presenting the confirm sheet, preventing SwiftUI sheet conflicts.
        try? await Task.sleep(nanoseconds: 300_000_000)
        showConfirmSheet = true
    }

    @MainActor
    private func saveDocument() async {
        guard let vehicleId = vehicle.id else {
            infoMessage = "Vehicle ID is missing."
            resetPendingState()
            return
        }

        guard let docType = activeDocType,
              let image = pendingImage else {
            resetPendingState()
            return
        }

        isSaving = true
        infoMessage = ""

        let docId = "\(vehicleId.uuidString)_\(docType)"

        do {
            let storagePath = try firestoreService.documentPhotoPath(
                fleetId: authViewModel.fleetId,
                vehicleId: vehicleId.uuidString,
                docType: docType
            )

            // If an existing document exists, delete the previous storage object
            // before uploading the replacement (ensures 'replace' semantics).
            if let existing = documentsByType[docType], existing.photoURL?.isEmpty == false {
                try? await firestoreService.deleteStorageObject(path: storagePath)
            }

            let photoURL = try await firestoreService.uploadPhoto(image, path: storagePath)

            let entity = documentsByType[docType] ?? DocumentEntity(context: context)
            let savedDocumentId = entity.id ?? UUID()
            entity.id = savedDocumentId
            entity.vehicleId = vehicleId
            entity.type = docType
            entity.expiryDate = pendingExpiryDate
            entity.photoURL = photoURL

            // Keep existing vehicle-level expiry fields in sync where available.
            if docType == "insurance" {
                vehicle.insuranceExpiry = pendingExpiryDate
                try await firestoreService.updateVehicle(
                    fleetId: authViewModel.fleetId,
                    vehicleId: vehicleId.uuidString,
                    data: ["insuranceExpiry": Timestamp(date: pendingExpiryDate)]
                )
            } else if docType == "licence" {
                vehicle.licenceExpiry = pendingExpiryDate
                try await firestoreService.updateVehicle(
                    fleetId: authViewModel.fleetId,
                    vehicleId: vehicleId.uuidString,
                    data: ["licenceExpiry": Timestamp(date: pendingExpiryDate)]
                )
            }

            try context.save()

            let firestorePayload: [String: Any] = [
                "id": docId,
                "vehicleId": vehicleId.uuidString,
                "type": docType,
                "expiryDate": Timestamp(date: pendingExpiryDate),
                "photoURL": photoURL,
                "updatedAt": Timestamp(date: Date())
            ]

            try await firestoreService.saveDocument(
                firestorePayload,
                fleetId: authViewModel.fleetId,
                docId: docId
            )

            NotificationService.shared.scheduleAllExpiryWarnings(
                vehicleRegistration: vehicle.registration ?? "",
                documentType: docType,
                expiryDate: pendingExpiryDate,
                vehicleId: vehicleId
            )

            infoMessage = "\(docType.capitalized) document saved successfully."
            loadDocuments()
        } catch {
            infoMessage = "Failed to save document: \(error.localizedDescription)"
        }

        isSaving = false
        resetPendingState()
    }

    @MainActor
    private func removeDocument(ofType type: String) async {
        guard let vehicleId = vehicle.id else {
            infoMessage = "Vehicle ID is missing."
            return
        }

        guard let entity = documentsByType[type] else {
            infoMessage = "No document to remove."
            return
        }

        isSaving = true
        infoMessage = ""

        let docId = "\(vehicleId.uuidString)_\(type)"

        do {
            // Delete Firestore document (if any)
            try await firestoreService.deleteDocument(fleetId: authViewModel.fleetId, docId: docId)

            // Delete stored photo; use deterministic path rather than the URL.
            let storagePath = try firestoreService.documentPhotoPath(
                fleetId: authViewModel.fleetId,
                vehicleId: vehicleId.uuidString,
                docType: type
            )
            try? await firestoreService.deleteStorageObject(path: storagePath)

            if type == "insurance" {
                vehicle.insuranceExpiry = nil
                try? await firestoreService.updateVehicle(
                    fleetId: authViewModel.fleetId,
                    vehicleId: vehicleId.uuidString,
                    data: ["insuranceExpiry": NSNull()]
                )
            } else if type == "licence" {
                vehicle.licenceExpiry = nil
                try? await firestoreService.updateVehicle(
                    fleetId: authViewModel.fleetId,
                    vehicleId: vehicleId.uuidString,
                    data: ["licenceExpiry": NSNull()]
                )
            }

            // Remove local Core Data entity
            context.delete(entity)
            try context.save()

            infoMessage = "Document removed."
            loadDocuments()
        } catch {
            infoMessage = "Failed to remove document: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func loadDocuments() {
        guard let vehicleId = vehicle.id else {
            documentsByType = [:]
            return
        }

        let request = DocumentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "vehicleId == %@", vehicleId as CVarArg)

        do {
            let docs = try context.fetch(request)
            var map: [String: DocumentEntity] = [:]
            for doc in docs {
                if let type = doc.type {
                    map[type.lowercased()] = doc
                }
            }
            documentsByType = map
        } catch {
            documentsByType = [:]
        }
    }

    private func resetPendingState() {
        showConfirmSheet = false
        showPhotosPicker = false
        activeDocType = nil
        selectedPhotoItem = nil
        pendingImage = nil
    }

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
