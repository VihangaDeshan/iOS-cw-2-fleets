//
//  ChangePasswordView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import FirebaseAuth

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isSuccess = false

    private var isFormValid: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= 6
            && newPassword == confirmPassword
    }

    private var passwordsMatch: Bool {
        confirmPassword.isEmpty || newPassword == confirmPassword
    }

    var body: some View {
        Form {
            Section {
                SecureField("Current Password", text: $currentPassword)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Verify Identity")
            } footer: {
                Text("Enter your current password to confirm your identity before making changes.")
            }

            Section {
                SecureField("New Password", text: $newPassword)
                    .textContentType(.newPassword)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Confirm New Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("New Password")
            } footer: {
                if !passwordsMatch {
                    Label("Passwords do not match.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("Must be at least 6 characters.")
                }
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isLoading {
                    ProgressView()
                } else {
                    Button("Update") {
                        Task { await changePassword() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isFormValid || isLoading)
                }
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                if isSuccess { dismiss() }
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func changePassword() async {
        guard let user = Auth.auth().currentUser,
              let email = user.email else {
            alertTitle = "Error"
            alertMessage = "No active session found. Please sign in again."
            showAlert = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)

        do {
            try await user.reauthenticate(with: credential)
            try await user.updatePassword(to: newPassword)
            alertTitle = "Password Updated"
            alertMessage = "Your password has been changed successfully."
            isSuccess = true
        } catch let error as NSError {
            alertTitle = "Update Failed"
            if error.code == AuthErrorCode.wrongPassword.rawValue {
                alertMessage = "The current password you entered is incorrect."
            } else {
                alertMessage = error.localizedDescription
            }
            isSuccess = false
        }

        showAlert = true
    }
}

#Preview {
    NavigationStack {
        ChangePasswordView()
    }
}
