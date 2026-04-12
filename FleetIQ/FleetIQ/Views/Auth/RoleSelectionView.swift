//
//  RoleSelectionView.swift
//  FleetIQ
//
//  Created by Vihanga Deshan Sammandapperuma on 2026-04-12.
//

import SwiftUI

// MARK: - Role Selection View
struct RoleSelectionView: View {
    // MARK: - Stored Properties
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("faceIDEnabled") private var faceIDEnabled: Bool = false
    @AppStorage("isUnlocked") private var isUnlocked: Bool = false
    @AppStorage("lastSelectedRole") private var lastSelectedRole: String = UserRole.manager.rawValue
    @State private var selectedRole: UserRole = .manager
    @State private var shouldNavigate: Bool = false

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.navyPrimary, Color(red: 0.13, green: 0.28, blue: 0.54)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    VStack(spacing: 8) {
                        Text("Who are you?")
                            .font(.system(size: 46, weight: .heavy))
                            .foregroundStyle(.white)

                        Text("Select your role")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    HStack(spacing: 14) {
                        RoleCardView(
                            title: "Manager",
                            subtitle: "Fleet owner\nFull access",
                            emoji: "💼",
                            isSelected: selectedRole == .manager
                        )
                        .onTapGesture {
                            selectedRole = .manager
                        }

                        RoleCardView(
                            title: "Driver",
                            subtitle: "Assigned to\none vehicle",
                            emoji: "🚗",
                            isSelected: selectedRole == .driver
                        )
                        .onTapGesture {
                            selectedRole = .driver
                        }
                    }
                    .padding(.top, 24)

                    Spacer()

                    Button(action: continueTapped) {
                        Text(buttonTitle)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.blue)
                            )
                    }
                    .padding(.bottom, 24)

                    Button(action: restartOnboarding) {
                        Text("View onboarding again")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .underline()
                    }
                    .padding(.bottom, 18)
                    .navigationDestination(isPresented: $shouldNavigate) {
                        LoginView(role: selectedRole.rawValue)
                    }
                }
                .padding(.horizontal, 22)
            }
            .navigationBarHidden(true)
            .onAppear {
                selectedRole = UserRole(rawValue: lastSelectedRole) ?? .manager
            }
        }
    }

    // MARK: - Private Methods
    /// Moves to login screen for currently selected role.
    private func continueTapped() {
        lastSelectedRole = selectedRole.rawValue
        shouldNavigate = true
    }

    /// Restarts onboarding flow for the current app install.
    private func restartOnboarding() {
        hasSeenOnboarding = false
        faceIDEnabled = false
        isUnlocked = false
        shouldNavigate = false
    }

    // MARK: - Private Computed Properties
    private var buttonTitle: String {
        if selectedRole == .manager {
            return "Continue as Manager ->"
        }

        return "Continue as Driver ->"
    }
}

// MARK: - Role Card View
private struct RoleCardView: View {
    // MARK: - Stored Properties
    let title: String
    let subtitle: String
    let emoji: String
    let isSelected: Bool

    // MARK: - Body
    var body: some View {
        VStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 44))

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            if isSelected {
                Text("Selected ✓")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.navyPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
                    .padding(.top, 2)
            } else {
                Color.clear
                    .frame(height: 34)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(isSelected ? 0.08 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isSelected ? Color.blue : Color.white.opacity(0.14), lineWidth: isSelected ? 3 : 1)
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 8)
    }
}

// MARK: - User Role
private enum UserRole: String {
    case manager
    case driver
}

#Preview {
    RoleSelectionView()
        .environmentObject(AuthViewModel())
}
