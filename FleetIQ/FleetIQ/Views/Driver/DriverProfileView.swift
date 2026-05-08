//
//  DriverProfileView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-13.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Driver Profile View
struct DriverProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel

    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @AppStorage("isUnlocked") private var isUnlocked = false

    @State private var phone = ""
    @State private var email = ""
    @State private var isLoadingProfile = false

    private var initials: String {
        let trimmedName = authViewModel.currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "DR" }
        let parts = trimmedName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(trimmedName.prefix(2)).uppercased()
    }

    var body: some View {
        List {
            // MARK: - Avatar Header
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.navyPrimary, Color.navySecondary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.navyPrimary.opacity(0.3), radius: 10, x: 0, y: 5)

                            if isLoadingProfile {
                                ProgressView().tint(.white)
                            } else {
                                Text(initials)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }

                        VStack(spacing: 3) {
                            Text(authViewModel.currentUserName.isEmpty ? "Driver" : authViewModel.currentUserName)
                                .font(.title3.weight(.bold))

                            Text(email.isEmpty ? authViewModel.userRole.capitalized : email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .listRowBackground(Color(.systemGroupedBackground))
            }

            // MARK: - Account
            Section("Account") {
                labeledRow(icon: "person.badge.shield.fill", iconColor: .navyPrimary, label: "Role", value: authViewModel.userRole.capitalized)
                labeledRow(icon: "number", iconColor: Color(hex: "5856D6"), label: "Driver ID", value: shortId(authViewModel.currentUID))
                labeledRow(icon: "car.fill", iconColor: .statusDueSoon, label: "Vehicle", value: authViewModel.assignedVehicleId.isEmpty ? "Not assigned" : authViewModel.assignedVehicleId)
                if !phone.isEmpty {
                    labeledRow(icon: "phone.fill", iconColor: .statusActive, label: "Phone", value: phone)
                }
            }

            // MARK: - Security
            Section("Security") {
                NavigationLink(destination: ChangePasswordView()) {
                    Label {
                        Text("Change Password")
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.blue)
                    }
                }

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "34C759").opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "faceid")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "34C759"))
                    }

                    Toggle("Face ID Lock", isOn: $faceIDEnabled)
                        .onChange(of: faceIDEnabled) { _, enabled in
                            if !enabled { isUnlocked = true }
                        }
                }
            }

            // MARK: - Sign Out
            Section {
                Button(role: .destructive) {
                    authViewModel.signOut()
                } label: {
                    HStack {
                        Spacer()
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadProfile() }
    }

    // MARK: - Helpers

    private func labeledRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            Text(label)
                .foregroundStyle(.primary)

            Spacer()

            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func shortId(_ uid: String) -> String {
        uid.isEmpty ? "—" : String(uid.prefix(12)) + "…"
    }

    private func loadProfile() async {
        guard !authViewModel.currentUID.isEmpty else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }

        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(authViewModel.currentUID)
                .getDocument()
            let data = doc.data() ?? [:]
            phone = data["phone"] as? String ?? ""
            email = data["email"] as? String ?? ""
        } catch {
            // Non-critical — profile still shows from authViewModel state
        }
    }
}

#Preview {
    NavigationStack {
        DriverProfileView()
            .environmentObject(AuthViewModel())
    }
}
