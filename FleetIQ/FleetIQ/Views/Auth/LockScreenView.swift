//
//  LockScreenView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import LocalAuthentication

// MARK: - Lock Screen View
struct LockScreenView: View {
    // MARK: - Stored Properties
    @AppStorage("isUnlocked") private var isUnlocked: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String = ""

    // MARK: - Body
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.navyPrimary, Color(red: 0.14, green: 0.3, blue: 0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 132, height: 132)

                    Image(systemName: "faceid")
                        .font(.system(size: 58, weight: .medium))
                        .foregroundStyle(.white)

                    Image(systemName: "hexagon")
                        .font(.system(size: 90, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                VStack(spacing: 8) {
                    Text("FleetIQ")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("Tap to unlock with Face ID")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                Button(action: unlockWithBiometrics) {
                    HStack(spacing: 10) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "faceid")
                        }

                        Text(isAuthenticating ? "Authenticating..." : "Unlock FleetIQ")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 24)

                Button(action: unlockWithPasscode) {
                    Text("Use Passcode Instead")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .underline()
                }
                .disabled(isAuthenticating)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
            }
            .padding(.vertical, 40)
        }
    }

    // MARK: - Private Methods
    /// Starts biometric authentication using Face ID.
    private func unlockWithBiometrics() {
        authenticate(
            policy: .deviceOwnerAuthenticationWithBiometrics,
            reason: "Unlock FleetIQ to access fleet data"
        )
    }

    /// Starts authentication flow with passcode fallback.
    private func unlockWithPasscode() {
        authenticate(
            policy: .deviceOwnerAuthentication,
            reason: "Unlock FleetIQ to access fleet data"
        )
    }

    /// Performs local authentication using the provided policy.
    /// - Parameters:
    ///   - policy: The local authentication policy to evaluate.
    ///   - reason: The reason string shown in the system authentication prompt.
    private func authenticate(policy: LAPolicy, reason: String) {
        errorMessage = ""
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(policy, error: &authError) else {
            errorMessage = authError?.localizedDescription ?? "Authentication is not available on this device."
            return
        }

        isAuthenticating = true

        context.evaluatePolicy(policy, localizedReason: reason) { success, evaluationError in
            DispatchQueue.main.async {
                isAuthenticating = false

                if success {
                    isUnlocked = true
                    return
                }

                errorMessage = evaluationError?.localizedDescription ?? "Authentication failed. Please try again."
            }
        }
    }
}

#Preview {
    LockScreenView()
}
