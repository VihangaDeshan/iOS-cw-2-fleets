//
//  ForgotPasswordView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Forgot Password View
struct ForgotPasswordView: View {
    // MARK: - Stored Properties
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var email: String = ""
    @State private var didSendReset: Bool = false
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

            VStack(alignment: .leading, spacing: 18) {
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

                Text("Forgot Password")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(.white)

                Text("Enter your account email to receive a reset link.")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.72))

                Text("EMAIL ADDRESS")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.45))

                TextField("", text: $email, prompt: Text("manager@fleetiq.lk").foregroundStyle(.white.opacity(0.45)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Color.white.opacity(0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Button(action: sendReset) {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isSubmitting ? "Sending..." : "Send Reset")
                            .font(.title2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.statusActive)
                    )
                    .foregroundStyle(.white)
                }
                .disabled(isSubmitting || email.isEmpty)

                if didSendReset {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.chipGreenText)

                        Text("Reset email sent successfully.")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.chipGreenText)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.chipGreenBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !authViewModel.errorMessage.isEmpty {
                    Text(authViewModel.errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.92))
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Private Methods
    /// Triggers the password reset email workflow.
    private func sendReset() {
        guard !isSubmitting else {
            return
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        didSendReset = false
        isSubmitting = true

        Task { @MainActor in
            await authViewModel.sendPasswordReset(email: trimmedEmail)
            didSendReset = authViewModel.errorMessage.isEmpty
            isSubmitting = false
        }
    }

    /// Returns to previous screen.
    private func goBack() {
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
    }
    .environmentObject(AuthViewModel())
}
