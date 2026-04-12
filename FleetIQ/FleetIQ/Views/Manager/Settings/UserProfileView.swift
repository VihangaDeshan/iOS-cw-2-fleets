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

    @State private var isEditing = false
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

        return "US"
    }

    private var hasUnsavedChanges: Bool {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines) != initialName.trimmingCharacters(in: .whitespacesAndNewlines)
            || phone.trimmingCharacters(in: .whitespacesAndNewlines) != initialPhone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                avatarSection

                profileCard

                securityCard

                logoutButton
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color.systemGroupedBg.ignoresSafeArea())
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        await saveProfile()
                    }
                }
                .disabled(!isEditing || !hasUnsavedChanges || isSaving)
            }
        }
        .task {
            await loadProfile()
        }
        .alert("Profile", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 138, height: 138)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.1)
                } else {
                    Text(initials)
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            Button("Edit") {
                isEditing = true
            }
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity)
    }

    private var profileCard: some View {
        VStack(spacing: 0) {
            profileFieldRow(label: "FULL NAME", text: $fullName, editable: true)
            Divider()
            profileFieldRow(label: "FLEET NAME", text: $fleetName, editable: false)
            Divider()
            profileFieldRow(label: "EMAIL", text: $email, editable: false)
            Divider()
            profileFieldRow(label: "PHONE", text: $phone, editable: true)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    private var securityCard: some View {
        VStack(spacing: 0) {
            Button {
                Task {
                    await sendPasswordReset()
                }
            } label: {
                HStack {
                    Text("Change Password")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.gray.opacity(0.6))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
            }

            Divider()

            HStack {
                Text("Two-Factor Authentication")
                    .font(.system(size: 20, weight: .medium))

                Spacer()

                Toggle("", isOn: $faceIDEnabled)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            authViewModel.signOut()
            dismiss()
        } label: {
            Text("Log Out")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    @ViewBuilder
    private func profileFieldRow(label: String, text: Binding<String>, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: "6F7787"))

            if editable && isEditing {
                TextField("", text: text)
                    .font(.system(size: 20, weight: .medium))
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
            } else {
                Text(text.wrappedValue.isEmpty ? "-" : text.wrappedValue)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private func loadProfile() async {
        guard !authViewModel.currentUID.isEmpty else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let uid = authViewModel.currentUID
            let doc = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]

            let resolvedName = data["name"] as? String ?? ""
            let resolvedEmail = data["email"] as? String ?? Auth.auth().currentUser?.email ?? ""
            let resolvedPhone = data["phone"] as? String ?? ""
            let resolvedFleet = data["fleetName"] as? String ?? authViewModel.fleetId

            fullName = resolvedName
            email = resolvedEmail
            phone = resolvedPhone
            fleetName = resolvedFleet.isEmpty ? authViewModel.fleetId : resolvedFleet

            initialName = fullName
            initialPhone = phone
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
            try await Firestore.firestore().collection("users").document(authViewModel.currentUID).setData([
                "name": trimmedName,
                "phone": trimmedPhone,
                "updatedAt": Timestamp(date: Date())
            ], merge: true)

            fullName = trimmedName
            phone = trimmedPhone
            initialName = trimmedName
            initialPhone = trimmedPhone
            isEditing = false

            alertMessage = "Profile updated successfully."
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func sendPasswordReset() async {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "No email found for password reset."
            showAlert = true
            return
        }

        authViewModel.errorMessage = ""
        await authViewModel.sendPasswordReset(email: email)

        if authViewModel.errorMessage.isEmpty {
            alertMessage = "Password reset email sent."
        } else {
            alertMessage = authViewModel.errorMessage
        }

        showAlert = true
    }
}

#Preview {
    NavigationStack {
        UserProfileView()
            .environmentObject(AuthViewModel())
    }
}
