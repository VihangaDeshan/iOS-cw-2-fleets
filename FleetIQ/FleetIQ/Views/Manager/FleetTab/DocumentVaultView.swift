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

// MARK: - Document Vault View
struct DocumentVaultView: View {
    let vehicle: VehicleEntity

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var documentsByType: [String: DocumentEntity] = [:]

    @State private var activeDocType: String?
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
            .navigationTitle("Document Vault")
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(
                isPresented: Binding(
                    get: { activeDocType != nil && !showConfirmSheet },
                    set: { presented in
                        if !presented {
                            selectedPhotoItem = nil
                        }
                    }
                ),
                selection: $selectedPhotoItem,
                matching: .images
            )
            .onChange(of: selectedPhotoItem) { _, item in
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

            Button {
                activeDocType = type
                infoMessage = ""
            } label: {
                Text(document == nil ? "Scan & Upload" : "Replace Document")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.navyPrimary)
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
    private func processPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            activeDocType = nil
            return
        }

        pendingImage = image
        pendingExpiryDate = Date()

        do {
            let lines = try await OCRService.shared.recognizeText(in: image)
            if let detected = OCRService.shared.extractExpiryDate(from: lines) {
                pendingExpiryDate = detected
            }
        } catch {
            // Ignore OCR failures and allow manual expiry selection.
        }

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

            let photoURL = try await firestoreService.uploadPhoto(image, path: storagePath)

            let entity = documentsByType[docType] ?? DocumentEntity(context: context)
            entity.id = entity.id ?? UUID()
            entity.vehicleId = vehicleId
            entity.type = docType
            entity.expiryDate = pendingExpiryDate
            entity.photoURL = photoURL

            // Keep existing vehicle-level expiry fields in sync where available.
            if docType == "insurance" {
                vehicle.insuranceExpiry = pendingExpiryDate
            } else if docType == "licence" {
                vehicle.licenceExpiry = pendingExpiryDate
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

            infoMessage = "\(docType.capitalized) document saved successfully."
            loadDocuments()
        } catch {
            infoMessage = "Failed to save document: \(error.localizedDescription)"
        }

        isSaving = false
        resetPendingState()
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
