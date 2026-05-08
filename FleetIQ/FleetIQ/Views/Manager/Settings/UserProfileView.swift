//
//  UserProfileView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel

    @AppStorage("faceIDEnabled") private var faceIDEnabled = false

    @State private var fullName = ""
    @State private var fleetName = ""
    @State private var email = ""
    @State private var phone = ""

    @State private var initialName = ""
    @State private var initialPhone = ""

    @State private var isSaving = false
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    private var initials: String {
        let parts = fullName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        return "MG"
    }

    private var hasUnsavedChanges: Bool {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines) != initialName ||
        phone.trimmingCharacters(in: .whitespacesAndNewlines) != initialPhone
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

                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(initials)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }

                        VStack(spacing: 3) {
                            Text(fullName.isEmpty ? "Manager" : fullName)
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

            // MARK: - Personal Info
            Section {
                // Name — editable
                HStack {
                    Label {
                        Text("Full Name")
                    } icon: {
                        Image(systemName: "person.fill")
                            .foregroundStyle(Color.navyPrimary)
                    }
                    Spacer()
                    TextField("Full Name", text: $fullName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                // Phone — editable
                HStack {
                    Label {
                        Text("Phone")
                    } icon: {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(Color.statusActive)
                    }
                    Spacer()
                    TextField("Phone", text: $phone)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .keyboardType(.phonePad)
                }

                // Fleet Name — read only
                HStack {
                    Label {
                        Text("Fleet Name")
                    } icon: {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(Color(hex: "5856D6"))
                    }
                    Spacer()
                    Text(fleetName.isEmpty ? "—" : fleetName)
                        .foregroundStyle(.secondary)
                }

                // Email — read only
                HStack {
                    Label {
                        Text("Email")
                    } icon: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(Color.statusDueSoon)
                    }
                    Spacer()
                    Text(email.isEmpty ? "—" : email)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } header: {
                Text("Personal Info")
            } footer: {
                Text("Full name and phone number can be edited. Email and fleet name are read-only.")
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
                }
            }

            // MARK: - Sign Out
            Section {
                Button(role: .destructive) {
                    authViewModel.signOut()
                    dismiss()
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
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await saveProfile() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasUnsavedChanges || isSaving)
                }
            }
        }
        .task { await loadProfile() }
        .alert("Profile", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Data

    private func loadProfile() async {
        guard !authViewModel.currentUID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(authViewModel.currentUID)
                .getDocument()
            let data = doc.data() ?? [:]

            fullName = data["name"] as? String ?? ""
            email = data["email"] as? String ?? Auth.auth().currentUser?.email ?? ""
            phone = data["phone"] as? String ?? ""
            let resolvedFleet = data["fleetName"] as? String ?? authViewModel.fleetId
            fleetName = resolvedFleet.isEmpty ? authViewModel.fleetId : resolvedFleet

            initialName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            initialPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func saveProfile() async {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            alertMessage = "Name cannot be empty."
            showAlert = true
            return
        }

        guard !authViewModel.currentUID.isEmpty else {
            alertMessage = "No active user found."
            showAlert = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await Firestore.firestore()
                .collection("users")
                .document(authViewModel.currentUID)
                .setData([
                    "name": trimmedName,
                    "phone": trimmedPhone,
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)

            fullName = trimmedName
            phone = trimmedPhone
            initialName = trimmedName
            initialPhone = trimmedPhone

            alertMessage = "Profile updated successfully."
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        UserProfileView()
            .environmentObject(AuthViewModel())
    }
}
