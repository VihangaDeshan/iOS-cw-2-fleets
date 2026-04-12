//
//  RegisterView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Register View
struct RegisterView: View {
    // MARK: - Stored Properties
    let role: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage("lastUsedEmail") private var lastUsedEmail: String = ""

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var fleetIdentifier: String = ""
    @State private var agreeToTerms: Bool = false
    @State private var showPassword: Bool = false
    @State private var isSubmitting: Bool = false

    // MARK: - Body
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.navyPrimary, Color(red: 0.14, green: 0.3, blue: 0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button(action: goBack) {
                            Image(systemName: "arrow.left")
                                .font(.headline.bold())
                                .foregroundStyle(Color.white.opacity(0.55))
                                .padding(11)
                                .background(Circle().fill(Color.white.opacity(0.28)))
                        }

                        Spacer()
                    }

                    HStack {
                        Spacer()

                        Text("Register")
                            .font(.system(size: 54, weight: .heavy))
                            .foregroundStyle(.white)

                        Spacer()
                    }

                    Text(role == "manager" ? "Create Manager Account" : "Create Driver Account")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 24)

                    Text("You will manage your fleet from this account")
                        .font(.title3)
                        .foregroundStyle(Color.white.opacity(0.42))
                        .padding(.bottom, 10)

                    fieldTitle("FULL NAME")
                    inputField("Kamal Silva", text: $name)

                    fieldTitle("EMAIL ADDRESS")
                    inputField("kamal@silvavans.lk", text: $email, isEmail: true)

                    fieldTitle("PASSWORD")
                    secureInputField("password123", text: $password)

                    fieldTitle("CONFIRM PASSWORD")
                    secureInputField("Re-enter password...", text: $confirmPassword, showEye: false)

                    fieldTitle(role == "manager" ? "FLEET NAME" : "FLEET ID")
                    inputField(role == "manager" ? "Silva Fleet" : "Fleet ID", text: $fleetIdentifier)

                    Button(action: toggleTerms) {
                        HStack(spacing: 10) {
                            Image(systemName: agreeToTerms ? "checkmark.square.fill" : "square")
                                .font(.title2)
                                .foregroundStyle(Color.blue)

                            Text("I agree to the Terms of Service and Privacy Policy")
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.72))

                            Spacer()
                        }
                    }
                    .padding(.top, 4)

                    Button(action: register) {
                        HStack(spacing: 10) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(isSubmitting ? "Creating..." : "Create Account")
                                .font(.title2.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.blue)
                                .shadow(color: Color.blue.opacity(0.45), radius: 10, x: 0, y: 6)
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(
                        isSubmitting ||
                        !agreeToTerms ||
                        name.isEmpty ||
                        email.isEmpty ||
                        password.isEmpty ||
                        confirmPassword.isEmpty ||
                        fleetIdentifier.isEmpty
                    )
                    .padding(.top, 8)

                    if !authViewModel.errorMessage.isEmpty {
                        Text(authViewModel.errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Private Methods
    /// Runs manager registration flow via AuthViewModel.
    private func register() {
        guard !isSubmitting else {
            return
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFleetId = fleetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true

        Task { @MainActor in
            await authViewModel.register(
                name: name,
                email: trimmedEmail,
                password: password,
                confirmPassword: confirmPassword,
                role: role,
                fleetId: trimmedFleetId
            )

            if authViewModel.isAuthenticated {
                lastUsedEmail = trimmedEmail
            }

            isSubmitting = false
        }
    }

    /// Toggles terms agreement checkbox state.
    private func toggleTerms() {
        agreeToTerms.toggle()
    }

    /// Closes register screen and returns to login.
    private func goBack() {
        dismiss()
    }

    /// Returns a field header view in uppercase style.
    private func fieldTitle(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.45))

            Spacer()
        }
    }

    /// Returns a styled text input field.
    private func inputField(_ placeholder: String, text: Binding<String>, isEmail: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.45)))
            .textInputAutocapitalization(isEmail ? .never : .words)
            .autocorrectionDisabled(isEmail)
            .keyboardType(isEmail ? .emailAddress : .default)
            .textContentType(isEmail ? .username : .name)
            .foregroundStyle(.white)
            .padding(16)
            .background(Color.white.opacity(0.13))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Returns a styled secure input field.
    private func secureInputField(_ placeholder: String, text: Binding<String>, showEye: Bool = true) -> some View {
        HStack(spacing: 10) {
            if showPassword {
                TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.45)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textContentType(.newPassword)
                    .foregroundStyle(.white)
            } else {
                SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.45)))
                    .textContentType(.newPassword)
                    .foregroundStyle(.white)
            }

            if showEye {
                Button(action: togglePassword) {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.13))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Toggles visibility state for password fields.
    private func togglePassword() {
        showPassword.toggle()
    }
}

#Preview {
    NavigationStack {
        RegisterView(role: "manager")
    }
    .environmentObject(AuthViewModel())
}
