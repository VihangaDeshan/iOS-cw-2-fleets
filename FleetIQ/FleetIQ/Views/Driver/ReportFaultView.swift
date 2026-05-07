//
//  ReportFaultView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Report Fault View
struct ReportFaultView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var faultViewModel = FaultViewModel()

    @State private var descriptionText: String = ""
    @State private var selectedUrgency: FaultUrgency = .high

    @State private var photoItem1: PhotosPickerItem?
    @State private var photoItem2: PhotosPickerItem?
    @State private var photoItem3: PhotosPickerItem?
    @State private var photo1: UIImage?
    @State private var photo2: UIImage?
    @State private var photo3: UIImage?

    @State private var errorMessage: String = ""
    @State private var showErrorAlert: Bool = false
    @State private var submittedFaultPayload: SubmittedFaultPayload?
    @State private var showPartialSuccessAlert: Bool = false

    private var normalizedFleetId: String {
        authViewModel.fleetId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDriverId: String {
        authViewModel.currentUID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedVehicleId: String {
        authViewModel.assignedVehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedPhotos: [UIImage] {
        [photo1, photo2, photo3].compactMap { $0 }
    }

    private var canSubmit: Bool {
        !normalizedFleetId.isEmpty
            && !normalizedDriverId.isEmpty
            && !normalizedVehicleId.isEmpty
            && !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !faultViewModel.isSending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                    dangerBanner
                    
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("DESCRIPTION")
                        descriptionSection
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("URGENCY")
                        urgencySection
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("PHOTOS (OPTIONAL)")
                        photosSection
                    }

                    gpsInfoBanner

                    if normalizedVehicleId.isEmpty {
                        missingVehicleBanner
                    }

                    sendButton
                        .padding(.top, 10)
                }
                .padding(16)
            }
        .background(Color.systemGroupedBg)
        .navigationTitle("Report Fault")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MyFaultHistoryView()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .navigationDestination(item: $submittedFaultPayload) { payload in
            FaultConfirmationView(
                faultId: payload.id,
                submittedAt: payload.submittedAt,
                fleetId: payload.fleetId,
                driverId: payload.driverId,
                vehicleId: payload.vehicleId
            ) {
                resetForm()
            }
        }
        .alert("Could not send report", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Report Sent", isPresented: $showPartialSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Report was sent without the photo because upload failed.")
        }
    }

    // MARK: - Sections
    private var dangerBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.statusOverdue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Safety First")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)

                Text("Park safely before submitting this report. Mark emergency issues as High urgency.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.statusOverdue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $descriptionText)
                .frame(minHeight: 120)
                .font(.subheadline)
                .padding(4)
            
            Divider()

            Text("Describe the issue clearly: noises, warning lights, or unusual behavior.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    private var urgencySection: some View {
        HStack(spacing: 8) {
            ForEach(FaultUrgency.allCases, id: \.self) { urgency in
                Button {
                    selectedUrgency = urgency
                } label: {
                    Text(urgency.title)
                        .font(.caption.weight(.bold))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(selectedUrgency == urgency ? urgency.activeBackground : Color(.systemBackground))
                        .foregroundColor(selectedUrgency == urgency ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selectedUrgency == urgency ? Color.clear : Color(.systemGray5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PhotoSlotView(item: $photoItem1, image: $photo1, label: "1")
                PhotoSlotView(item: $photoItem2, image: $photo2, label: "2")
                PhotoSlotView(item: $photoItem3, image: $photo3, label: "3")
            }
            
            Text("Attach up to 3 images from your library.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var gpsInfoBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundColor(.statusActive)
                .frame(width: 32, height: 32)
                .background(Color.statusActive.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("GPS INCLUDED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                
                Text("Your location is automatically captured.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
    }

    private var missingVehicleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.fill")
                .foregroundColor(.statusDueSoon)

            Text("No assigned vehicle found. Contact manager.")
                .font(.caption.weight(.medium))
                .foregroundColor(.statusDueSoon)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.statusDueSoon.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sendButton: some View {
        Button {
            Task {
                await submitFault()
            }
        } label: {
            HStack(spacing: 8) {
                if faultViewModel.isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }

                Text(faultViewModel.isSending ? "SENDING..." : "SEND FAULT REPORT")
                    .font(.subheadline.weight(.bold))
                    .tracking(0.5)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSubmit ? Color.navyPrimary : Color(.systemGray4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: (canSubmit ? Color.navyPrimary : Color.clear).opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .disabled(!canSubmit)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.horizontal, 4)
    }

    // MARK: - Actions
    private func submitFault() async {
        guard canSubmit else {
            errorMessage = "Please complete all required fields before submitting."
            showErrorAlert = true
            return
        }

        do {
            let createdFaultId = try await faultViewModel.submitFault(
                vehicleId: normalizedVehicleId,
                driverId: normalizedDriverId,
                description: descriptionText,
                urgency: selectedUrgency.rawValue,
                photos: selectedPhotos,
                fleetId: normalizedFleetId
            )

            submittedFaultPayload = SubmittedFaultPayload(
                id: createdFaultId,
                submittedAt: Date(),
                fleetId: normalizedFleetId,
                driverId: normalizedDriverId,
                vehicleId: normalizedVehicleId
            )
            if faultViewModel.photoUploadFailed {
                showPartialSuccessAlert = true
            }
        } catch {
            if !selectedPhotos.isEmpty,
               shouldRetryWithoutPhoto(for: error) {
                do {
                    let createdFaultId = try await faultViewModel.submitFault(
                        vehicleId: normalizedVehicleId,
                        driverId: normalizedDriverId,
                        description: descriptionText,
                        urgency: selectedUrgency.rawValue,
                        photos: [],
                        fleetId: normalizedFleetId
                    )

                    submittedFaultPayload = SubmittedFaultPayload(
                        id: createdFaultId,
                        submittedAt: Date(),
                        fleetId: normalizedFleetId,
                        driverId: normalizedDriverId,
                        vehicleId: normalizedVehicleId
                    )
                    showPartialSuccessAlert = true
                    return
                } catch {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                    return
                }
            }

            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func shouldRetryWithoutPhoto(for error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("does not exist")
            || message.contains("object") && message.contains("photo")
            || message.contains("storage")
    }

    private func resetForm() {
        descriptionText = ""
        selectedUrgency = .high
        photoItem1 = nil
        photoItem2 = nil
        photoItem3 = nil
        photo1 = nil
        photo2 = nil
        photo3 = nil
    }
}

private struct SubmittedFaultPayload: Identifiable, Hashable {
    let id: UUID
    let submittedAt: Date
    let fleetId: String
    let driverId: String
    let vehicleId: String
}

// MARK: - Photo Slot
private struct PhotoSlotView: View {
    @Binding var item: PhotosPickerItem?
    @Binding var image: UIImage?

    let label: String

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        Text("Photo \(label)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 98)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attach photo to fault report")
        .accessibilityHint("Opens photo library")
        .onChange(of: item) { _, newItem in
            Task {
                await loadImage(from: newItem)
            }
        }
    }

    private func loadImage(from newItem: PhotosPickerItem?) async {
        guard let newItem else {
            image = nil
            return
        }

        guard let data = try? await newItem.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }

        image = uiImage
    }
}

// MARK: - Urgency
private enum FaultUrgency: String, CaseIterable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }

    var activeBackground: Color {
        switch self {
        case .low:
            return .statusActive
        case .medium:
            return .statusDueSoon
        case .high:
            return .statusOverdue
        }
    }

    var inactiveBackground: Color {
        switch self {
        case .low:
            return .chipGreenBg
        case .medium:
            return .chipOrangeBg
        case .high:
            return .chipRedBg
        }
    }

    var activeText: Color {
        switch self {
        case .low:
            return .chipGreenText
        case .medium:
            return .chipOrangeText
        case .high:
            return .chipRedText
        }
    }
}

#Preview {
    ReportFaultView()
        .environmentObject(AuthViewModel())
}