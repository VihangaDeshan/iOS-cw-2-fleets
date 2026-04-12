//
//  OnboardingView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI
import LocalAuthentication

// MARK: - Onboarding View
struct OnboardingView: View {
    // MARK: - Stored Properties
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("faceIDEnabled") private var faceIDEnabled: Bool = false
    @AppStorage("isUnlocked") private var isUnlocked: Bool = false

    @State private var currentStep: Int = 0
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String = ""

    // MARK: - Body
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.navyPrimary, Color(red: 0.14, green: 0.29, blue: 0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentStep) {
                    OnboardingStepOneView()
                        .tag(0)

                    OnboardingStepTwoView()
                        .tag(1)

                    OnboardingStepThreeView(errorMessage: errorMessage)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == currentStep ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.bottom, 28)

                if currentStep < 2 {
                    Button(action: nextStep) {
                        Text(currentStep == 0 ? "Get Started" : "Continue ->")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                    .padding(.horizontal, 52)
                    .padding(.bottom, 26)
                } else {
                    Button(action: enableFaceID) {
                        HStack(spacing: 10) {
                            if isAuthenticating {
                                ProgressView()
                                    .tint(Color.navyPrimary)
                            }

                            Text(isAuthenticating ? "Enabling..." : "Enable Face ID ->")
                                .font(.title3.weight(.semibold))
                        }
                        .foregroundStyle(Color.navyPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                    }
                    .disabled(isAuthenticating)
                    .padding(.horizontal, 40)

                    Button(action: skipOnboarding) {
                        Text("Skip for now")
                            .font(.title3)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 26)
                }
            }
        }
    }

    // MARK: - Private Methods
    /// Advances onboarding to the next step.
    private func nextStep() {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = min(currentStep + 1, 2)
        }
    }

    /// Completes onboarding without enabling Face ID.
    private func skipOnboarding() {
        hasSeenOnboarding = true
        faceIDEnabled = false
        isUnlocked = true
    }

    /// Requests biometric authentication and enables app lock when successful.
    private func enableFaceID() {
        errorMessage = ""
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            errorMessage = authError?.localizedDescription ?? "Face ID is not available on this device."
            return
        }

        isAuthenticating = true

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Enable Face ID to secure FleetIQ data"
        ) { success, evaluationError in
            DispatchQueue.main.async {
                isAuthenticating = false

                if success {
                    faceIDEnabled = true
                    isUnlocked = true
                    hasSeenOnboarding = true
                    return
                }

                errorMessage = evaluationError?.localizedDescription ?? "Face ID setup failed."
            }
        }
    }
}

// MARK: - Step One
private struct OnboardingStepOneView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("Step 01")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.top, 46)

                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 98, height: 98)
                    .overlay {
                        Text("🚚")
                            .font(.system(size: 42))
                    }

                Text("FleetIQ")
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(.white)

                Text("Intelligent Fleet Management &\nMaintenance for Sri Lanka")
                    .font(.title2)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    OnboardingBulletRow(icon: "📊", text: "Manage all vehicles from one dashboard")
                    OnboardingBulletRow(icon: "⚡", text: "Real-time driver connection via Firebase")
                    OnboardingBulletRow(icon: "📷", text: "Scan paper invoices — no typing needed")
                    OnboardingBulletRow(icon: "📋", text: "Revenue licence expiry alerts avoid fines")
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Step Two
private struct OnboardingStepTwoView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Step 02")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.top, 46)

                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 98, height: 98)
                    .overlay {
                        Text("🚚")
                            .font(.system(size: 42))
                    }

                Text("How FleetIQ works")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(.white)

                Text("Two user types — both connected live")
                    .font(.title2)
                    .foregroundStyle(Color.white.opacity(0.82))

                OnboardingRoleCard(
                    title: "Manager",
                    subtitle: "FLEET OWNER / SUPERVISOR",
                    color: Color.blue.opacity(0.15),
                    border: Color.blue.opacity(0.45),
                    items: [
                        "Sees all vehicles and drivers",
                        "Receives fault reports in real time",
                        "Scans invoices and manages records",
                        "Views analytics and cost reports"
                    ]
                )

                OnboardingRoleCard(
                    title: "Driver",
                    subtitle: "ASSIGNED TO ONE VEHICLE",
                    color: Color.green.opacity(0.12),
                    border: Color.green.opacity(0.4),
                    items: [
                        "Sees only their assigned vehicle",
                        "Reports faults with photos instantly",
                        "Logs trips and fuel fill-ups"
                    ]
                )
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Step Three
private struct OnboardingStepThreeView: View {
    // MARK: - Stored Properties
    let errorMessage: String

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Step 03")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.top, 46)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 118, height: 118)

                    Circle()
                        .trim(from: 0.0, to: 0.28)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 118, height: 118)

                    Image(systemName: "faceid")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text("Secure Your Fleet Data")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(.white)

                Text("FleetIQ protects driver records and\nfinancial data with Face ID")
                    .font(.title2)
                    .foregroundStyle(Color.white.opacity(0.74))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 16) {
                    Text("PROTECTED DATA")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.78))

                    OnboardingProtectedRow(icon: "lock", text: "Driver personal information")
                    OnboardingProtectedRow(icon: "doc.text", text: "Insurance and revenue licence docs")
                    OnboardingProtectedRow(icon: "creditcard", text: "Vehicle cost and financial records")
                    OnboardingProtectedRow(icon: "camera", text: "Fault report photos")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.top, 4)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Shared Components
private struct OnboardingBulletRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title3)
                .frame(width: 34)

            Text(text)
                .font(.title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.13))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct OnboardingRoleCard: View {
    let title: String
    let subtitle: String
    let color: Color
    let border: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(border)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Text(title == "Manager" ? "🧍" : "🚗")
                            .font(.title2)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.58))
                }
            }

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text("✓")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(border)
                        .padding(.top, 1)

                    Text(item)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.95))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(color)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct OnboardingProtectedRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 24)

            Text(text)
                .font(.title3)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    OnboardingView()
}
