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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dangerBanner
                    descriptionSection
                    urgencySection
                    photosSection
                    gpsInfoBanner

                    if normalizedVehicleId.isEmpty {
                        missingVehicleBanner
                    }

                    sendButton
                }
                .padding(16)
            }
            .background(Color.systemGroupedBg)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 112)
            }
            .navigationTitle("Report Fault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MyFaultHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
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
        }
        .alert("Could not send report", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(errorMessage)
        }
        .alert("Report Sent", isPresented: $showPartialSuccessAlert) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text("Report was sent without the photo because upload failed.")
        }
    }

    // MARK: - Sections
    private var dangerBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.statusOverdue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Safety First")
                    .font(.headline.weight(.semibold))

                Text("Park safely before submitting this report. Emergency issues should be marked as High urgency.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.chipRedBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fault Description")
                .font(.headline)

            TextEditor(text: $descriptionText)
                .frame(minHeight: 130)
                .padding(8)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            Text("Describe the issue clearly: noises, warning lights, behavior, and when it started.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var urgencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Urgency")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(FaultUrgency.allCases, id: \.self) { urgency in
                    Button {
                        selectedUrgency = urgency
                    } label: {
                        Text(urgency.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(selectedUrgency == urgency ? urgency.activeBackground : urgency.inactiveBackground)
                            .foregroundColor(selectedUrgency == urgency ? .white : urgency.activeText)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Urgency: \(urgency.title)")
                    .accessibilityHint("Tap to select this urgency level")
                    .accessibilityAddTraits(selectedUrgency == urgency ? .isSelected : [])
                }
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos (Optional)")
                .font(.headline)

            Text("Attach up to 3 images from your photo library. Selected images are uploaded in order.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                PhotoSlotView(item: $photoItem1, image: $photo1, label: "1")
                PhotoSlotView(item: $photoItem2, image: $photo2, label: "2")
                PhotoSlotView(item: $photoItem3, image: $photo3, label: "3")
            }
        }
    }

    private var gpsInfoBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.fill")
                .foregroundColor(.driverGreen)

            VStack(alignment: .leading, spacing: 4) {
                Text("GPS Included")
                    .font(.subheadline.weight(.semibold))

                Text("Your current location is captured automatically when you send the report.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.chipGreenBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var missingVehicleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.fill")
                .foregroundColor(.chipOrangeText)

            Text("No assigned vehicle found. Ask your manager to assign a vehicle before reporting faults.")
                .font(.subheadline)
                .foregroundColor(.chipOrangeText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.chipOrangeBg)
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

                Text(faultViewModel.isSending ? "Sending..." : "Send Fault Report")
                    .font(.headline.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? Color.statusOverdue : Color(.systemGray3))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSubmit)
        .accessibilityLabel("Send fault report")
        .accessibilityHint("Submits report to manager immediately")
        .padding(.top, 4)
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