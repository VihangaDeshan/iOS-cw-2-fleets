//
//  LoginView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Login View
struct LoginView: View {
    // MARK: - Stored Properties
    let role: String
    var showsBackButton: Bool = true
    var showChangeRoleAction: Bool = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage("lastUsedEmail") private var lastUsedEmail: String = ""

    @State private var email: String = ""
    @State private var password: String = ""
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
                VStack(spacing: 18) {
                    HStack {
                        if showsBackButton {
                            Button(action: backTapped) {
                                Image(systemName: "arrow.left")
                                    .font(.headline.bold())
                                    .foregroundStyle(Color.white.opacity(0.55))
                                    .padding(11)
                                    .background(Circle().fill(Color.white.opacity(0.28)))
                            }
                        }

                        Spacer()
                    }
                    .padding(.top, 6)

                    Text("Sign in")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.white)

                    Text("🚚")
                        .font(.system(size: 44))
                        .padding(.top, 16)

                    Text("Welcome Back")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    Text(role == "manager" ? "Sign in as Manager" : "Sign in as Driver")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.45))

                    VStack(spacing: 14) {
                        labeledFieldTitle("EMAIL ADDRESS")

                        TextField("", text: $email, prompt: Text("manager@fleetiq.lk").foregroundStyle(.white.opacity(0.5)))
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .autocorrectionDisabled(true)
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(Color.white.opacity(0.13))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        labeledFieldTitle("PASSWORD")

                        HStack(spacing: 10) {
                            if showPassword {
                                TextField("", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .textContentType(.password)
                                    .foregroundStyle(.white)
                            } else {
                                SecureField("", text: $password)
                                    .textContentType(.password)
                                    .foregroundStyle(.white)
                            }

                            Button(action: togglePasswordVisibility) {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.42))
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                        HStack {
                            Spacer()

                            NavigationLink(destination: ForgotPasswordView()) {
                                Text("Forgot Password?")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.blue)
                            }
                        }
                    }
                    .padding(.top, 22)

                    Button(action: signIn) {
                        HStack(spacing: 10) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(isSubmitting ? "Signing in..." : "Sign in")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                                .shadow(color: Color.blue.opacity(0.45), radius: 10, x: 0, y: 6)
                        )
                    }
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)
                    .padding(.horizontal, 66)
                    .padding(.top, 10)

                    HStack(spacing: 14) {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)

                        Text("or")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.62))

                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.top, 8)

                    HStack(spacing: 30) {
                        Text("")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.black)
                        
                        Text("G")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                            .overlay {
                                Text("G")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(Color.blue)
                                    .mask(
                                        Rectangle()
                                            .frame(width: 40, height: 16)
                                            .offset(y: 4)
                                    )
                            }
                    }

                    HStack(spacing: 8) {
                        Text("Don't have an account?")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.45))
                        
                        NavigationLink(destination: RegisterView(role: role)) {
                            Text("Register")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.blue)
                        }
                    }
                    .padding(.top, 28)

                    if showChangeRoleAction {
                        NavigationLink(destination: RoleSelectionView()) {
                            Text("Switch role")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .underline()
                        }
                        .padding(.top, 8)
                    }

                    if !authViewModel.errorMessage.isEmpty {
                        Text(authViewModel.errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 26)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard email.isEmpty else {
                return
            }

            email = lastUsedEmail
        }
    }

    // MARK: - Private Methods
    /// Starts sign-in flow for selected role using AuthViewModel.
    private func signIn() {
        guard !isSubmitting else {
            return
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true

        Task { @MainActor in
            await authViewModel.signIn(email: trimmedEmail, password: password, expectedRole: role)

            if authViewModel.isAuthenticated {
                lastUsedEmail = trimmedEmail
            }

            isSubmitting = false
        }
    }

    /// Toggles visibility state for password field.
    private func togglePasswordVisibility() {
        showPassword.toggle()
    }

    /// Returns to the previous screen.
    private func backTapped() {
        dismiss()
    }

    /// Builds a common text label for form fields.
    private func labeledFieldTitle(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.45))

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        LoginView(role: "manager")
    }
    .environmentObject(AuthViewModel())
}
